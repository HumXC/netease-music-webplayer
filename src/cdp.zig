const std = @import("std");

const c = @cImport({
    @cInclude("curl/curl.h");
});

const allocator = std.heap.smp_allocator;

const CurlBuffer = struct {
    data: std.ArrayList(u8) = .empty,

    fn deinit(self: *CurlBuffer) void {
        self.data.deinit(allocator);
    }
};

fn curlWriteCallback(
    ptr: ?*anyopaque,
    size: usize,
    nmemb: usize,
    userdata: ?*anyopaque,
) callconv(.c) usize {
    if (ptr == null or userdata == null) return 0;
    const total = size * nmemb;
    if (total == 0) return 0;

    const buffer: *CurlBuffer = @ptrCast(@alignCast(userdata.?));
    const bytes: [*]const u8 = @ptrCast(ptr.?);
    buffer.data.appendSlice(allocator, bytes[0..total]) catch return 0;
    return total;
}

pub fn globalInit() !void {
    try curlCheck(c.curl_global_init(c.CURL_GLOBAL_ALL));
}

pub fn globalDeinit() void {
    c.curl_global_cleanup();
}

fn curlCheck(result: c.CURLcode) !void {
    if (result == c.CURLE_OK) return;
    std.debug.print(
        "[curl] {s}\n",
        .{std.mem.span(c.curl_easy_strerror(result))},
    );
    return error.CurlError;
}

fn httpGet(url: [:0]const u8) ![]u8 {
    const curl = c.curl_easy_init() orelse return error.CurlInitFailed;
    defer c.curl_easy_cleanup(curl);

    var buffer: CurlBuffer = .{};
    errdefer buffer.deinit();

    try curlCheck(c.curl_easy_setopt(curl, c.CURLOPT_URL, url.ptr));
    try curlCheck(c.curl_easy_setopt(curl, c.CURLOPT_WRITEFUNCTION, curlWriteCallback));
    try curlCheck(c.curl_easy_setopt(curl, c.CURLOPT_WRITEDATA, &buffer));
    try curlCheck(c.curl_easy_setopt(curl, c.CURLOPT_CONNECTTIMEOUT_MS, @as(c_long, 3000)));
    try curlCheck(c.curl_easy_setopt(curl, c.CURLOPT_TIMEOUT_MS, @as(c_long, 5000)));
    try curlCheck(c.curl_easy_perform(curl));

    return try buffer.data.toOwnedSlice(allocator);
}

pub fn findNeteaseTarget(io: std.Io, port: u16) ![]u8 {
    const list_url = try std.fmt.allocPrintSentinel(
        allocator,
        "http://127.0.0.1:{d}/json/list",
        .{port},
        0,
    );
    defer allocator.free(list_url);

    var attempt: usize = 0;
    while (attempt < 200) : (attempt += 1) {
        const body = httpGet(list_url) catch {
            try io.sleep(.fromMilliseconds(50), .awake);
            continue;
        };
        defer allocator.free(body);

        var parsed = std.json.parseFromSlice(
            std.json.Value,
            allocator,
            body,
            .{},
        ) catch {
            try io.sleep(.fromMilliseconds(50), .awake);
            continue;
        };
        defer parsed.deinit();

        if (parsed.value != .array) {
            try io.sleep(.fromMilliseconds(50), .awake);
            continue;
        }

        for (parsed.value.array.items) |target| {
            if (target != .object) continue;
            const obj = target.object;

            const typ = getString(obj, "type");
            if (!std.mem.eql(u8, typ, "page")) continue;

            const page_url = getString(obj, "url");
            if (std.mem.indexOf(u8, page_url, "music.163.com") == null) continue;

            const ws_url = getString(obj, "webSocketDebuggerUrl");
            if (ws_url.len == 0) continue;

            std.debug.print("[cdp] target: {s}\n", .{page_url});
            return try allocator.dupe(u8, ws_url);
        }

        try io.sleep(.fromMilliseconds(50), .awake);
    }

    return error.NeteaseTargetNotFound;
}

fn getString(obj: std.json.ObjectMap, key: []const u8) []const u8 {
    const value = obj.get(key) orelse return "";
    return if (value == .string) value.string else "";
}

fn appendJsonString(list: *std.ArrayList(u8), value: []const u8) !void {
    try list.append(allocator, '"');

    for (value) |ch| {
        switch (ch) {
            '"' => try list.appendSlice(allocator, "\\\""),
            '\\' => try list.appendSlice(allocator, "\\\\"),
            '\n' => try list.appendSlice(allocator, "\\n"),
            '\r' => try list.appendSlice(allocator, "\\r"),
            '\t' => try list.appendSlice(allocator, "\\t"),
            '\x08' => try list.appendSlice(allocator, "\\b"),
            '\x0c' => try list.appendSlice(allocator, "\\f"),
            0...0x07, 0x0b, 0x0e...0x1f => {
                var tmp: [6]u8 = undefined;
                const escaped = try std.fmt.bufPrint(&tmp, "\\u{x:0>4}", .{ch});
                try list.appendSlice(allocator, escaped);
            },
            else => try list.append(allocator, ch),
        }
    }

    try list.append(allocator, '"');
}

pub const Client = struct {
    curl: *c.CURL,
    io: std.Io,
    next_id: u32 = 1,
    mutex: std.Io.Mutex = .init,

    pub fn connect(io: std.Io, ws_url: []const u8) !Client {
        const curl = c.curl_easy_init() orelse return error.CurlInitFailed;
        errdefer c.curl_easy_cleanup(curl);

        const url_z = try allocator.dupeZ(u8, ws_url);
        defer allocator.free(url_z);

        try curlCheck(c.curl_easy_setopt(curl, c.CURLOPT_URL, url_z.ptr));
        try curlCheck(c.curl_easy_setopt(curl, c.CURLOPT_CONNECT_ONLY, @as(c_long, 2)));
        try curlCheck(c.curl_easy_setopt(curl, c.CURLOPT_CONNECTTIMEOUT_MS, @as(c_long, 5000)));
        try curlCheck(c.curl_easy_setopt(curl, c.CURLOPT_TIMEOUT_MS, @as(c_long, 5000)));

        std.debug.print("[cdp] connecting websocket...\n", .{});
        try curlCheck(c.curl_easy_perform(curl));
        std.debug.print("[cdp] connected\n", .{});

        return .{
            .curl = curl,
            .io = io,
        };
    }

    pub fn deinit(self: *Client) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        var sent: usize = 0;
        _ = c.curl_ws_send(self.curl, "", 0, &sent, 0, c.CURLWS_CLOSE);
        c.curl_easy_cleanup(self.curl);
    }

    fn sendTextUnlocked(self: *Client, payload: []const u8) !void {
        var offset: usize = 0;
        while (offset < payload.len) {
            var sent: usize = 0;
            const result = c.curl_ws_send(
                self.curl,
                payload.ptr + offset,
                payload.len - offset,
                &sent,
                0,
                c.CURLWS_TEXT,
            );

            if (result == c.CURLE_AGAIN) {
                try self.io.sleep(.fromMilliseconds(10), .awake);
                continue;
            }

            try curlCheck(result);

            if (sent == 0) {
                try self.io.sleep(.fromMilliseconds(10), .awake);
                continue;
            }

            offset += sent;
        }
    }

    fn receiveTextUnlocked(self: *Client) ![]u8 {
        var output: std.ArrayList(u8) = .empty;
        errdefer output.deinit(allocator);

        while (true) {
            var buffer: [64 * 1024]u8 = undefined;
            var received: usize = 0;
            var meta: ?*const c.struct_curl_ws_frame = null;

            const result = c.curl_ws_recv(
                self.curl,
                &buffer,
                buffer.len,
                &received,
                &meta,
            );

            if (result == c.CURLE_AGAIN) {
                try self.io.sleep(.fromMilliseconds(10), .awake);
                continue;
            }

            try curlCheck(result);
            const frame = meta orelse continue;

            if ((frame.flags & c.CURLWS_CLOSE) != 0)
                return error.WebSocketClosed;

            if ((frame.flags & c.CURLWS_PING) != 0 or
                (frame.flags & c.CURLWS_PONG) != 0)
                continue;

            if ((frame.flags & c.CURLWS_TEXT) == 0 and
                (frame.flags & c.CURLWS_CONT) == 0)
                continue;

            if (received != 0)
                try output.appendSlice(allocator, buffer[0..received]);

            if (frame.bytesleft == 0)
                return try output.toOwnedSlice(allocator);
        }
    }

    fn commandUnlocked(
        self: *Client,
        method: []const u8,
        params_json: []const u8,
    ) !std.json.Parsed(std.json.Value) {
        const id = self.next_id;
        self.next_id += 1;

        var request: std.ArrayList(u8) = .empty;
        defer request.deinit(allocator);

        try request.appendSlice(allocator, "{\"id\":");

        var id_buf: [32]u8 = undefined;
        const id_text = try std.fmt.bufPrint(&id_buf, "{d}", .{id});
        try request.appendSlice(allocator, id_text);

        try request.appendSlice(allocator, ",\"method\":");
        try appendJsonString(&request, method);
        try request.appendSlice(allocator, ",\"params\":");
        try request.appendSlice(allocator, params_json);
        try request.append(allocator, '}');

        try self.sendTextUnlocked(request.items);

        while (true) {
            const message = try self.receiveTextUnlocked();
            defer allocator.free(message);

            var parsed = std.json.parseFromSlice(
                std.json.Value,
                allocator,
                message,
                .{},
            ) catch continue;

            if (parsed.value != .object) {
                parsed.deinit();
                continue;
            }

            const response_id = parsed.value.object.get("id") orelse {
                parsed.deinit();
                continue;
            };

            if (response_id != .integer or response_id.integer != id) {
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
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return try self.commandUnlocked(method, params_json);
    }

    fn evaluateUnlocked(
        self: *Client,
        expression: []const u8,
    ) !std.json.Parsed(std.json.Value) {
        var params: std.ArrayList(u8) = .empty;
        defer params.deinit(allocator);

        try params.appendSlice(allocator, "{\"expression\":");
        try appendJsonString(&params, expression);
        try params.appendSlice(
            allocator,
            ",\"returnByValue\":true,\"awaitPromise\":true,\"userGesture\":true}",
        );

        return try self.commandUnlocked("Runtime.evaluate", params.items);
    }

    pub fn evaluate(
        self: *Client,
        expression: []const u8,
    ) !std.json.Parsed(std.json.Value) {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return try self.evaluateUnlocked(expression);
    }

    pub fn evaluateString(
        self: *Client,
        expression: []const u8,
    ) !?[]u8 {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        var response = try self.evaluateUnlocked(expression);
        defer response.deinit();

        try checkError(&response);

        const remote = getRemoteObject(&response) orelse return null;
        const value = remote.object.get("value") orelse return null;
        if (value != .string) return null;
        return try allocator.dupe(u8, value.string);
    }

    pub fn evaluateBool(
        self: *Client,
        expression: []const u8,
    ) !bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        var response = try self.evaluateUnlocked(expression);
        defer response.deinit();

        try checkError(&response);

        const remote = getRemoteObject(&response) orelse return false;
        const value = remote.object.get("value") orelse return false;
        return switch (value) {
            .bool => |v| v,
            else => false,
        };
    }

    pub fn addScriptOnNewDocument(
        self: *Client,
        source: []const u8,
    ) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        var params: std.ArrayList(u8) = .empty;
        defer params.deinit(allocator);

        try params.appendSlice(allocator, "{\"source\":");
        try appendJsonString(&params, source);
        try params.append(allocator, '}');

        var response = try self.commandUnlocked(
            "Page.addScriptToEvaluateOnNewDocument",
            params.items,
        );
        defer response.deinit();

        try checkError(&response);
    }

    pub fn bringToFront(self: *Client) !void {
        var response = try self.command("Page.bringToFront", "{}");
        defer response.deinit();
        try checkError(&response);
    }

    pub fn closeBrowser(self: *Client) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const id = self.next_id;
        self.next_id += 1;

        var request: std.ArrayList(u8) = .empty;
        defer request.deinit(allocator);

        request.appendSlice(allocator, "{\"id\":") catch return;
        var id_buf: [32]u8 = undefined;
        const id_text = std.fmt.bufPrint(&id_buf, "{d}", .{id}) catch return;
        request.appendSlice(allocator, id_text) catch return;
        request.appendSlice(
            allocator,
            ",\"method\":\"Browser.close\",\"params\":{}}",
        ) catch return;

        self.sendTextUnlocked(request.items) catch {};
    }
};

pub fn checkError(
    response: *const std.json.Parsed(std.json.Value),
) !void {
    if (response.value != .object)
        return error.InvalidCdpResponse;

    if (response.value.object.get("error")) |value| {
        std.debug.print("[cdp] protocol error: {any}\n", .{value});
        return error.CdpProtocolError;
    }

    const outer = response.value.object.get("result") orelse return;
    if (outer == .object) {
        if (outer.object.get("exceptionDetails")) |details| {
            std.debug.print("[cdp] JavaScript exception: {any}\n", .{details});
            return error.JavaScriptException;
        }
    }
}

fn getRemoteObject(
    response: *const std.json.Parsed(std.json.Value),
) ?std.json.Value {
    if (response.value != .object) return null;

    const outer = response.value.object.get("result") orelse return null;
    if (outer != .object) return null;

    if (outer.object.get("exceptionDetails") != null) return null;

    const remote = outer.object.get("result") orelse return null;
    if (remote != .object) return null;

    return remote;
}
