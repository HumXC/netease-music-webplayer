const std = @import("std");
const websocket = @import("websocket");

const allocator = std.heap.smp_allocator;

const max_ws_message_size = 16 * 1024 * 1024;

// Kept for compatibility with the existing main.zig.
// No global initialization is required by std.http or websocket.zig.
pub fn globalInit() !void {}

pub fn globalDeinit() void {}

fn httpGet(
    io: std.Io,
    url: []const u8,
) ![]u8 {
    var client: std.http.Client = .{
        .allocator = allocator,
        .io = io,
    };
    defer client.deinit();

    var body: std.Io.Writer.Allocating =
        .init(allocator);
    errdefer body.deinit();

    const response = try client.fetch(.{
        .location = .{
            .url = url,
        },
        .response_writer = &body.writer,
    });

    if (response.status.class() != .success) {
        std.debug.print(
            "[cdp] HTTP request failed: {d}\n",
            .{@intFromEnum(response.status)},
        );
        return error.HttpRequestFailed;
    }

    return try body.toOwnedSlice();
}

pub fn findNeteaseTarget(
    io: std.Io,
    port: u16,
) ![]u8 {
    const list_url = try std.fmt.allocPrint(
        allocator,
        "http://127.0.0.1:{d}/json/list",
        .{port},
    );
    defer allocator.free(list_url);

    var attempt: usize = 0;

    while (attempt < 200) : (attempt += 1) {
        const body = httpGet(
            io,
            list_url,
        ) catch {
            try io.sleep(
                .fromMilliseconds(50),
                .awake,
            );
            continue;
        };
        defer allocator.free(body);

        var parsed = std.json.parseFromSlice(
            std.json.Value,
            allocator,
            body,
            .{},
        ) catch {
            try io.sleep(
                .fromMilliseconds(50),
                .awake,
            );
            continue;
        };
        defer parsed.deinit();

        if (parsed.value != .array) {
            try io.sleep(
                .fromMilliseconds(50),
                .awake,
            );
            continue;
        }

        for (parsed.value.array.items) |target| {
            if (target != .object)
                continue;

            const obj = target.object;

            const typ =
                getString(obj, "type");

            if (!std.mem.eql(
                u8,
                typ,
                "page",
            )) {
                continue;
            }

            const page_url =
                getString(obj, "url");

            if (std.mem.indexOf(
                u8,
                page_url,
                "music.163.com",
            ) == null) {
                continue;
            }

            const ws_url =
                getString(
                    obj,
                    "webSocketDebuggerUrl",
                );

            if (ws_url.len == 0)
                continue;

            std.debug.print(
                "[cdp] target: {s}\n",
                .{page_url},
            );

            return try allocator.dupe(
                u8,
                ws_url,
            );
        }

        try io.sleep(
            .fromMilliseconds(50),
            .awake,
        );
    }

    return error.NeteaseTargetNotFound;
}

fn getString(
    obj: std.json.ObjectMap,
    key: []const u8,
) []const u8 {
    const value =
        obj.get(key) orelse return "";

    return if (value == .string)
        value.string
    else
        "";
}

fn appendJsonString(
    list: *std.ArrayList(u8),
    value: []const u8,
) !void {
    try list.append(
        allocator,
        '"',
    );

    for (value) |ch| {
        switch (ch) {
            '"' => try list.appendSlice(
                allocator,
                "\\\"",
            ),

            '\\' => try list.appendSlice(
                allocator,
                "\\\\",
            ),

            '\n' => try list.appendSlice(
                allocator,
                "\\n",
            ),

            '\r' => try list.appendSlice(
                allocator,
                "\\r",
            ),

            '\t' => try list.appendSlice(
                allocator,
                "\\t",
            ),

            '\x08' => try list.appendSlice(
                allocator,
                "\\b",
            ),

            '\x0c' => try list.appendSlice(
                allocator,
                "\\f",
            ),

            0...0x07,
            0x0b,
            0x0e...0x1f,
            => {
                var tmp: [6]u8 = undefined;

                const escaped =
                    try std.fmt.bufPrint(
                        &tmp,
                        "\\u{x:0>4}",
                        .{ch},
                    );

                try list.appendSlice(
                    allocator,
                    escaped,
                );
            },

            else => try list.append(
                allocator,
                ch,
            ),
        }
    }

    try list.append(
        allocator,
        '"',
    );
}

const WsAddress = struct {
    host: []const u8,
    port: u16,
    path: []const u8,
    tls: bool,
};

fn parseWebSocketUrl(
    url: []const u8,
) !WsAddress {
    var rest: []const u8 = undefined;
    var tls = false;
    var default_port: u16 = 80;

    if (std.mem.startsWith(
        u8,
        url,
        "ws://",
    )) {
        rest = url["ws://".len..];
    } else if (std.mem.startsWith(
        u8,
        url,
        "wss://",
    )) {
        rest = url["wss://".len..];
        tls = true;
        default_port = 443;
    } else {
        return error.UnsupportedWebSocketScheme;
    }

    if (rest.len == 0)
        return error.InvalidWebSocketUrl;

    const slash_index =
        std.mem.indexOfScalar(
            u8,
            rest,
            '/',
        );

    const authority =
        if (slash_index) |index|
            rest[0..index]
        else
            rest;

    const path =
        if (slash_index) |index|
            rest[index..]
        else
            "/";

    if (authority.len == 0)
        return error.InvalidWebSocketUrl;

    // IPv6 literal:
    //
    //   ws://[::1]:9222/devtools/page/...
    if (authority[0] == '[') {
        const closing =
            std.mem.indexOfScalar(
                u8,
                authority,
                ']',
            ) orelse
            return error.InvalidWebSocketUrl;

        const host =
            authority[1..closing];

        if (host.len == 0)
            return error.InvalidWebSocketUrl;

        var port =
            default_port;

        const remaining =
            authority[closing + 1 ..];

        if (remaining.len != 0) {
            if (remaining[0] != ':' or
                remaining.len == 1)
            {
                return error.InvalidWebSocketUrl;
            }

            port = try std.fmt.parseInt(
                u16,
                remaining[1..],
                10,
            );
        }

        return .{
            .host = host,
            .port = port,
            .path = path,
            .tls = tls,
        };
    }

    // Chrome normally gives us:
    //
    // ws://127.0.0.1:PORT/devtools/page/ID
    const colon =
        std.mem.lastIndexOfScalar(
            u8,
            authority,
            ':',
        );

    if (colon) |index| {
        if (index == 0 or
            index + 1 >= authority.len)
        {
            return error.InvalidWebSocketUrl;
        }

        const host =
            authority[0..index];

        const port =
            try std.fmt.parseInt(
                u16,
                authority[index + 1 ..],
                10,
            );

        return .{
            .host = host,
            .port = port,
            .path = path,
            .tls = tls,
        };
    }

    return .{
        .host = authority,
        .port = default_port,
        .path = path,
        .tls = tls,
    };
}

pub const Client = struct {
    ws: websocket.Client,
    io: std.Io,

    next_id: u32 = 1,

    mutex: std.Io.Mutex = .init,

    pub fn connect(
        io: std.Io,
        ws_url: []const u8,
    ) !Client {
        const address =
            try parseWebSocketUrl(ws_url);

        std.debug.print(
            "[cdp] connecting websocket {s}:{d}{s}...\n",
            .{
                address.host,
                address.port,
                address.path,
            },
        );

        var ws = try websocket.Client.init(
            io,
            allocator,
            .{
                .host = address.host,
                .port = address.port,
                .tls = address.tls,

                .connect_timeout_ms = 5000,

                .buffer_size = 16 * 1024,
                .max_size = max_ws_message_size,
            },
        );
        errdefer ws.deinit();

        try ws.handshake(
            address.path,
            .{
                .timeout_ms = 5000,
            },
        );

        std.debug.print(
            "[cdp] connected\n",
            .{},
        );

        return .{
            .ws = ws,
            .io = io,
        };
    }

    pub fn deinit(
        self: *Client,
    ) void {
        self.mutex.lockUncancelable(
            self.io,
        );
        defer self.mutex.unlock(
            self.io,
        );

        self.ws.close(.{}) catch {};
        self.ws.deinit();
    }

    fn sendTextUnlocked(
        self: *Client,
        payload: []const u8,
    ) !void {
        // websocket.zig currently declares its client
        // write API as []u8 even though the payload is
        // not modified by this call.
        try self.ws.write(
            @constCast(payload),
        );
    }

    fn receiveTextUnlocked(
        self: *Client,
    ) ![]u8 {
        while (true) {
            const maybe_message =
                try self.ws.read();

            const message =
                maybe_message orelse continue;

            switch (message.type) {
                .text => {
                    // Message storage belongs to websocket.zig
                    // and may be reused by the next read, so
                    // duplicate it for the caller.
                    return try allocator.dupe(
                        u8,
                        message.data,
                    );
                },

                .close => return error.WebSocketClosed,

                else => continue,
            }
        }
    }

    fn commandUnlocked(
        self: *Client,
        method: []const u8,
        params_json: []const u8,
    ) !std.json.Parsed(std.json.Value) {
        const id =
            self.next_id;

        self.next_id += 1;

        var request: std.ArrayList(u8) =
            .empty;

        defer request.deinit(
            allocator,
        );

        try request.appendSlice(
            allocator,
            "{\"id\":",
        );

        var id_buf: [32]u8 =
            undefined;

        const id_text =
            try std.fmt.bufPrint(
                &id_buf,
                "{d}",
                .{id},
            );

        try request.appendSlice(
            allocator,
            id_text,
        );

        try request.appendSlice(
            allocator,
            ",\"method\":",
        );

        try appendJsonString(
            &request,
            method,
        );

        try request.appendSlice(
            allocator,
            ",\"params\":",
        );

        try request.appendSlice(
            allocator,
            params_json,
        );

        try request.append(
            allocator,
            '}',
        );

        try self.sendTextUnlocked(
            request.items,
        );

        while (true) {
            const message =
                try self.receiveTextUnlocked();

            defer allocator.free(
                message,
            );

            var parsed =
                std.json.parseFromSlice(
                    std.json.Value,
                    allocator,
                    message,
                    .{},
                ) catch
                    continue;

            if (parsed.value != .object) {
                parsed.deinit();
                continue;
            }

            const response_id =
                parsed.value.object.get(
                    "id",
                ) orelse {
                    // CDP event / notification.
                    parsed.deinit();
                    continue;
                };

            if (response_id != .integer or
                response_id.integer != id)
            {
                parsed.deinit();
                continue;
            }

            return parsed;
        }
    }

    pub fn command(
        self: *Client,
        method: []const u8,
        params_json: []const u8,
    ) !std.json.Parsed(std.json.Value) {
        self.mutex.lockUncancelable(
            self.io,
        );
        defer self.mutex.unlock(
            self.io,
        );

        return try self.commandUnlocked(
            method,
            params_json,
        );
    }

    fn evaluateUnlocked(
        self: *Client,
        expression: []const u8,
    ) !std.json.Parsed(std.json.Value) {
        var params: std.ArrayList(u8) =
            .empty;

        defer params.deinit(
            allocator,
        );

        try params.appendSlice(
            allocator,
            "{\"expression\":",
        );

        try appendJsonString(
            &params,
            expression,
        );

        try params.appendSlice(
            allocator,
            ",\"returnByValue\":true," ++ "\"awaitPromise\":true," ++ "\"userGesture\":true}",
        );

        return try self.commandUnlocked(
            "Runtime.evaluate",
            params.items,
        );
    }

    pub fn evaluate(
        self: *Client,
        expression: []const u8,
    ) !std.json.Parsed(std.json.Value) {
        self.mutex.lockUncancelable(
            self.io,
        );
        defer self.mutex.unlock(
            self.io,
        );

        return try self.evaluateUnlocked(
            expression,
        );
    }

    pub fn evaluateString(
        self: *Client,
        expression: []const u8,
    ) !?[]u8 {
        self.mutex.lockUncancelable(
            self.io,
        );
        defer self.mutex.unlock(
            self.io,
        );

        var response =
            try self.evaluateUnlocked(
                expression,
            );

        defer response.deinit();

        try checkError(
            &response,
        );

        const remote =
            getRemoteObject(
                &response,
            ) orelse
            return null;

        const value =
            remote.object.get(
                "value",
            ) orelse
            return null;

        if (value != .string)
            return null;

        return try allocator.dupe(
            u8,
            value.string,
        );
    }

    pub fn evaluateBool(
        self: *Client,
        expression: []const u8,
    ) !bool {
        self.mutex.lockUncancelable(
            self.io,
        );
        defer self.mutex.unlock(
            self.io,
        );

        var response =
            try self.evaluateUnlocked(
                expression,
            );

        defer response.deinit();

        try checkError(
            &response,
        );

        const remote =
            getRemoteObject(
                &response,
            ) orelse
            return false;

        const value =
            remote.object.get(
                "value",
            ) orelse
            return false;

        return switch (value) {
            .bool => |v| v,
            else => false,
        };
    }

    pub fn addScriptOnNewDocument(
        self: *Client,
        source: []const u8,
    ) !void {
        self.mutex.lockUncancelable(
            self.io,
        );
        defer self.mutex.unlock(
            self.io,
        );

        var params: std.ArrayList(u8) =
            .empty;

        defer params.deinit(
            allocator,
        );

        try params.appendSlice(
            allocator,
            "{\"source\":",
        );

        try appendJsonString(
            &params,
            source,
        );

        try params.append(
            allocator,
            '}',
        );

        var response =
            try self.commandUnlocked(
                "Page.addScriptToEvaluateOnNewDocument",
                params.items,
            );

        defer response.deinit();

        try checkError(
            &response,
        );
    }

    pub fn bringToFront(
        self: *Client,
    ) !void {
        var response =
            try self.command(
                "Page.bringToFront",
                "{}",
            );

        defer response.deinit();

        try checkError(
            &response,
        );
    }

    pub fn closeBrowser(
        self: *Client,
    ) void {
        self.mutex.lockUncancelable(
            self.io,
        );
        defer self.mutex.unlock(
            self.io,
        );

        const id =
            self.next_id;

        self.next_id += 1;

        var request: std.ArrayList(u8) =
            .empty;

        defer request.deinit(
            allocator,
        );

        request.appendSlice(
            allocator,
            "{\"id\":",
        ) catch
            return;

        var id_buf: [32]u8 =
            undefined;

        const id_text =
            std.fmt.bufPrint(
                &id_buf,
                "{d}",
                .{id},
            ) catch
                return;

        request.appendSlice(
            allocator,
            id_text,
        ) catch
            return;

        request.appendSlice(
            allocator,
            ",\"method\":\"Browser.close\"," ++ "\"params\":{}}",
        ) catch
            return;

        self.sendTextUnlocked(
            request.items,
        ) catch {};
    }
};

pub fn checkError(
    response: *const std.json.Parsed(
        std.json.Value,
    ),
) !void {
    if (response.value != .object)
        return error.InvalidCdpResponse;

    if (response.value.object.get(
        "error",
    )) |value| {
        std.debug.print(
            "[cdp] protocol error: {any}\n",
            .{value},
        );

        return error.CdpProtocolError;
    }

    const outer =
        response.value.object.get(
            "result",
        ) orelse
        return;

    if (outer != .object)
        return;

    if (outer.object.get(
        "exceptionDetails",
    )) |details| {
        std.debug.print(
            "[cdp] JavaScript exception: {any}\n",
            .{details},
        );

        return error.JavaScriptException;
    }
}

fn getRemoteObject(
    response: *const std.json.Parsed(
        std.json.Value,
    ),
) ?std.json.Value {
    if (response.value != .object)
        return null;

    const outer =
        response.value.object.get(
            "result",
        ) orelse
        return null;

    if (outer != .object)
        return null;

    const remote =
        outer.object.get(
            "result",
        ) orelse
        return null;

    if (remote != .object)
        return null;

    return remote;
}
