const std = @import("std");
const cdp = @import("cdp.zig");

const allocator = std.heap.smp_allocator;

const browser_polyfills = @embedFile("assets/browser_polyfills.js");
const metadata_script = @embedFile("assets/metadata.js");

pub const RepeatMode = enum {
    random,
    order,
    heart,
    list,
    single,
};

pub const Snapshot = struct {
    title: [256]u8 = [_]u8{0} ** 256,
    title_len: usize = 0,

    artist: [256]u8 = [_]u8{0} ** 256,
    artist_len: usize = 0,

    playing: bool = false,
    liked: bool = false,
    muted: bool = false,

    repeat_mode: [64]u8 = [_]u8{0} ** 64,
    repeat_mode_len: usize = 0,

    pub fn titleSlice(self: *const Snapshot) []const u8 {
        return self.title[0..self.title_len];
    }

    pub fn artistSlice(self: *const Snapshot) []const u8 {
        return self.artist[0..self.artist_len];
    }

    pub fn repeatModeSlice(self: *const Snapshot) []const u8 {
        return self.repeat_mode[0..self.repeat_mode_len];
    }
};

pub const Controller = struct {
    client: *cdp.Client,

    pub fn init(client: *cdp.Client) Controller {
        return .{ .client = client };
    }

    pub fn initialize(self: *Controller) !void {
        {
            var response = try self.client.command("Runtime.enable", "{}");
            defer response.deinit();
            try cdp.checkError(&response);
        }

        {
            var response = try self.client.command("Page.enable", "{}");
            defer response.deinit();
            try cdp.checkError(&response);
        }

        {
            var response = try self.client.evaluate(browser_polyfills);
            defer response.deinit();
            try cdp.checkError(&response);
        }

        try self.client.addScriptOnNewDocument(browser_polyfills);

        const ready = try self.client.evaluateBool(
            "typeof window.__neteaseTrayAction === 'function'",
        );

        if (!ready) {
            std.debug.print(
                "[player] polyfill initialization incomplete, retrying\n",
                .{},
            );

            var response =
                try self.client.evaluate(
                    browser_polyfills,
                );
            defer response.deinit();

            try cdp.checkError(&response);

            const retry_ready =
                try self.client.evaluateBool(
                    "typeof window.__neteaseTrayAction === 'function'",
                );

            if (!retry_ready)
                return error.PlayerScriptInitializationFailed;
        }

        std.debug.print("[player] browser polyfills installed\n", .{});
    }

    pub fn refresh(self: *Controller) !Snapshot {
        const result = try self.client.evaluateString(metadata_script);
        const json = result orelse return Snapshot{};
        defer allocator.free(json);

        return parseSnapshot(json);
    }

    pub fn show(self: *Controller) void {
        self.client.bringToFront() catch |err| {
            std.debug.print("[player] bringToFront: {s}\n", .{@errorName(err)});
        };
    }

    pub fn playPause(self: *Controller) void {
        self.action(
            "window.__neteaseTrayAction ? window.__neteaseTrayAction('playPause') : false",
        );
    }

    pub fn play(self: *Controller) void {
        self.action(
            "window.__neteaseTrayAction ? window.__neteaseTrayAction('play') : false",
        );
    }

    pub fn previous(self: *Controller) void {
        self.action(
            "window.__neteaseTrayAction ? window.__neteaseTrayAction('previous') : false",
        );
    }

    pub fn next(self: *Controller) void {
        self.action(
            "window.__neteaseTrayAction ? window.__neteaseTrayAction('next') : false",
        );
    }

    pub fn toggleLike(self: *Controller) void {
        self.action(
            "window.__neteaseTrayAction ? window.__neteaseTrayAction('toggleLike') : false",
        );
    }

    pub fn toggleMute(self: *Controller) void {
        self.action(
            "window.__neteaseTrayAction ? window.__neteaseTrayAction('toggleMute') : false",
        );
    }

    pub fn setRepeatMode(self: *Controller, mode: RepeatMode) void {
        const script = switch (mode) {
            .random => "window.__neteaseTrayAction ? window.__neteaseTrayAction('setRepeatMode', '随机播放') : false",
            .order => "window.__neteaseTrayAction ? window.__neteaseTrayAction('setRepeatMode', '顺序播放') : false",
            .heart => "window.__neteaseTrayAction ? window.__neteaseTrayAction('setRepeatMode', '心动模式') : false",
            .list => "window.__neteaseTrayAction ? window.__neteaseTrayAction('setRepeatMode', '列表循环') : false",
            .single => "window.__neteaseTrayAction ? window.__neteaseTrayAction('setRepeatMode', '单曲循环') : false",
        };

        self.action(script);
    }

    pub fn closeBrowser(self: *Controller) void {
        self.client.closeBrowser();
    }

    fn action(self: *Controller, script: []const u8) void {
        const handled = self.client.evaluateBool(script) catch |err| {
            std.debug.print("[player] action failed: {s}\n", .{@errorName(err)});
            return;
        };

        if (!handled) self.show();
    }
};

fn copyField(dst: []u8, len_out: *usize, src: []const u8) void {
    const count = @min(dst.len, src.len);
    @memcpy(dst[0..count], src[0..count]);
    len_out.* = count;
}

fn parseSnapshot(json_text: []const u8) Snapshot {
    var snapshot: Snapshot = .{};

    var parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_text,
        .{},
    ) catch return snapshot;
    defer parsed.deinit();

    if (parsed.value != .object) return snapshot;
    const obj = parsed.value.object;

    if (obj.get("title")) |v| {
        if (v == .string)
            copyField(&snapshot.title, &snapshot.title_len, v.string);
    }

    if (obj.get("artist")) |v| {
        if (v == .string)
            copyField(&snapshot.artist, &snapshot.artist_len, v.string);
    }

    if (obj.get("playing")) |v| {
        if (v == .bool) snapshot.playing = v.bool;
    }

    if (obj.get("liked")) |v| {
        if (v == .bool) snapshot.liked = v.bool;
    }

    if (obj.get("muted")) |v| {
        if (v == .bool) snapshot.muted = v.bool;
    }

    if (obj.get("repeatMode")) |v| {
        if (v == .string)
            copyField(
                &snapshot.repeat_mode,
                &snapshot.repeat_mode_len,
                v.string,
            );
    }

    return snapshot;
}
