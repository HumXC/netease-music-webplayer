const std = @import("std");
const goose = @import("goose");
const player = @import("player.zig");

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

const PropEntry = struct {
    key: GStr,
    value: PropVariant,
};

const PropDict = goose.core.value.Value.Dict(
    GStr,
    PropVariant,
    []const PropEntry,
);

const EventVariant = goose.core.value.Value.Variant(union(enum) {
    str: GStr,
    bool: bool,
    int: i32,
});

const GroupProp = struct {
    id: i32,
    props: PropDict,
};

const PropertyUpdate = struct {
    id: i32,
    props: PropDict,
};

const PropertyUpdateArray = goose.core.value.Value.Array(PropertyUpdate);
const GStrArray = goose.core.value.Value.Array(GStr);

const RemovedProp = struct {
    id: i32,
    props: GStrArray,
};

const RemovedPropArray = goose.core.value.Value.Array(RemovedProp);
const IntArray = goose.core.value.Value.Array(i32);
const ByteArray = goose.core.value.Value.Array(u8);

const Pixmap = struct {
    width: i32,
    height: i32,
    bytes: ByteArray,
};

const PixmapArray = goose.core.value.Value.Array(Pixmap);

const ToolTip = struct {
    icon_name: GStr,
    icon_pixmap: PixmapArray,
    title: GStr,
    description: GStr,
};

const tray_icon_ico = @embedFile("assets/netease-favicon.ico");

const tray_bus_name =
    "org.kde.StatusNotifierItem.netease_music_webplayer";
const tray_path = "/StatusNotifierItem";
const menu_path = "/StatusNotifierItem/Menu";

var controller: ?*player.Controller = null;
var tray_conn: ?*goose.Connection = null;

var current_snapshot: player.Snapshot = .{};

var now_playing_label_buf: [512:0]u8 = [_:0]u8{0} ** 512;
var now_playing_label_len: usize = 1;
var repeat_label_buf: [96:0]u8 = [_:0]u8{0} ** 96;
var repeat_label_len: usize = 0;

var menu_revision: u32 = 1;

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

const menu_props_previous = menuItem("上一曲", "media-skip-backward-symbolic");
const menu_props_next = menuItem("下一曲", "media-skip-forward-symbolic");

var menu_props_like = menuItem("添加喜欢", "love");
var menu_props_mute = menuItem("静音", "audio-volume-muted-symbolic");

var menu_props_repeat = [_]PropEntry{
    .{ .key = GStr.new("type"), .value = PropVariant.new(.{ .type = GStr.new("standard") }) },
    .{ .key = GStr.new("label"), .value = PropVariant.new(.{ .label = GStr.new("播放模式") }) },
    .{ .key = GStr.new("icon-name"), .value = PropVariant.new(.{ .icon_name = GStr.new("media-playlist-repeat-symbolic") }) },
    .{ .key = GStr.new("children-display"), .value = PropVariant.new(.{ .children_display = GStr.new("submenu") }) },
    .{ .key = GStr.new("enabled"), .value = PropVariant.new(.{ .enabled = true }) },
    .{ .key = GStr.new("visible"), .value = PropVariant.new(.{ .visible = true }) },
};

const menu_props_repeat_random = menuItem("随机播放", "media-playlist-shuffle-symbolic");
const menu_props_repeat_order = menuItem("顺序播放", "media-playlist-consecutive-symbolic");
const menu_props_repeat_heart = menuItem("心动模式", "love");
const menu_props_repeat_list = menuItem("列表循环", "media-playlist-repeat-symbolic");
const menu_props_repeat_single = menuItem("单曲循环", "media-playlist-repeat-song-symbolic");

const menu_props_show = menuItem("显示窗口", "view-restore-symbolic");
const menu_props_refresh = menuItem("刷新状态", "view-refresh-symbolic");
const menu_props_quit = menuItem("退出", "window-close-symbolic");

const menu_root_props = [_]PropEntry{
    .{ .key = GStr.new("children-display"), .value = PropVariant.new(.{ .children_display = GStr.new("submenu") }) },
};

fn menuItem(
    comptime label: [:0]const u8,
    comptime icon: [:0]const u8,
) [5]PropEntry {
    return .{
        .{ .key = GStr.new("type"), .value = PropVariant.new(.{ .type = GStr.new("standard") }) },
        .{ .key = GStr.new("label"), .value = PropVariant.new(.{ .label = GStr.new(label) }) },
        .{ .key = GStr.new("icon-name"), .value = PropVariant.new(.{ .icon_name = GStr.new(icon) }) },
        .{ .key = GStr.new("enabled"), .value = PropVariant.new(.{ .enabled = true }) },
        .{ .key = GStr.new("visible"), .value = PropVariant.new(.{ .visible = true }) },
    };
}

const root_child_ids = [_]i32{
    100, 1, 2, 3, 4, 13, 5, 11, 12,
};

const repeat_child_ids = [_]i32{ 6, 7, 8, 9, 10 };
const no_child_ids = [_]i32{};
const empty_menu_ids = [_]i32{};
const menu_root_update_ids = [_]i32{0};
const empty_removed_props = [_]RemovedProp{};

const menu_group_props = [_]GroupProp{
    .{ .id = 0, .props = PropDict.new(&menu_root_props) },
    .{ .id = 100, .props = PropDict.new(&now_playing_label_prop) },
    .{ .id = 1, .props = PropDict.new(&menu_props_play_pause) },
    .{ .id = 2, .props = PropDict.new(&menu_props_previous) },
    .{ .id = 3, .props = PropDict.new(&menu_props_next) },
    .{ .id = 4, .props = PropDict.new(&menu_props_like) },
    .{ .id = 13, .props = PropDict.new(&menu_props_mute) },
    .{ .id = 5, .props = PropDict.new(&menu_props_repeat) },
    .{ .id = 6, .props = PropDict.new(&menu_props_repeat_random) },
    .{ .id = 7, .props = PropDict.new(&menu_props_repeat_order) },
    .{ .id = 8, .props = PropDict.new(&menu_props_repeat_heart) },
    .{ .id = 9, .props = PropDict.new(&menu_props_repeat_list) },
    .{ .id = 10, .props = PropDict.new(&menu_props_repeat_single) },
    .{ .id = 11, .props = PropDict.new(&menu_props_show) },
    .{ .id = 12, .props = PropDict.new(&menu_props_quit) },
};

const MenuLayout = struct {
    pub const SIGNATURE = "(ia{sv}av)";

    id: i32,
    props: []const PropEntry,
    child_ids: []const i32,

    pub fn ser(self: MenuLayout, w: *goose.core.value.DBusWriter) !void {
        try w.padTo(8);
        try goose.core.value.Serializer.trySerialize(i32, self.id, w);
        try goose.core.value.Serializer.trySerialize(
            PropDict,
            PropDict.new(self.props),
            w,
        );

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
        13 => .{ .id = 13, .props = &menu_props_mute, .child_ids = &no_child_ids },
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

pub fn setSnapshot(snapshot: player.Snapshot) void {
    current_snapshot = snapshot;
}

fn refreshSnapshot() void {
    const ctl = controller orelse return;
    const snapshot = ctl.refresh() catch |err| {
        std.debug.print("[tray] refresh failed: {s}\n", .{@errorName(err)});
        return;
    };
    setSnapshot(snapshot);
}

fn syncMenuProperties() void {
    const snapshot = current_snapshot;

    const title = snapshot.titleSlice();
    const artist = snapshot.artistSlice();

    const label = if (title.len == 0)
        std.fmt.bufPrintZ(
            &now_playing_label_buf,
            "没有正在播放的歌曲",
            .{},
        ) catch "没有正在播放的歌曲"
    else if (artist.len != 0)
        std.fmt.bufPrintZ(
            &now_playing_label_buf,
            "{s} - {s}",
            .{ title, artist },
        ) catch "正在播放"
    else
        std.fmt.bufPrintZ(
            &now_playing_label_buf,
            "{s}",
            .{title},
        ) catch "正在播放";

    now_playing_label_len = label.len;
    now_playing_label_prop[1].value =
        PropVariant.new(.{
            .label = GStr.new(now_playing_label_buf[0..now_playing_label_len :0]),
        });

    if (snapshot.playing) {
        menu_props_play_pause[1].value =
            PropVariant.new(.{ .label = GStr.new("暂停") });
        menu_props_play_pause[2].value =
            PropVariant.new(.{ .icon_name = GStr.new("media-playback-pause-symbolic") });
    } else {
        menu_props_play_pause[1].value =
            PropVariant.new(.{ .label = GStr.new("播放") });
        menu_props_play_pause[2].value =
            PropVariant.new(.{ .icon_name = GStr.new("media-playback-start-symbolic") });
    }

    if (snapshot.liked) {
        menu_props_like[1].value =
            PropVariant.new(.{ .label = GStr.new("取消喜欢") });
        menu_props_like[2].value =
            PropVariant.new(.{ .icon_name = GStr.new("heart-filled-symbolic") });
    } else {
        menu_props_like[1].value =
            PropVariant.new(.{ .label = GStr.new("添加喜欢") });
        menu_props_like[2].value =
            PropVariant.new(.{ .icon_name = GStr.new("love") });
    }

    if (snapshot.muted) {
        menu_props_mute[1].value =
            PropVariant.new(.{ .label = GStr.new("取消静音") });
        menu_props_mute[2].value =
            PropVariant.new(.{ .icon_name = GStr.new("audio-volume-high-symbolic") });
    } else {
        menu_props_mute[1].value =
            PropVariant.new(.{ .label = GStr.new("静音") });
        menu_props_mute[2].value =
            PropVariant.new(.{ .icon_name = GStr.new("audio-volume-muted-symbolic") });
    }

    const repeat_mode = snapshot.repeatModeSlice();
    if (repeat_mode.len != 0) {
        const repeat_label = std.fmt.bufPrintZ(
            &repeat_label_buf,
            "{s}",
            .{repeat_mode},
        ) catch "播放模式";

        repeat_label_len = repeat_label.len;
        menu_props_repeat[1].value =
            PropVariant.new(.{
                .label = GStr.new(repeat_label_buf[0..repeat_label_len :0]),
            });

        if (std.mem.indexOf(u8, repeat_mode, "单") != null or
            std.mem.indexOf(u8, repeat_mode, "one") != null)
        {
            menu_props_repeat[2].value =
                PropVariant.new(.{
                    .icon_name = GStr.new("media-playlist-repeat-song-symbolic"),
                });
        } else if (std.mem.indexOf(u8, repeat_mode, "随机") != null or
            std.mem.indexOf(u8, repeat_mode, "shuffle") != null)
        {
            menu_props_repeat[2].value =
                PropVariant.new(.{
                    .icon_name = GStr.new("media-playlist-shuffle-symbolic"),
                });
        } else {
            menu_props_repeat[2].value =
                PropVariant.new(.{
                    .icon_name = GStr.new("media-playlist-repeat-symbolic"),
                });
        }
    }
}

const TrayAction = enum {
    show,
    play_pause,
    previous,
    next,
    toggle_like,
    toggle_mute,
    repeat_random,
    repeat_order,
    repeat_heart,
    repeat_list,
    repeat_single,
    refresh,
    quit,
};

fn performAction(action: TrayAction) void {
    const ctl = controller orelse return;

    switch (action) {
        .show => ctl.show(),
        .play_pause => ctl.playPause(),
        .previous => ctl.previous(),
        .next => ctl.next(),
        .toggle_like => ctl.toggleLike(),
        .toggle_mute => ctl.toggleMute(),
        .repeat_random => ctl.setRepeatMode(.random),
        .repeat_order => ctl.setRepeatMode(.order),
        .repeat_heart => ctl.setRepeatMode(.heart),
        .repeat_list => ctl.setRepeatMode(.list),
        .repeat_single => ctl.setRepeatMode(.single),
        .refresh => {},
        .quit => {
            ctl.closeBrowser();
            std.process.exit(0);
        },
    }

    if (action != .show and action != .quit) {
        refreshSnapshot();
        syncMenuProperties();
        emitMenuUpdated();
    }
}

const empty_pixmaps = [_]Pixmap{};
var tray_icon_argb: []u8 = &.{};
var tray_icon_pixmap_storage: [1]Pixmap = undefined;
var tray_icon_pixmaps: []const Pixmap = &empty_pixmaps;

fn readLe(
    comptime T: type,
    bytes: []const u8,
    offset: usize,
) !T {
    const size = @bitSizeOf(T) / 8;
    if (offset + size > bytes.len) return error.EndOfIcon;
    return std.mem.readInt(T, bytes[offset..][0..size], .little);
}

fn initTrayIcon(allocator: std.mem.Allocator) !void {
    if (tray_icon_pixmaps.len != 0) return;

    const ico = tray_icon_ico;
    if (try readLe(u16, ico, 0) != 0 or try readLe(u16, ico, 2) != 1)
        return error.InvalidIcon;
    if (try readLe(u16, ico, 4) == 0)
        return error.InvalidIcon;

    const entry = 6;
    const width_u8 = ico[entry];
    const height_u8 = ico[entry + 1];
    const width: usize = if (width_u8 == 0) 256 else width_u8;
    const entry_height: usize = if (height_u8 == 0) 256 else height_u8;

    const bit_count = try readLe(u16, ico, entry + 6);
    const image_size = try readLe(u32, ico, entry + 8);
    const image_offset = try readLe(u32, ico, entry + 12);

    if (bit_count != 32) return error.UnsupportedIcon;
    if (@as(usize, image_offset) + @as(usize, image_size) > ico.len)
        return error.EndOfIcon;

    const dib: usize = @intCast(image_offset);
    const header_size = try readLe(u32, ico, dib);
    const dib_width = try readLe(i32, ico, dib + 4);
    const dib_height = try readLe(i32, ico, dib + 8);
    const dib_bpp = try readLe(u16, ico, dib + 14);
    const compression = try readLe(u32, ico, dib + 16);

    if (header_size < 40 or
        dib_width <= 0 or
        dib_bpp != 32 or
        compression != 0)
        return error.UnsupportedIcon;

    const pixel_width: usize = @intCast(dib_width);
    const pixel_height: usize =
        if (dib_height > 0)
            @as(usize, @intCast(dib_height)) / 2
        else
            entry_height;

    if (pixel_width != width or pixel_height == 0)
        return error.UnsupportedIcon;

    const src = dib + @as(usize, header_size);
    const stride = pixel_width * 4;
    if (src + stride * pixel_height > ico.len)
        return error.EndOfIcon;

    const argb = try allocator.alloc(
        u8,
        pixel_width * pixel_height * 4,
    );
    errdefer allocator.free(argb);

    for (0..pixel_height) |y| {
        const src_y = pixel_height - 1 - y;
        for (0..pixel_width) |x| {
            const si = src + src_y * stride + x * 4;
            const di = (y * pixel_width + x) * 4;
            argb[di + 0] = ico[si + 3];
            argb[di + 1] = ico[si + 2];
            argb[di + 2] = ico[si + 1];
            argb[di + 3] = ico[si + 0];
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

    ToolTip: ToolTip = .{
        .icon_name = GStr.new("netease-cloud-music"),
        .icon_pixmap = PixmapArray.new(&empty_pixmaps),
        .title = GStr.new("Netease Cloud Music"),
        .description = GStr.new(""),
    },

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
        performAction(.show);
    }

    pub fn SecondaryActivate(_: *TrayItem, _: i32, _: i32) void {
        performAction(.play_pause);
    }

    pub fn ContextMenu(_: *TrayItem, _: i32, _: i32) void {}

    pub fn Scroll(_: *TrayItem, delta: i32, _: GStr) void {
        performAction(if (delta < 0) .previous else .next);
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

    pub fn GetLayout(
        _: *TrayMenu,
        _: i32,
        _: i32,
        _: []const GStr,
    ) !struct { u32, MenuLayout } {
        syncMenuProperties();
        return .{ menu_revision, menuLayoutById(0) };
    }

    pub fn GetGroupProperties(
        _: *TrayMenu,
        _: []const i32,
        _: []const GStr,
    ) goose.core.value.Value.Array(GroupProp) {
        syncMenuProperties();
        return goose.core.value.Value.Array(GroupProp).new(&menu_group_props);
    }

    pub fn AboutToShow(_: *TrayMenu, _: i32) bool {
        refreshSnapshot();
        syncMenuProperties();
        emitMenuUpdated();
        return true;
    }

    pub fn AboutToShowGroup(
        _: *TrayMenu,
        _: []const i32,
    ) struct { IntArray, IntArray } {
        refreshSnapshot();
        syncMenuProperties();
        emitMenuUpdated();
        return .{
            IntArray.new(&menu_root_update_ids),
            IntArray.new(&empty_menu_ids),
        };
    }

    pub fn Event(
        _: *TrayMenu,
        id: i32,
        event_id: GStr,
        _: EventVariant,
        _: u32,
    ) void {
        dispatchEvent(id, event_id);
    }

    pub fn EventGroup(_: *TrayMenu) IntArray {
        return IntArray.new(&empty_menu_ids);
    }

    pub fn handleEventRaw(msg: goose.core.Message, _: *TrayMenu) void {
        parseEvent(msg) catch {};
    }

    pub fn handleEventGroupRaw(
        msg: goose.core.Message,
        _: *TrayMenu,
    ) IntArray {
        parseEventGroup(msg) catch
            return IntArray.new(&empty_menu_ids);

        return IntArray.new(&empty_menu_ids);
    }

    fn dispatchEvent(id: i32, event_id: GStr) void {
        if (!std.mem.eql(u8, event_id.s, "clicked")) return;

        switch (id) {
            1 => performAction(.play_pause),
            2 => performAction(.previous),
            3 => performAction(.next),
            4 => performAction(.toggle_like),
            13 => performAction(.toggle_mute),
            6 => performAction(.repeat_random),
            7 => performAction(.repeat_order),
            8 => performAction(.repeat_heart),
            9 => performAction(.repeat_list),
            10 => performAction(.repeat_single),
            11 => performAction(.show),
            12 => performAction(.quit),
            else => {},
        }
    }

    fn alignPos(pos: *usize, alignment: usize) void {
        const rem = pos.* % alignment;
        if (rem != 0) pos.* += alignment - rem;
    }

    fn readInt(
        body: []const u8,
        pos: *usize,
        comptime T: type,
        endian: std.builtin.Endian,
    ) !T {
        const size = @bitSizeOf(T) / 8;
        if (pos.* + size > body.len) return error.EndOfBody;
        const value = std.mem.readInt(
            T,
            body[pos.*..][0..size],
            endian,
        );
        pos.* += size;
        return value;
    }

    fn readString(
        body: []const u8,
        pos: *usize,
        endian: std.builtin.Endian,
    ) ![]const u8 {
        alignPos(pos, 4);
        const len = try readInt(body, pos, u32, endian);
        if (pos.* + len + 1 > body.len) return error.EndOfBody;
        const value = body[pos.* .. pos.* + len];
        pos.* += len + 1;
        return value;
    }

    fn skipVariant(
        body: []const u8,
        pos: *usize,
        endian: std.builtin.Endian,
    ) !void {
        const sig_len = try readInt(body, pos, u8, endian);
        if (pos.* + sig_len + 1 > body.len) return error.EndOfBody;

        const sig = body[pos.* .. pos.* + sig_len];
        pos.* += sig_len + 1;

        if (std.mem.eql(u8, sig, "i") or
            std.mem.eql(u8, sig, "u") or
            std.mem.eql(u8, sig, "b"))
        {
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

        if (std.mem.eql(u8, event_id, "clicked"))
            dispatchEvent(id, GStr.new("clicked"));
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

            if (std.mem.eql(u8, event_id, "clicked"))
                dispatchEvent(id, GStr.new("clicked"));
        }
    }
};

fn emitMenuSignal(
    conn: *goose.Connection,
    member: [:0]const u8,
    payload: anytype,
) void {
    var encoder = goose.message.BodyEncoder.encode(
        conn.__allocator,
        payload,
    ) catch |err| {
        std.debug.print(
            "[tray] failed to encode {s}: {s}\n",
            .{ member, @errorName(err) },
        );
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
        std.debug.print(
            "[tray] failed to emit {s}: {s}\n",
            .{ member, @errorName(err) },
        );
    };
}

fn emitMenuUpdated() void {
    const conn = tray_conn orelse return;

    menu_revision +%= 1;
    if (menu_revision == 0) menu_revision = 1;

    const changed_props = [_]PropertyUpdate{
        .{ .id = 100, .props = PropDict.new(&now_playing_label_prop) },
        .{ .id = 1, .props = PropDict.new(&menu_props_play_pause) },
        .{ .id = 4, .props = PropDict.new(&menu_props_like) },
        .{ .id = 13, .props = PropDict.new(&menu_props_mute) },
        .{ .id = 5, .props = PropDict.new(&menu_props_repeat) },
    };

    emitMenuSignal(
        conn,
        "ItemsPropertiesUpdated",
        .{
            PropertyUpdateArray.new(&changed_props),
            RemovedPropArray.new(&empty_removed_props),
        },
    );

    emitMenuSignal(
        conn,
        "LayoutUpdated",
        .{ menu_revision, @as(i32, 0) },
    );
}

fn registerTrayWithWatcher(conn: *goose.Connection) void {
    const watcher = goose.proxy.Proxy.init(
        conn,
        "org.kde.StatusNotifierWatcher",
        "/StatusNotifierWatcher",
        "org.kde.StatusNotifierWatcher",
    );

    if (watcher.call(
        "RegisterStatusNotifierItem",
        .{GStr.new(tray_path)},
    )) |result_value| {
        var result = result_value;
        result.deinit();
    } else |err| {
        std.debug.print(
            "[tray] failed to register StatusNotifierItem: {s}\n",
            .{@errorName(err)},
        );
    }
}

fn onWatcherOwnerChanged(
    ctx: ?*anyopaque,
    _: goose.core.Message,
) void {
    const conn: *goose.Connection =
        @ptrCast(@alignCast(ctx.?));
    registerTrayWithWatcher(conn);
}

pub fn run(
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *std.process.Environ.Map,
    ctl: *player.Controller,
) !void {
    controller = ctl;
    defer controller = null;

    refreshSnapshot();
    syncMenuProperties();

    initTrayIcon(allocator) catch |err| {
        std.debug.print(
            "[tray] failed to load embedded favicon: {s}\n",
            .{@errorName(err)},
        );
    };

    var conn = try goose.Connection.init(
        allocator,
        .Session,
        io,
        environ_map,
    );
    defer conn.close();

    tray_conn = &conn;
    defer tray_conn = null;

    _ = try conn.registerObject(
        TrayItem,
        tray_bus_name,
        tray_path,
        {},
    );

    _ = try conn.registerObject(
        TrayMenu,
        tray_bus_name,
        menu_path,
        {},
    );

    try conn.registerSignalHandler(
        "org.freedesktop.DBus",
        "NameOwnerChanged",
        onWatcherOwnerChanged,
        &conn,
    );

    conn.addMatch(
        "type='signal',sender='org.freedesktop.DBus'," ++
            "interface='org.freedesktop.DBus'," ++
            "member='NameOwnerChanged'," ++
            "arg0='org.kde.StatusNotifierWatcher'",
    ) catch |err| {
        std.debug.print(
            "[tray] failed to watch StatusNotifierWatcher: {s}\n",
            .{@errorName(err)},
        );
    };

    registerTrayWithWatcher(&conn);

    std.debug.print("[tray] ready\n", .{});
    try conn.waitOnHandle(0);
}
