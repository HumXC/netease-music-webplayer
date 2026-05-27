const std = @import("std");
const gtk = @import("gtk");
const glib = @import("glib");
const webkit = @import("webkit");
const goose = @import("goose");

const default_url = "https://music.163.com/st/webplayer";
const chrome_linux_ua = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";
const tray_icon_ico = @embedFile("assets/netease-favicon.ico");
const browser_polyfills = @embedFile("assets/browser_polyfills.js");

var main_window: ?*gtk.ApplicationWindow = null;
var data_dir: ?[:0]const u8 = null;
var cache_dir: ?[:0]const u8 = null;
var cookies_file: ?[:0]const u8 = null;
var window_state_file: ?[:0]const u8 = null;
var app_io: ?std.Io = null;
var window_width: i32 = 1200;
var window_height: i32 = 820;
var start_silent = false;
var start_autoplay = false;
var autoplay_attempts: u8 = 0;

const TrayAction = enum(usize) {
    show = 1,
    play_pause = 2,
    previous = 3,
    next = 4,
    toggle_like = 5,
    repeat_random = 7,
    repeat_order = 8,
    repeat_heart = 9,
    repeat_list = 10,
    repeat_single = 11,
    refresh_now_playing = 12,
    quit = 13,
};

const GStr = goose.core.value.GStr;
const GPath = goose.core.value.GPath;
const PropVariant = goose.core.value.Value.Variant(union(enum) {
    label: GStr,
    type: GStr,
    icon_name: GStr,
    children_display: GStr,
    enabled: bool,
    visible: bool,
});
const PropEntry = struct { key: GStr, value: PropVariant };
const PropDict = goose.core.value.Value.Dict(GStr, PropVariant, []const PropEntry);
const EventVariant = goose.core.value.Value.Variant(union(enum) {
    str: GStr,
    bool: bool,
    int: i32,
});
const GroupProp = struct { id: i32, props: PropDict };
const PropertyUpdate = struct { id: i32, props: PropDict };
const PropertyUpdateArray = goose.core.value.Value.Array(PropertyUpdate);
const GStrArray = goose.core.value.Value.Array(GStr);
const RemovedProp = struct { id: i32, props: GStrArray };
const RemovedPropArray = goose.core.value.Value.Array(RemovedProp);
const IntArray = goose.core.value.Value.Array(i32);
const ByteArray = goose.core.value.Value.Array(u8);
const Pixmap = struct { width: i32, height: i32, bytes: ByteArray };
const PixmapArray = goose.core.value.Value.Array(Pixmap);
const ToolTip = struct { icon_name: GStr, icon_pixmap: PixmapArray, title: GStr, description: GStr };
const MenuEvent = struct { id: i32, event_id: GStr, data: EventVariant, timestamp: u32 };

var now_playing_label_buf: [512:0]u8 = [_:0]u8{0} ** 512;
var now_playing_label_len: usize = 1;
var now_playing_is_playing: ?bool = null;
var now_playing_liked: ?bool = null;
var now_playing_repeat_mode_buf: [64:0]u8 = [_:0]u8{0} ** 64;
var now_playing_repeat_mode_len: usize = 0;
var now_playing_label_prop = [_]PropEntry{
    .{ .key = GStr.new("type"), .value = PropVariant.new(.{ .type = GStr.new("standard") }) },
    .{ .key = GStr.new("label"), .value = PropVariant.new(.{ .label = GStr.new("-") }) },
    .{ .key = GStr.new("enabled"), .value = PropVariant.new(.{ .enabled = false }) },
    .{ .key = GStr.new("visible"), .value = PropVariant.new(.{ .visible = true }) },
};

var menu_props_play_pause = [_]PropEntry{
    .{ .key = GStr.new("type"), .value = PropVariant.new(.{ .type = GStr.new("standard") }) },
    .{ .key = GStr.new("label"), .value = PropVariant.new(.{ .label = GStr.new("播放") }) },
    .{ .key = GStr.new("icon-name"), .value = PropVariant.new(.{ .icon_name = GStr.new("media-playback-start-symbolic") }) },
    .{ .key = GStr.new("enabled"), .value = PropVariant.new(.{ .enabled = true }) },
    .{ .key = GStr.new("visible"), .value = PropVariant.new(.{ .visible = true }) },
};
const menu_props_previous = [_]PropEntry{
    .{ .key = GStr.new("type"), .value = PropVariant.new(.{ .type = GStr.new("standard") }) },
    .{ .key = GStr.new("label"), .value = PropVariant.new(.{ .label = GStr.new("上一曲") }) },
    .{ .key = GStr.new("icon-name"), .value = PropVariant.new(.{ .icon_name = GStr.new("media-skip-backward-symbolic") }) },
    .{ .key = GStr.new("enabled"), .value = PropVariant.new(.{ .enabled = true }) },
    .{ .key = GStr.new("visible"), .value = PropVariant.new(.{ .visible = true }) },
};
const menu_props_next = [_]PropEntry{
    .{ .key = GStr.new("type"), .value = PropVariant.new(.{ .type = GStr.new("standard") }) },
    .{ .key = GStr.new("label"), .value = PropVariant.new(.{ .label = GStr.new("下一曲") }) },
    .{ .key = GStr.new("icon-name"), .value = PropVariant.new(.{ .icon_name = GStr.new("media-skip-forward-symbolic") }) },
    .{ .key = GStr.new("enabled"), .value = PropVariant.new(.{ .enabled = true }) },
    .{ .key = GStr.new("visible"), .value = PropVariant.new(.{ .visible = true }) },
};
var menu_props_like = [_]PropEntry{
    .{ .key = GStr.new("type"), .value = PropVariant.new(.{ .type = GStr.new("standard") }) },
    .{ .key = GStr.new("label"), .value = PropVariant.new(.{ .label = GStr.new("添加喜欢") }) },
    .{ .key = GStr.new("icon-name"), .value = PropVariant.new(.{ .icon_name = GStr.new("love") }) },
    .{ .key = GStr.new("enabled"), .value = PropVariant.new(.{ .enabled = true }) },
    .{ .key = GStr.new("visible"), .value = PropVariant.new(.{ .visible = true }) },
};
var menu_props_repeat = [_]PropEntry{
    .{ .key = GStr.new("type"), .value = PropVariant.new(.{ .type = GStr.new("standard") }) },
    .{ .key = GStr.new("label"), .value = PropVariant.new(.{ .label = GStr.new("播放模式") }) },
    .{ .key = GStr.new("icon-name"), .value = PropVariant.new(.{ .icon_name = GStr.new("media-playlist-repeat-symbolic") }) },
    .{ .key = GStr.new("children-display"), .value = PropVariant.new(.{ .children_display = GStr.new("submenu") }) },
    .{ .key = GStr.new("enabled"), .value = PropVariant.new(.{ .enabled = true }) },
    .{ .key = GStr.new("visible"), .value = PropVariant.new(.{ .visible = true }) },
};
const menu_props_repeat_random = [_]PropEntry{
    .{ .key = GStr.new("type"), .value = PropVariant.new(.{ .type = GStr.new("standard") }) },
    .{ .key = GStr.new("label"), .value = PropVariant.new(.{ .label = GStr.new("随机播放") }) },
    .{ .key = GStr.new("icon-name"), .value = PropVariant.new(.{ .icon_name = GStr.new("media-playlist-shuffle-symbolic") }) },
    .{ .key = GStr.new("enabled"), .value = PropVariant.new(.{ .enabled = true }) },
    .{ .key = GStr.new("visible"), .value = PropVariant.new(.{ .visible = true }) },
};
const menu_props_repeat_order = [_]PropEntry{
    .{ .key = GStr.new("type"), .value = PropVariant.new(.{ .type = GStr.new("standard") }) },
    .{ .key = GStr.new("label"), .value = PropVariant.new(.{ .label = GStr.new("顺序播放") }) },
    .{ .key = GStr.new("icon-name"), .value = PropVariant.new(.{ .icon_name = GStr.new("media-playlist-consecutive-symbolic") }) },
    .{ .key = GStr.new("enabled"), .value = PropVariant.new(.{ .enabled = true }) },
    .{ .key = GStr.new("visible"), .value = PropVariant.new(.{ .visible = true }) },
};
const menu_props_repeat_heart = [_]PropEntry{
    .{ .key = GStr.new("type"), .value = PropVariant.new(.{ .type = GStr.new("standard") }) },
    .{ .key = GStr.new("label"), .value = PropVariant.new(.{ .label = GStr.new("心动模式") }) },
    .{ .key = GStr.new("icon-name"), .value = PropVariant.new(.{ .icon_name = GStr.new("love") }) },
    .{ .key = GStr.new("enabled"), .value = PropVariant.new(.{ .enabled = true }) },
    .{ .key = GStr.new("visible"), .value = PropVariant.new(.{ .visible = true }) },
};
const menu_props_repeat_list = [_]PropEntry{
    .{ .key = GStr.new("type"), .value = PropVariant.new(.{ .type = GStr.new("standard") }) },
    .{ .key = GStr.new("label"), .value = PropVariant.new(.{ .label = GStr.new("列表循环") }) },
    .{ .key = GStr.new("icon-name"), .value = PropVariant.new(.{ .icon_name = GStr.new("media-playlist-repeat-symbolic") }) },
    .{ .key = GStr.new("enabled"), .value = PropVariant.new(.{ .enabled = true }) },
    .{ .key = GStr.new("visible"), .value = PropVariant.new(.{ .visible = true }) },
};
const menu_props_repeat_single = [_]PropEntry{
    .{ .key = GStr.new("type"), .value = PropVariant.new(.{ .type = GStr.new("standard") }) },
    .{ .key = GStr.new("label"), .value = PropVariant.new(.{ .label = GStr.new("单曲循环") }) },
    .{ .key = GStr.new("icon-name"), .value = PropVariant.new(.{ .icon_name = GStr.new("media-playlist-repeat-song-symbolic") }) },
    .{ .key = GStr.new("enabled"), .value = PropVariant.new(.{ .enabled = true }) },
    .{ .key = GStr.new("visible"), .value = PropVariant.new(.{ .visible = true }) },
};
const menu_props_show = [_]PropEntry{
    .{ .key = GStr.new("type"), .value = PropVariant.new(.{ .type = GStr.new("standard") }) },
    .{ .key = GStr.new("label"), .value = PropVariant.new(.{ .label = GStr.new("显示窗口") }) },
    .{ .key = GStr.new("icon-name"), .value = PropVariant.new(.{ .icon_name = GStr.new("view-restore-symbolic") }) },
    .{ .key = GStr.new("enabled"), .value = PropVariant.new(.{ .enabled = true }) },
    .{ .key = GStr.new("visible"), .value = PropVariant.new(.{ .visible = true }) },
};
const menu_props_quit = [_]PropEntry{
    .{ .key = GStr.new("type"), .value = PropVariant.new(.{ .type = GStr.new("standard") }) },
    .{ .key = GStr.new("label"), .value = PropVariant.new(.{ .label = GStr.new("退出") }) },
    .{ .key = GStr.new("icon-name"), .value = PropVariant.new(.{ .icon_name = GStr.new("window-close-symbolic") }) },
    .{ .key = GStr.new("enabled"), .value = PropVariant.new(.{ .enabled = true }) },
    .{ .key = GStr.new("visible"), .value = PropVariant.new(.{ .visible = true }) },
};
const menu_root_props = [_]PropEntry{
    .{ .key = GStr.new("children-display"), .value = PropVariant.new(.{ .children_display = GStr.new("submenu") }) },
};
const empty_menu_ids = [_]i32{};
const menu_root_update_ids = [_]i32{0};
const empty_removed_props = [_]RemovedProp{};
var menu_revision: u32 = 1;
const empty_pixmaps = [_]Pixmap{};

var tray_icon_argb: []u8 = &.{};
var tray_icon_pixmap_storage: [1]Pixmap = undefined;
var tray_icon_pixmaps: []const Pixmap = &empty_pixmaps;

const root_child_ids = [_]i32{ 100, 1, 2, 3, 4, 5, 11, 12 };
const repeat_child_ids = [_]i32{ 6, 7, 8, 9, 10 };
const no_child_ids = [_]i32{};

const MenuLayout = struct {
    pub const SIGNATURE = "(ia{sv}av)";

    id: i32,
    props: []const PropEntry,
    child_ids: []const i32,

    pub fn ser(self: MenuLayout, w: *goose.core.value.DBusWriter) !void {
        try w.padTo(8);
        try goose.core.value.Serializer.trySerialize(i32, self.id, w);
        try goose.core.value.Serializer.trySerialize(PropDict, PropDict.new(self.props), w);

        try w.padTo(4);
        const len_pos = w.buffer.items.len;
        try w.writeInt(u32, 0);
        const start = w.buffer.items.len;
        for (self.child_ids) |child_id| {
            const child = menuLayoutById(child_id);
            try w.writeSignatureOf(MenuLayout);
            try child.ser(w);
        }
        w.writeU32At(len_pos, @intCast(w.buffer.items.len - start));
    }
};

fn menuLayoutById(id: i32) MenuLayout {
    return switch (id) {
        0 => .{ .id = 0, .props = &menu_root_props, .child_ids = &root_child_ids },
        100 => .{ .id = 100, .props = &now_playing_label_prop, .child_ids = &no_child_ids },
        1 => .{ .id = 1, .props = &menu_props_play_pause, .child_ids = &no_child_ids },
        2 => .{ .id = 2, .props = &menu_props_previous, .child_ids = &no_child_ids },
        3 => .{ .id = 3, .props = &menu_props_next, .child_ids = &no_child_ids },
        4 => .{ .id = 4, .props = &menu_props_like, .child_ids = &no_child_ids },
        5 => .{ .id = 5, .props = &menu_props_repeat, .child_ids = &repeat_child_ids },
        6 => .{ .id = 6, .props = &menu_props_repeat_random, .child_ids = &no_child_ids },
        7 => .{ .id = 7, .props = &menu_props_repeat_order, .child_ids = &no_child_ids },
        8 => .{ .id = 8, .props = &menu_props_repeat_heart, .child_ids = &no_child_ids },
        9 => .{ .id = 9, .props = &menu_props_repeat_list, .child_ids = &no_child_ids },
        10 => .{ .id = 10, .props = &menu_props_repeat_single, .child_ids = &no_child_ids },
        11 => .{ .id = 11, .props = &menu_props_show, .child_ids = &no_child_ids },
        else => .{ .id = 12, .props = &menu_props_quit, .child_ids = &no_child_ids },
    };
}

const menu_group_props = [_]GroupProp{
    .{ .id = 0, .props = PropDict.new(&menu_root_props) },
    .{ .id = 100, .props = PropDict.new(&now_playing_label_prop) },
    .{ .id = 1, .props = PropDict.new(&menu_props_play_pause) },
    .{ .id = 2, .props = PropDict.new(&menu_props_previous) },
    .{ .id = 3, .props = PropDict.new(&menu_props_next) },
    .{ .id = 4, .props = PropDict.new(&menu_props_like) },
    .{ .id = 5, .props = PropDict.new(&menu_props_repeat) },
    .{ .id = 6, .props = PropDict.new(&menu_props_repeat_random) },
    .{ .id = 7, .props = PropDict.new(&menu_props_repeat_order) },
    .{ .id = 8, .props = PropDict.new(&menu_props_repeat_heart) },
    .{ .id = 9, .props = PropDict.new(&menu_props_repeat_list) },
    .{ .id = 10, .props = PropDict.new(&menu_props_repeat_single) },
    .{ .id = 11, .props = PropDict.new(&menu_props_show) },
    .{ .id = 12, .props = PropDict.new(&menu_props_quit) },
};

const tray_bus_name = "org.kde.StatusNotifierItem.netease_music_webplayer";
const tray_path = "/StatusNotifierItem";
const menu_path = "/StatusNotifierItem/Menu";

fn scheduleTrayAction(action: TrayAction) void {
    glib.MainContext.invoke(null, onTrayAction, @ptrFromInt(@intFromEnum(action)));
}

fn onTrayAction(data: ?*anyopaque) callconv(.c) c_int {
    const action: TrayAction = @enumFromInt(@intFromPtr(data.?));
    switch (action) {
        .show => if (main_window) |existing_window| {
            const window = existing_window.as(gtk.Window);
            window.as(gtk.Widget).show();
            window.present();
        },
        .play_pause => evalPlayerScriptHidden("window.__neteaseTrayAction && window.__neteaseTrayAction('playPause')"),
        .previous => evalPlayerScriptHidden("window.__neteaseTrayAction && window.__neteaseTrayAction('previous')"),
        .next => evalPlayerScriptHidden("window.__neteaseTrayAction && window.__neteaseTrayAction('next')"),
        .toggle_like => evalPlayerScriptHidden("window.__neteaseTrayAction && window.__neteaseTrayAction('toggleLike')"),
        .repeat_random => evalPlayerScriptHidden("window.__neteaseTrayAction && window.__neteaseTrayAction('setRepeatMode', '随机播放')"),
        .repeat_order => evalPlayerScriptHidden("window.__neteaseTrayAction && window.__neteaseTrayAction('setRepeatMode', '顺序播放')"),
        .repeat_heart => evalPlayerScriptHidden("window.__neteaseTrayAction && window.__neteaseTrayAction('setRepeatMode', '心动模式')"),
        .repeat_list => evalPlayerScriptHidden("window.__neteaseTrayAction && window.__neteaseTrayAction('setRepeatMode', '列表循环')"),
        .repeat_single => evalPlayerScriptHidden("window.__neteaseTrayAction && window.__neteaseTrayAction('setRepeatMode', '单曲循环')"),
        .refresh_now_playing => evalPlayerScriptHidden("window.__neteasePublishNowPlaying && window.__neteasePublishNowPlaying()"),
        .quit => if (main_window) |existing_window| existing_window.as(gtk.Window).destroy(),
    }
    return 0;
}

fn evalPlayerScript(script: [:0]const u8) void {
    if (main_window) |existing_window| {
        const window = existing_window.as(gtk.Window);
        window.as(gtk.Widget).show();
    }
    evalPlayerScriptHidden(script);
}

fn evalPlayerScriptHidden(script: [:0]const u8) void {
    if (current_web_view) |view| {
        view.evaluateJavascript(script, -1, null, null, null, null, null);
    }
}

fn autoplayTick(_: ?*anyopaque) callconv(.c) c_int {
    if (autoplay_attempts == 0) return 0;
    autoplay_attempts -= 1;
    evalPlayerScriptHidden("window.__neteaseTrayAction && window.__neteaseTrayAction('play')");
    return if (autoplay_attempts == 0) 0 else 1;
}

var current_web_view: ?*webkit.WebView = null;
var tray_conn: ?*goose.Connection = null;

fn formatNowPlayingLabel(buf: *[512:0]u8, title: []const u8, _: []const u8, _: []const u8) [:0]const u8 {
    return if (title.len != 0 and !std.mem.eql(u8, title, "title"))
        std.fmt.bufPrintZ(buf, "{s}", .{title}) catch "没有正在播放的歌曲"
    else
        std.fmt.bufPrintZ(buf, "没有正在播放的歌曲", .{}) catch "没有正在播放的歌曲";
}

fn updateNowPlayingLabel(title: []const u8, artist: []const u8, album: []const u8) bool {
    var new_label_buf: [512:0]u8 = [_:0]u8{0} ** 512;
    const text = formatNowPlayingLabel(&new_label_buf, title, artist, album);

    if (std.mem.eql(u8, now_playing_label_buf[0..now_playing_label_len], text)) return false;

    @memcpy(now_playing_label_buf[0..text.len], text);
    now_playing_label_buf[text.len] = 0;
    now_playing_label_len = text.len;
    now_playing_label_prop[1].value = PropVariant.new(.{ .label = GStr.new(now_playing_label_buf[0..now_playing_label_len :0]) });
    return true;
}

fn updatePlaybackState(playing: bool) bool {
    if (now_playing_is_playing) |old| {
        if (old == playing) return false;
    }
    now_playing_is_playing = playing;
    if (playing) {
        menu_props_play_pause[1].value = PropVariant.new(.{ .label = GStr.new("暂停") });
        menu_props_play_pause[2].value = PropVariant.new(.{ .icon_name = GStr.new("media-playback-pause-symbolic") });
    } else {
        menu_props_play_pause[1].value = PropVariant.new(.{ .label = GStr.new("播放") });
        menu_props_play_pause[2].value = PropVariant.new(.{ .icon_name = GStr.new("media-playback-start-symbolic") });
    }
    return true;
}

fn updateLikeState(liked: bool) bool {
    if (now_playing_liked) |old| {
        if (old == liked) return false;
    }
    now_playing_liked = liked;
    if (liked) {
        menu_props_like[1].value = PropVariant.new(.{ .label = GStr.new("取消喜欢") });
        menu_props_like[2].value = PropVariant.new(.{ .icon_name = GStr.new("heart-filled-symbolic") });
    } else {
        menu_props_like[1].value = PropVariant.new(.{ .label = GStr.new("添加喜欢") });
        menu_props_like[2].value = PropVariant.new(.{ .icon_name = GStr.new("love") });
    }
    return true;
}

fn updateRepeatMode(mode: []const u8) bool {
    if (mode.len == 0) return false;
    if (std.mem.eql(u8, now_playing_repeat_mode_buf[0..now_playing_repeat_mode_len], mode)) return false;
    const label = std.fmt.bufPrintZ(&now_playing_repeat_mode_buf, "{s}", .{mode}) catch return false;
    now_playing_repeat_mode_len = label.len;
    menu_props_repeat[1].value = PropVariant.new(.{ .label = GStr.new(now_playing_repeat_mode_buf[0..now_playing_repeat_mode_len :0]) });
    if (std.mem.indexOf(u8, mode, "单") != null or std.mem.indexOf(u8, mode, "one") != null) {
        menu_props_repeat[2].value = PropVariant.new(.{ .icon_name = GStr.new("media-playlist-repeat-song-symbolic") });
    } else if (std.mem.indexOf(u8, mode, "随机") != null or std.mem.indexOf(u8, mode, "shuffle") != null) {
        menu_props_repeat[2].value = PropVariant.new(.{ .icon_name = GStr.new("media-playlist-shuffle-symbolic") });
    } else {
        menu_props_repeat[2].value = PropVariant.new(.{ .icon_name = GStr.new("media-playlist-repeat-symbolic") });
    }
    return true;
}

fn commitMenuUpdateIfNeeded(changed: bool) void {
    if (!changed) return;
    menu_revision +%= 1;
    if (menu_revision == 0) menu_revision = 1;
    emitMenuUpdated();
}

const metadata_script = @embedFile("assets/metadata.js");

fn pollNowPlaying(_: ?*anyopaque) callconv(.c) c_int {
    if (current_web_view) |view| {
        view.evaluateJavascript(metadata_script, -1, null, null, null, onNowPlayingJavascript, null);
    }
    return 1;
}

fn emitMenuSignal(conn: *goose.Connection, member: [:0]const u8, payload: anytype) void {
    var encoder = goose.message.BodyEncoder.encode(conn.__allocator, payload) catch |err| {
        std.debug.print("[tray] failed to encode {s}: {s}\n", .{ member, @errorName(err) });
        return;
    };
    defer encoder.deinit();

    const serial = conn.serial_counter;
    conn.serial_counter += 1;
    const header = goose.core.MessageHeader{
        .message_type = .Signal,
        .flags = 0,
        .proto_version = 1,
        .body_length = @intCast(encoder.body().len),
        .serial = serial,
        .header_fields = @constCast(&[_]goose.core.HeaderField{
            .{ .code = .Path, .value = .{ .Path = menu_path } },
            .{ .code = .Interface, .value = .{ .Interface = "com.canonical.dbusmenu" } },
            .{ .code = .Member, .value = .{ .Member = member } },
            .{ .code = .Signature, .value = .{ .Signature = encoder.signature() } },
        }),
    };
    const msg = goose.core.Message.new(header, encoder.body());
    conn.sendMessage(msg) catch |err| {
        std.debug.print("[tray] failed to emit {s}: {s}\n", .{ member, @errorName(err) });
    };
}

fn emitMenuUpdated() void {
    const conn = tray_conn orelse return;

    // The menu item set is stable, but the disabled "now playing" item's label
    // changes.  Some StatusNotifier/dbusmenu hosts only refetch cached item
    // properties on ItemsPropertiesUpdated, while others react to LayoutUpdated.
    // Emit both so tray menus update reliably across hosts.
    const changed_props = [_]PropertyUpdate{
        .{ .id = 100, .props = PropDict.new(&now_playing_label_prop) },
        .{ .id = 1, .props = PropDict.new(&menu_props_play_pause) },
        .{ .id = 4, .props = PropDict.new(&menu_props_like) },
        .{ .id = 5, .props = PropDict.new(&menu_props_repeat) },
    };
    emitMenuSignal(conn, "ItemsPropertiesUpdated", .{
        PropertyUpdateArray.new(&changed_props),
        RemovedPropArray.new(&empty_removed_props),
    });
    emitMenuSignal(conn, "LayoutUpdated", .{ menu_revision, @as(i32, 0) });
}

fn updateNowPlayingFromJson(json_text: []const u8) void {
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.smp_allocator, json_text, .{}) catch return;
    defer parsed.deinit();
    if (parsed.value != .object) return;
    const obj = parsed.value.object;
    const title = if (obj.get("title")) |v| if (v == .string) v.string else "" else "";
    const artist = if (obj.get("artist")) |v| if (v == .string) v.string else "" else "";
    const album = if (obj.get("album")) |v| if (v == .string) v.string else "" else "";
    const label_changed = updateNowPlayingLabel(title, artist, album);
    const playback_changed = if (obj.get("playing")) |v| if (v == .bool) updatePlaybackState(v.bool) else false else false;
    const like_changed = if (obj.get("liked")) |v| if (v == .bool) updateLikeState(v.bool) else false else false;
    const repeat_changed = if (obj.get("repeatMode")) |v| if (v == .string) updateRepeatMode(v.string) else false else false;
    commitMenuUpdateIfNeeded(label_changed or playback_changed or like_changed or repeat_changed);
}

fn updateNowPlayingFromJscValue(value: *javascriptcore.Value) void {
    const raw = value.toString();
    defer glib.free(raw);
    updateNowPlayingFromJson(std.mem.span(raw));
}

fn onNowPlayingMessage(_: *webkit.UserContentManager, value: *javascriptcore.Value, _: ?*anyopaque) callconv(.c) void {
    updateNowPlayingFromJscValue(value);
}

fn onNowPlayingJavascript(source: ?*gobject.Object, result: *gio.AsyncResult, _: ?*anyopaque) callconv(.c) void {
    const view: *webkit.WebView = @ptrCast(@alignCast(source.?));
    var err: ?*glib.Error = null;
    const value = view.evaluateJavascriptFinish(result, &err) orelse {
        if (err) |e| e.free();
        return;
    };
    defer value.unref();
    if (err) |e| {
        e.free();
        return;
    }
    updateNowPlayingFromJscValue(value);
}

fn onActivate(app: *gio.Application, _: ?*anyopaque) callconv(.c) void {
    if (main_window) |existing_window| {
        const window = existing_window.as(gtk.Window);
        window.as(gtk.Widget).show();
        window.present();
        return;
    }

    const gtk_app: *gtk.Application = @ptrCast(@alignCast(app));
    const window = gtk.ApplicationWindow.new(gtk_app);
    main_window = window;

    loadWindowState();
    window.as(gtk.Window).setTitle("Netease Cloud Music");
    window.as(gtk.Window).setDefaultSize(window_width, window_height);

    const view = createWebView();
    current_web_view = view;

    // Enable the default context menu's "Inspect Element" entry / Web Inspector.
    const settings = view.getSettings();
    settings.setEnableDeveloperExtras(1);
    // Netease's web player rejects the default WebKitGTK user agent.
    // Pretend to be desktop Chrome; this only affects website sniffing.
    settings.setUserAgent(chrome_linux_ua);

    const manager = view.getUserContentManager();
    _ = manager.registerScriptMessageHandler("neteaseNowPlaying", null);
    _ = webkit.UserContentManager.signals.script_message_received.connect(
        manager,
        ?*anyopaque,
        onNowPlayingMessage,
        null,
        .{ .detail = "neteaseNowPlaying" },
    );

    const polyfill_script = webkit.UserScript.new(
        browser_polyfills,
        .all_frames,
        .start,
        null,
        null,
    );
    manager.addScript(polyfill_script);
    polyfill_script.unref();

    // Some pages interfere with the default context menu. Always keep an
    // inspector entry in WebKit's proposed menu and let WebKit show it.
    _ = webkit.WebView.signals.context_menu.connect(view, ?*anyopaque, onContextMenu, null, .{});

    window.as(gtk.Window).setChild(view.as(gtk.Widget));

    _ = gtk.Window.signals.close_request.connect(window.as(gtk.Window), ?*anyopaque, onCloseRequest, null, .{});
    _ = gtk.Widget.signals.unrealize.connect(window.as(gtk.Widget), ?*anyopaque, onWindowUnrealize, null, .{});

    view.loadUri(default_url);
    if (!start_silent) window.as(gtk.Widget).show();

    _ = glib.timeoutAddSeconds(2, pollNowPlaying, null);
    if (start_autoplay) {
        autoplay_attempts = 8;
        _ = glib.timeoutAddSeconds(3, autoplayTick, null);
    }
}

fn createWebView() *webkit.WebView {
    if (data_dir) |data| {
        const session = webkit.NetworkSession.new(data, cache_dir orelse data);
        session.setPersistentCredentialStorageEnabled(1);

        if (cookies_file) |cookie_path| {
            const cookie_manager = session.getCookieManager();
            cookie_manager.setPersistentStorage(cookie_path, .sqlite);
            cookie_manager.setAcceptPolicy(.always);
        }

        return @ptrCast(@alignCast(gobject.Object.new(
            webkit.WebView.getGObjectType(),
            "network-session",
            session,
            @as(?[*:0]const u8, null),
        )));
    }

    return webkit.WebView.new();
}

fn saveWindowState(window: *gtk.Window) void {
    window.getDefaultSize(&window_width, &window_height);
    if (window_width <= 0 or window_height <= 0) return;
    const path = window_state_file orelse return;
    var buf: [64]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d} {d}\n", .{ window_width, window_height }) catch return;
    std.Io.Dir.writeFile(.cwd(), app_io orelse return, .{ .sub_path = path, .data = text }) catch {};
}

fn loadWindowState() void {
    const path = window_state_file orelse return;
    const text = std.Io.Dir.readFileAlloc(.cwd(), app_io orelse return, path, std.heap.smp_allocator, .limited(1024)) catch return;
    defer std.heap.smp_allocator.free(text);
    var it = std.mem.tokenizeAny(u8, text, " \t\r\n");
    const w_text = it.next() orelse return;
    const h_text = it.next() orelse return;
    const w = std.fmt.parseInt(i32, w_text, 10) catch return;
    const h = std.fmt.parseInt(i32, h_text, 10) catch return;
    if (w >= 640 and h >= 480) {
        window_width = w;
        window_height = h;
    }
}

fn onCloseRequest(window: *gtk.Window, _: ?*anyopaque) callconv(.c) c_int {
    saveWindowState(window);
    window.as(gtk.Widget).hide();
    return 1;
}

fn onWindowUnrealize(widget: *gtk.Widget, _: ?*anyopaque) callconv(.c) void {
    const window: *gtk.Window = @ptrCast(@alignCast(widget));
    saveWindowState(window);
}

fn onContextMenu(
    _: *webkit.WebView,
    menu: *webkit.ContextMenu,
    _: *webkit.HitTestResult,
    _: ?*anyopaque,
) callconv(.c) c_int {
    const inspect = webkit.ContextMenuItem.newFromStockAction(.inspect_element);
    menu.append(inspect);

    // FALSE: do not suppress the menu; show WebKit's menu.
    return 0;
}

const TrayItem = struct {
    pub const INTERFACE_NAME = "org.kde.StatusNotifierItem";

    Category: GStr = GStr.new("ApplicationStatus"),
    Id: GStr = GStr.new("netease-music-webplayer"),
    Title: GStr = GStr.new("Netease Cloud Music"),
    Status: GStr = GStr.new("Active"),
    WindowId: i32 = 0,
    IconName: GStr = GStr.new("netease-cloud-music"),
    IconThemePath: GStr = GStr.new(""),
    IconPixmap: PixmapArray = PixmapArray.new(&empty_pixmaps),
    AttentionIconName: GStr = GStr.new(""),
    AttentionIconPixmap: PixmapArray = PixmapArray.new(&empty_pixmaps),
    AttentionMovieName: GStr = GStr.new(""),
    OverlayIconName: GStr = GStr.new(""),
    OverlayIconPixmap: PixmapArray = PixmapArray.new(&empty_pixmaps),
    ToolTip: ToolTip = .{ .icon_name = GStr.new("netease-cloud-music"), .icon_pixmap = PixmapArray.new(&empty_pixmaps), .title = GStr.new("Netease Cloud Music"), .description = GStr.new("") },
    ItemIsMenu: bool = false,
    Menu: GPath = GPath.new(menu_path),

    pub fn init(_: *goose.Connection, _: void) TrayItem {
        return .{
            .IconPixmap = PixmapArray.new(tray_icon_pixmaps),
            .ToolTip = .{
                .icon_name = GStr.new("netease-cloud-music"),
                .icon_pixmap = PixmapArray.new(tray_icon_pixmaps),
                .title = GStr.new("Netease Cloud Music"),
                .description = GStr.new(""),
            },
        };
    }

    pub fn Activate(_: *TrayItem, _: i32, _: i32) void {
        scheduleTrayAction(.show);
    }

    pub fn SecondaryActivate(_: *TrayItem, _: i32, _: i32) void {
        scheduleTrayAction(.play_pause);
    }

    pub fn ContextMenu(_: *TrayItem, _: i32, _: i32) void {}

    pub fn Scroll(_: *TrayItem, delta: i32, _: GStr) void {
        scheduleTrayAction(if (delta < 0) .previous else .next);
    }
};

const TrayMenu = struct {
    pub const INTERFACE_NAME = "com.canonical.dbusmenu";

    Version: u32 = 3,
    TextDirection: GStr = GStr.new("ltr"),
    Status: GStr = GStr.new("normal"),
    IconThemePath: []const GStr = &.{},

    pub fn init(_: *goose.Connection, _: void) TrayMenu {
        return .{};
    }

    fn labelProps(label: [:0]const u8) []const PropEntry {
        return switch (label[0]) {
            '1' => &menu_props_play_pause,
            '2' => &menu_props_previous,
            '3' => &menu_props_next,
            '4' => &menu_props_like,
            '5' => &menu_props_repeat,
            '6' => &menu_props_repeat_random,
            '7' => &menu_props_repeat_order,
            '8' => &menu_props_repeat_heart,
            '9' => &menu_props_repeat_list,
            else => &menu_props_quit,
        };
    }

    pub fn GetLayout(_: *TrayMenu, _: i32, _: i32, _: []const GStr) !struct { u32, MenuLayout } {
        return .{ menu_revision, menuLayoutById(0) };
    }

    pub fn GetGroupProperties(_: *TrayMenu, _: []const i32, _: []const GStr) goose.core.value.Value.Array(GroupProp) {
        // Some tray hosts ask for item properties separately after GetLayout.
        // Returning the complete static property set is accepted by dbusmenu
        // clients and avoids handing out stack-backed slices.
        return goose.core.value.Value.Array(GroupProp).new(&menu_group_props);
    }

    pub fn AboutToShow(_: *TrayMenu, _: i32) bool {
        scheduleTrayAction(.refresh_now_playing);
        return true;
    }

    pub fn AboutToShowGroup(_: *TrayMenu, _: []const i32) struct { IntArray, IntArray } {
        scheduleTrayAction(.refresh_now_playing);
        return .{ IntArray.new(&menu_root_update_ids), IntArray.new(&empty_menu_ids) };
    }

    fn dispatchEvent(id: i32, event_id: GStr) void {
        if (!std.mem.eql(u8, event_id.s, "clicked")) return;
        switch (id) {
            1 => scheduleTrayAction(.play_pause),
            2 => scheduleTrayAction(.previous),
            3 => scheduleTrayAction(.next),
            4 => scheduleTrayAction(.toggle_like),
            6 => scheduleTrayAction(.repeat_random),
            7 => scheduleTrayAction(.repeat_order),
            8 => scheduleTrayAction(.repeat_heart),
            9 => scheduleTrayAction(.repeat_list),
            10 => scheduleTrayAction(.repeat_single),
            11 => scheduleTrayAction(.show),
            12 => scheduleTrayAction(.quit),
            else => {},
        }
    }

    pub fn Event(_: *TrayMenu, id: i32, event_id: GStr, _: EventVariant, _: u32) void {
        dispatchEvent(id, event_id);
    }

    pub fn EventGroup(_: *TrayMenu) IntArray {
        return IntArray.new(&empty_menu_ids);
    }

    pub fn handleEventRaw(msg: goose.core.Message, _: *TrayMenu) void {
        parseEvent(msg) catch {};
    }

    pub fn handleEventGroupRaw(msg: goose.core.Message, _: *TrayMenu) IntArray {
        parseEventGroup(msg) catch return IntArray.new(&empty_menu_ids);
        return IntArray.new(&empty_menu_ids);
    }

    fn alignPos(pos: *usize, alignment: usize) void {
        const rem = pos.* % alignment;
        if (rem != 0) pos.* += alignment - rem;
    }

    fn readInt(body: []const u8, pos: *usize, comptime T: type, endian: std.builtin.Endian) !T {
        const size = @bitSizeOf(T) / 8;
        if (pos.* + size > body.len) return error.EndOfBody;
        const value = std.mem.readInt(T, body[pos.*..][0..size], endian);
        pos.* += size;
        return value;
    }

    fn readString(body: []const u8, pos: *usize, endian: std.builtin.Endian) ![]const u8 {
        alignPos(pos, 4);
        const len = try readInt(body, pos, u32, endian);
        if (pos.* + len + 1 > body.len) return error.EndOfBody;
        const value = body[pos.* .. pos.* + len];
        pos.* += len + 1;
        return value;
    }

    fn skipVariant(body: []const u8, pos: *usize, endian: std.builtin.Endian) !void {
        const sig_len = try readInt(body, pos, u8, endian);
        if (pos.* + sig_len + 1 > body.len) return error.EndOfBody;
        const sig = body[pos.* .. pos.* + sig_len];
        pos.* += sig_len + 1;

        if (std.mem.eql(u8, sig, "i") or std.mem.eql(u8, sig, "u") or std.mem.eql(u8, sig, "b")) {
            alignPos(pos, 4);
            _ = try readInt(body, pos, u32, endian);
        } else if (std.mem.eql(u8, sig, "s")) {
            _ = try readString(body, pos, endian);
        }
    }

    fn parseEvent(msg: goose.core.Message) !void {
        const body = msg.body;
        var pos: usize = 0;
        const endian = msg.header.endianess;
        alignPos(&pos, 4);
        const id = try readInt(body, &pos, i32, endian);
        const event_id = try readString(body, &pos, endian);
        try skipVariant(body, &pos, endian);
        alignPos(&pos, 4);
        _ = try readInt(body, &pos, u32, endian);
        if (std.mem.eql(u8, event_id, "clicked")) dispatchEvent(id, GStr.new("clicked"));
    }

    fn parseEventGroup(msg: goose.core.Message) !void {
        const body = msg.body;
        var pos: usize = 0;
        const endian = msg.header.endianess;
        const byte_len = try readInt(body, &pos, u32, endian);
        alignPos(&pos, 8);
        const end = @min(body.len, pos + byte_len);
        while (pos < end) {
            alignPos(&pos, 8);
            const id = try readInt(body, &pos, i32, endian);
            const event_id = try readString(body, &pos, endian);
            try skipVariant(body, &pos, endian);
            alignPos(&pos, 4);
            _ = try readInt(body, &pos, u32, endian);
            if (std.mem.eql(u8, event_id, "clicked")) dispatchEvent(id, GStr.new("clicked"));
        }
    }
};

fn readLe(comptime T: type, bytes: []const u8, offset: usize) !T {
    const size = @bitSizeOf(T) / 8;
    if (offset + size > bytes.len) return error.EndOfIcon;
    return std.mem.readInt(T, bytes[offset..][0..size], .little);
}

fn initTrayIcon(allocator: std.mem.Allocator) !void {
    if (tray_icon_pixmaps.len != 0) return;

    const ico = tray_icon_ico;
    if (try readLe(u16, ico, 0) != 0 or try readLe(u16, ico, 2) != 1) return error.InvalidIcon;
    if (try readLe(u16, ico, 4) == 0) return error.InvalidIcon;

    const entry = 6;
    const width_u8 = ico[entry];
    const height_u8 = ico[entry + 1];
    const width: usize = if (width_u8 == 0) 256 else width_u8;
    const entry_height: usize = if (height_u8 == 0) 256 else height_u8;
    const bit_count = try readLe(u16, ico, entry + 6);
    const image_size = try readLe(u32, ico, entry + 8);
    const image_offset = try readLe(u32, ico, entry + 12);
    if (bit_count != 32) return error.UnsupportedIcon;
    if (@as(usize, image_offset) + @as(usize, image_size) > ico.len) return error.EndOfIcon;

    const dib = @as(usize, image_offset);
    const header_size = try readLe(u32, ico, dib);
    if (header_size < 40) return error.UnsupportedIcon;
    const dib_width = try readLe(i32, ico, dib + 4);
    const dib_height = try readLe(i32, ico, dib + 8);
    const dib_bpp = try readLe(u16, ico, dib + 14);
    const compression = try readLe(u32, ico, dib + 16);
    if (dib_width <= 0 or dib_bpp != 32 or compression != 0) return error.UnsupportedIcon;

    const pixel_width: usize = @intCast(dib_width);
    // ICO BMP height includes XOR bitmap + AND mask, so it is usually double.
    const pixel_height: usize = if (dib_height > 0) @as(usize, @intCast(dib_height)) / 2 else entry_height;
    if (pixel_width != width or pixel_height == 0) return error.UnsupportedIcon;

    const src = dib + @as(usize, header_size);
    const src_stride = pixel_width * 4;
    if (src + src_stride * pixel_height > ico.len) return error.EndOfIcon;

    var argb = try allocator.alloc(u8, pixel_width * pixel_height * 4);
    errdefer allocator.free(argb);

    for (0..pixel_height) |y| {
        const src_y = pixel_height - 1 - y;
        for (0..pixel_width) |x| {
            const si = src + src_y * src_stride + x * 4;
            const di = (y * pixel_width + x) * 4;
            const b = ico[si + 0];
            const g = ico[si + 1];
            const r = ico[si + 2];
            const a = ico[si + 3];
            argb[di + 0] = a;
            argb[di + 1] = r;
            argb[di + 2] = g;
            argb[di + 3] = b;
        }
    }

    tray_icon_argb = argb;
    tray_icon_pixmap_storage[0] = .{
        .width = @intCast(pixel_width),
        .height = @intCast(pixel_height),
        .bytes = ByteArray.new(tray_icon_argb),
    };
    tray_icon_pixmaps = &tray_icon_pixmap_storage;
}

fn registerTrayWithWatcher(conn: *goose.Connection) void {
    const watcher = goose.proxy.Proxy.init(conn, "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher");
    // Register by object path rather than by well-known bus name.  This makes
    // watchers store the sender's unique name (e.g. :1.234/StatusNotifierItem),
    // so they can remove the icon reliably when our D-Bus connection disappears.
    // Some watchers (including mika-shell's current implementation) only match
    // removals against the unique old owner from NameOwnerChanged.
    if (watcher.call("RegisterStatusNotifierItem", .{GStr.new(tray_path)})) |result_value| {
        var result = result_value;
        result.deinit();
    } else |err| {
        std.debug.print("[tray] failed to register StatusNotifierItem: {s}\n", .{@errorName(err)});
    }
}

fn onWatcherOwnerChanged(ctx: ?*anyopaque, _: goose.core.Message) void {
    const conn: *goose.Connection = @ptrCast(@alignCast(ctx.?));
    registerTrayWithWatcher(conn);
}

fn trayThread(allocator: std.mem.Allocator, io: std.Io, environ_map: *std.process.Environ.Map) !void {
    var conn = try goose.Connection.init(allocator, .Session, io, environ_map);
    defer conn.close();
    tray_conn = &conn;
    defer {
        if (tray_conn == &conn) tray_conn = null;
    }

    initTrayIcon(allocator) catch |err| {
        std.debug.print("[tray] failed to load embedded favicon: {s}\n", .{@errorName(err)});
    };

    _ = try conn.registerObject(TrayItem, tray_bus_name, tray_path, {});
    _ = try conn.registerObject(TrayMenu, tray_bus_name, menu_path, {});

    try conn.registerSignalHandler("org.freedesktop.DBus", "NameOwnerChanged", onWatcherOwnerChanged, &conn);
    conn.addMatch("type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='org.kde.StatusNotifierWatcher'") catch |err| {
        std.debug.print("[tray] failed to watch StatusNotifierWatcher owner: {s}\n", .{@errorName(err)});
    };

    registerTrayWithWatcher(&conn);

    try conn.waitOnHandle(0);
}

fn setupStorage(io: std.Io, allocator: std.mem.Allocator) !void {
    const home_z = std.c.getenv("HOME") orelse return;
    const home = std.mem.span(home_z);

    data_dir = try std.fmt.allocPrintSentinel(allocator, "{s}/.config/netease-music-webplayer/data", .{home}, 0);
    cache_dir = try std.fmt.allocPrintSentinel(allocator, "{s}/.config/netease-music-webplayer/cache", .{home}, 0);
    cookies_file = try std.fmt.allocPrintSentinel(allocator, "{s}/.config/netease-music-webplayer/cookies.sqlite", .{home}, 0);
    window_state_file = try std.fmt.allocPrintSentinel(allocator, "{s}/.config/netease-music-webplayer/window-state", .{home}, 0);

    try std.Io.Dir.createDirPath(.cwd(), io, data_dir.?);
    try std.Io.Dir.createDirPath(.cwd(), io, cache_dir.?);
}

fn parseArgs(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.arena.allocator());
    defer args.deinit();
    _ = args.skip();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--silent") or
            std.mem.eql(u8, arg, "-s"))
        {
            start_silent = true;
        } else if (std.mem.eql(u8, arg, "-a") or
            std.mem.eql(u8, arg, "--auto-play"))
        {
            start_autoplay = true;
        }
    }
}

pub fn main(init: std.process.Init) !void {
    app_io = init.io;
    try parseArgs(init);
    try setupStorage(init.io, init.arena.allocator());

    const tray_thread = try std.Thread.spawn(.{}, trayThread, .{ std.heap.smp_allocator, init.io, init.environ_map });
    tray_thread.detach();

    const app = gtk.Application.new("io.github.HumXC.netease_music_webplayer", gio.ApplicationFlags.flags_flags_none);
    defer app.as(gobject.Object).unref();

    _ = gio.Application.signals.activate.connect(app.as(gio.Application), ?*anyopaque, onActivate, null, .{});
    _ = app.as(gio.Application).run(0, null);
}

const gio = @import("gio");
const gobject = @import("gobject");
const javascriptcore = @import("javascriptcore");
