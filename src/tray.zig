const std = @import("std");
const goose = @import("goose");
const player = @import("player.zig");

const GStr = goose.core.value.GStr;
const GPath = goose.core.value.GPath;
const GVariant = goose.core.value.GVariant;

const PropVariant = goose.core.value.Value.Variant(union(enum) {
    label: GStr,
    type: GStr,
    icon_name: GStr,
    children_display: GStr,
    enabled: bool,
    visible: bool,
});

const PropDict = std.StringHashMap(PropVariant);

const MenuEvent = struct {
    id: i32,
    event_id: GStr,
    data: GVariant,
    timestamp: u32,
};

const GroupProp = struct {
    id: i32,
    props: PropDict,
};

const PropertyUpdate = struct {
    id: i32,
    props: PropDict,
};

const PropertyUpdateArray =
    goose.core.value.Value.Array(PropertyUpdate);

const GStrArray =
    goose.core.value.Value.Array(GStr);

const RemovedProp = struct {
    id: i32,
    props: GStrArray,
};

const RemovedPropArray =
    goose.core.value.Value.Array(RemovedProp);

const IntArray =
    goose.core.value.Value.Array(i32);

const ByteArray =
    goose.core.value.Value.Array(u8);

const Pixmap = struct {
    width: i32,
    height: i32,
    bytes: ByteArray,
};

const PixmapArray =
    goose.core.value.Value.Array(Pixmap);

const ToolTip = struct {
    icon_name: GStr,
    icon_pixmap: PixmapArray,
    title: GStr,
    description: GStr,
};

const tray_icon_ico =
    @embedFile("assets/netease-favicon.ico");

const tray_bus_name =
    "org.kde.StatusNotifierItem.netease_music_webplayer";

const tray_path =
    "/StatusNotifierItem";

const menu_path =
    "/StatusNotifierItem/Menu";

var controller: ?*player.Controller = null;
var tray_conn: ?*goose.Connection = null;

var current_snapshot: player.Snapshot = .{};

var now_playing_label_buf: [512:0]u8 =
    [_:0]u8{0} ** 512;

var repeat_label_buf: [96:0]u8 =
    [_:0]u8{0} ** 96;

var menu_revision: u32 = 1;

const root_child_ids = [_]i32{
    100,
    1,
    2,
    3,
    4,
    13,
    5,
    11,
    12,
};

const repeat_child_ids =
    [_]i32{ 6, 7, 8, 9, 10 };

const no_child_ids =
    [_]i32{};

const empty_menu_ids =
    [_]i32{};

const menu_root_update_ids =
    [_]i32{0};

const empty_removed_props =
    [_]RemovedProp{};

const MenuProps = struct {
    root: PropDict,
    now_playing: PropDict,

    play_pause: PropDict,
    previous: PropDict,
    next: PropDict,
    like: PropDict,
    mute: PropDict,

    repeat: PropDict,
    repeat_random: PropDict,
    repeat_order: PropDict,
    repeat_heart: PropDict,
    repeat_list: PropDict,
    repeat_single: PropDict,

    show: PropDict,
    quit: PropDict,

    fn init(
        allocator: std.mem.Allocator,
    ) !MenuProps {
        var root =
            try makeRootProps(allocator);
        errdefer root.deinit();

        var now_playing =
            try makeNowPlayingProps(allocator);
        errdefer now_playing.deinit();

        var play_pause =
            try makeMenuItem(
                allocator,
                "播放",
                "media-playback-start-symbolic",
            );
        errdefer play_pause.deinit();

        var previous =
            try makeMenuItem(
                allocator,
                "上一曲",
                "media-skip-backward-symbolic",
            );
        errdefer previous.deinit();

        var next =
            try makeMenuItem(
                allocator,
                "下一曲",
                "media-skip-forward-symbolic",
            );
        errdefer next.deinit();

        var like =
            try makeMenuItem(
                allocator,
                "添加喜欢",
                "love",
            );
        errdefer like.deinit();

        var mute =
            try makeMenuItem(
                allocator,
                "静音",
                "audio-volume-muted-symbolic",
            );
        errdefer mute.deinit();

        var repeat =
            try makeRepeatProps(allocator);
        errdefer repeat.deinit();

        var repeat_random =
            try makeMenuItem(
                allocator,
                "随机播放",
                "media-playlist-shuffle-symbolic",
            );
        errdefer repeat_random.deinit();

        var repeat_order =
            try makeMenuItem(
                allocator,
                "顺序播放",
                "media-playlist-consecutive-symbolic",
            );
        errdefer repeat_order.deinit();

        var repeat_heart =
            try makeMenuItem(
                allocator,
                "心动模式",
                "love",
            );
        errdefer repeat_heart.deinit();

        var repeat_list =
            try makeMenuItem(
                allocator,
                "列表循环",
                "media-playlist-repeat-symbolic",
            );
        errdefer repeat_list.deinit();

        var repeat_single =
            try makeMenuItem(
                allocator,
                "单曲循环",
                "media-playlist-repeat-song-symbolic",
            );
        errdefer repeat_single.deinit();

        var show =
            try makeMenuItem(
                allocator,
                "显示窗口",
                "view-restore-symbolic",
            );
        errdefer show.deinit();

        var quit =
            try makeMenuItem(
                allocator,
                "退出",
                "window-close-symbolic",
            );
        errdefer quit.deinit();

        return .{
            .root = root,
            .now_playing = now_playing,

            .play_pause = play_pause,
            .previous = previous,
            .next = next,
            .like = like,
            .mute = mute,

            .repeat = repeat,
            .repeat_random = repeat_random,
            .repeat_order = repeat_order,
            .repeat_heart = repeat_heart,
            .repeat_list = repeat_list,
            .repeat_single = repeat_single,

            .show = show,
            .quit = quit,
        };
    }

    fn deinit(
        self: *MenuProps,
    ) void {
        self.root.deinit();
        self.now_playing.deinit();

        self.play_pause.deinit();
        self.previous.deinit();
        self.next.deinit();
        self.like.deinit();
        self.mute.deinit();

        self.repeat.deinit();
        self.repeat_random.deinit();
        self.repeat_order.deinit();
        self.repeat_heart.deinit();
        self.repeat_list.deinit();
        self.repeat_single.deinit();

        self.show.deinit();
        self.quit.deinit();
    }
};

var menu_props: ?*MenuProps = null;

var menu_group_props: [15]GroupProp = undefined;

fn putProp(
    dict: *PropDict,
    key: []const u8,
    value: PropVariant,
) !void {
    try dict.put(key, value);
}

fn setProp(
    dict: *PropDict,
    key: []const u8,
    value: PropVariant,
) void {
    const ptr =
        dict.getPtr(key) orelse {
            std.debug.print(
                "[tray] missing menu property: {s}\n",
                .{key},
            );
            return;
        };

    ptr.* = value;
}

fn makeMenuItem(
    allocator: std.mem.Allocator,
    label: [:0]const u8,
    icon: [:0]const u8,
) !PropDict {
    var props =
        PropDict.init(allocator);

    errdefer props.deinit();

    try putProp(
        &props,
        "type",
        PropVariant.new(.{
            .type = GStr.new("standard"),
        }),
    );

    try putProp(
        &props,
        "label",
        PropVariant.new(.{
            .label = GStr.new(label),
        }),
    );

    try putProp(
        &props,
        "icon-name",
        PropVariant.new(.{
            .icon_name = GStr.new(icon),
        }),
    );

    try putProp(
        &props,
        "enabled",
        PropVariant.new(.{
            .enabled = true,
        }),
    );

    try putProp(
        &props,
        "visible",
        PropVariant.new(.{
            .visible = true,
        }),
    );

    return props;
}

fn makeRootProps(
    allocator: std.mem.Allocator,
) !PropDict {
    var props =
        PropDict.init(allocator);

    errdefer props.deinit();

    try putProp(
        &props,
        "children-display",
        PropVariant.new(.{
            .children_display = GStr.new("submenu"),
        }),
    );

    return props;
}

fn makeNowPlayingProps(
    allocator: std.mem.Allocator,
) !PropDict {
    var props =
        PropDict.init(allocator);

    errdefer props.deinit();

    try putProp(
        &props,
        "type",
        PropVariant.new(.{
            .type = GStr.new("standard"),
        }),
    );

    try putProp(
        &props,
        "label",
        PropVariant.new(.{
            .label = GStr.new("-"),
        }),
    );

    try putProp(
        &props,
        "enabled",
        PropVariant.new(.{
            .enabled = false,
        }),
    );

    try putProp(
        &props,
        "visible",
        PropVariant.new(.{
            .visible = true,
        }),
    );

    return props;
}

fn makeRepeatProps(
    allocator: std.mem.Allocator,
) !PropDict {
    var props =
        PropDict.init(allocator);

    errdefer props.deinit();

    try putProp(
        &props,
        "type",
        PropVariant.new(.{
            .type = GStr.new("standard"),
        }),
    );

    try putProp(
        &props,
        "label",
        PropVariant.new(.{
            .label = GStr.new("播放模式"),
        }),
    );

    try putProp(
        &props,
        "icon-name",
        PropVariant.new(.{
            .icon_name = GStr.new(
                "media-playlist-repeat-symbolic",
            ),
        }),
    );

    try putProp(
        &props,
        "children-display",
        PropVariant.new(.{
            .children_display = GStr.new("submenu"),
        }),
    );

    try putProp(
        &props,
        "enabled",
        PropVariant.new(.{
            .enabled = true,
        }),
    );

    try putProp(
        &props,
        "visible",
        PropVariant.new(.{
            .visible = true,
        }),
    );

    return props;
}

fn refreshMenuGroupProps() void {
    const props =
        menu_props orelse return;

    menu_group_props = .{
        .{
            .id = 0,
            .props = props.root,
        },
        .{
            .id = 100,
            .props = props.now_playing,
        },
        .{
            .id = 1,
            .props = props.play_pause,
        },
        .{
            .id = 2,
            .props = props.previous,
        },
        .{
            .id = 3,
            .props = props.next,
        },
        .{
            .id = 4,
            .props = props.like,
        },
        .{
            .id = 13,
            .props = props.mute,
        },
        .{
            .id = 5,
            .props = props.repeat,
        },
        .{
            .id = 6,
            .props = props.repeat_random,
        },
        .{
            .id = 7,
            .props = props.repeat_order,
        },
        .{
            .id = 8,
            .props = props.repeat_heart,
        },
        .{
            .id = 9,
            .props = props.repeat_list,
        },
        .{
            .id = 10,
            .props = props.repeat_single,
        },
        .{
            .id = 11,
            .props = props.show,
        },
        .{
            .id = 12,
            .props = props.quit,
        },
    };
}

const MenuLayout = struct {
    pub const SIGNATURE =
        "(ia{sv}av)";

    id: i32,
    props: PropDict,
    child_ids: []const i32,

    pub fn ser(
        self: MenuLayout,
        w: *goose.core.value.DBusWriter,
    ) !void {
        try w.padTo(8);

        try goose.core.value.Serializer
            .trySerialize(
            i32,
            self.id,
            w,
        );

        try goose.core.value.Serializer
            .trySerialize(
            PropDict,
            self.props,
            w,
        );

        try w.padTo(4);

        const len_pos =
            w.buffer.items.len;

        try w.writeInt(u32, 0);

        const start =
            w.buffer.items.len;

        for (self.child_ids) |child_id| {
            const child =
                menuLayoutById(child_id);

            try w.writeSignatureOf(
                MenuLayout,
            );

            try child.ser(w);
        }

        w.writeU32At(
            len_pos,
            @intCast(
                w.buffer.items.len -
                    start,
            ),
        );
    }
};

fn menuLayoutById(
    id: i32,
) MenuLayout {
    const props =
        menu_props orelse unreachable;

    return switch (id) {
        0 => .{
            .id = 0,
            .props = props.root,
            .child_ids = &root_child_ids,
        },

        100 => .{
            .id = 100,
            .props = props.now_playing,
            .child_ids = &no_child_ids,
        },

        1 => .{
            .id = 1,
            .props = props.play_pause,
            .child_ids = &no_child_ids,
        },

        2 => .{
            .id = 2,
            .props = props.previous,
            .child_ids = &no_child_ids,
        },

        3 => .{
            .id = 3,
            .props = props.next,
            .child_ids = &no_child_ids,
        },

        4 => .{
            .id = 4,
            .props = props.like,
            .child_ids = &no_child_ids,
        },

        13 => .{
            .id = 13,
            .props = props.mute,
            .child_ids = &no_child_ids,
        },

        5 => .{
            .id = 5,
            .props = props.repeat,
            .child_ids = &repeat_child_ids,
        },

        6 => .{
            .id = 6,
            .props = props.repeat_random,
            .child_ids = &no_child_ids,
        },

        7 => .{
            .id = 7,
            .props = props.repeat_order,
            .child_ids = &no_child_ids,
        },

        8 => .{
            .id = 8,
            .props = props.repeat_heart,
            .child_ids = &no_child_ids,
        },

        9 => .{
            .id = 9,
            .props = props.repeat_list,
            .child_ids = &no_child_ids,
        },

        10 => .{
            .id = 10,
            .props = props.repeat_single,
            .child_ids = &no_child_ids,
        },

        11 => .{
            .id = 11,
            .props = props.show,
            .child_ids = &no_child_ids,
        },

        else => .{
            .id = 12,
            .props = props.quit,
            .child_ids = &no_child_ids,
        },
    };
}

pub fn setSnapshot(
    snapshot: player.Snapshot,
) void {
    current_snapshot = snapshot;
}

fn refreshSnapshot() void {
    const ctl =
        controller orelse return;

    const snapshot =
        ctl.refresh() catch |err| {
            std.debug.print(
                "[tray] refresh failed: {s}\n",
                .{@errorName(err)},
            );
            return;
        };

    setSnapshot(snapshot);
}

fn syncMenuProperties() void {
    const props =
        menu_props orelse return;

    const snapshot =
        current_snapshot;

    const title =
        snapshot.titleSlice();

    const artist =
        snapshot.artistSlice();

    const label =
        if (title.len == 0)
            std.fmt.bufPrintZ(
                &now_playing_label_buf,
                "没有正在播放的歌曲",
                .{},
            ) catch
                "没有正在播放的歌曲"
        else if (artist.len != 0)
            std.fmt.bufPrintZ(
                &now_playing_label_buf,
                "{s} - {s}",
                .{
                    title,
                    artist,
                },
            ) catch
                "正在播放"
        else
            std.fmt.bufPrintZ(
                &now_playing_label_buf,
                "{s}",
                .{title},
            ) catch
                "正在播放";

    setProp(
        &props.now_playing,
        "label",
        PropVariant.new(.{
            .label = GStr.new(label),
        }),
    );

    if (snapshot.playing) {
        setProp(
            &props.play_pause,
            "label",
            PropVariant.new(.{
                .label = GStr.new("暂停"),
            }),
        );

        setProp(
            &props.play_pause,
            "icon-name",
            PropVariant.new(.{
                .icon_name = GStr.new(
                    "media-playback-pause-symbolic",
                ),
            }),
        );
    } else {
        setProp(
            &props.play_pause,
            "label",
            PropVariant.new(.{
                .label = GStr.new("播放"),
            }),
        );

        setProp(
            &props.play_pause,
            "icon-name",
            PropVariant.new(.{
                .icon_name = GStr.new(
                    "media-playback-start-symbolic",
                ),
            }),
        );
    }

    if (snapshot.liked) {
        setProp(
            &props.like,
            "label",
            PropVariant.new(.{
                .label = GStr.new("取消喜欢"),
            }),
        );

        setProp(
            &props.like,
            "icon-name",
            PropVariant.new(.{
                .icon_name = GStr.new(
                    "heart-filled-symbolic",
                ),
            }),
        );
    } else {
        setProp(
            &props.like,
            "label",
            PropVariant.new(.{
                .label = GStr.new("添加喜欢"),
            }),
        );

        setProp(
            &props.like,
            "icon-name",
            PropVariant.new(.{
                .icon_name = GStr.new("love"),
            }),
        );
    }

    if (snapshot.muted) {
        setProp(
            &props.mute,
            "label",
            PropVariant.new(.{
                .label = GStr.new("取消静音"),
            }),
        );

        setProp(
            &props.mute,
            "icon-name",
            PropVariant.new(.{
                .icon_name = GStr.new(
                    "audio-volume-high-symbolic",
                ),
            }),
        );
    } else {
        setProp(
            &props.mute,
            "label",
            PropVariant.new(.{
                .label = GStr.new("静音"),
            }),
        );

        setProp(
            &props.mute,
            "icon-name",
            PropVariant.new(.{
                .icon_name = GStr.new(
                    "audio-volume-muted-symbolic",
                ),
            }),
        );
    }

    const repeat_mode =
        snapshot.repeatModeSlice();

    if (repeat_mode.len != 0) {
        const repeat_label =
            std.fmt.bufPrintZ(
                &repeat_label_buf,
                "{s}",
                .{repeat_mode},
            ) catch
                "播放模式";

        setProp(
            &props.repeat,
            "label",
            PropVariant.new(.{
                .label = GStr.new(repeat_label),
            }),
        );

        if (std.mem.indexOf(
            u8,
            repeat_mode,
            "单",
        ) != null or
            std.mem.indexOf(
                u8,
                repeat_mode,
                "one",
            ) != null)
        {
            setProp(
                &props.repeat,
                "icon-name",
                PropVariant.new(.{
                    .icon_name = GStr.new(
                        "media-playlist-repeat-song-symbolic",
                    ),
                }),
            );
        } else if (std.mem.indexOf(
            u8,
            repeat_mode,
            "随机",
        ) != null or
            std.mem.indexOf(
                u8,
                repeat_mode,
                "shuffle",
            ) != null)
        {
            setProp(
                &props.repeat,
                "icon-name",
                PropVariant.new(.{
                    .icon_name = GStr.new(
                        "media-playlist-shuffle-symbolic",
                    ),
                }),
            );
        } else {
            setProp(
                &props.repeat,
                "icon-name",
                PropVariant.new(.{
                    .icon_name = GStr.new(
                        "media-playlist-repeat-symbolic",
                    ),
                }),
            );
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

fn performAction(
    action: TrayAction,
) void {
    const ctl =
        controller orelse return;

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

    if (action != .show and
        action != .quit)
    {
        refreshSnapshot();
        syncMenuProperties();
        emitMenuUpdated();
    }
}

const empty_pixmaps =
    [_]Pixmap{};

var tray_icon_argb: []u8 =
    &.{};

var tray_icon_pixmap_storage: [1]Pixmap = undefined;

var tray_icon_pixmaps: []const Pixmap =
    &empty_pixmaps;

fn readLe(
    comptime T: type,
    bytes: []const u8,
    offset: usize,
) !T {
    const size =
        @bitSizeOf(T) / 8;

    if (offset + size > bytes.len)
        return error.EndOfIcon;

    return std.mem.readInt(
        T,
        bytes[offset..][0..size],
        .little,
    );
}

fn initTrayIcon(
    allocator: std.mem.Allocator,
) !void {
    if (tray_icon_pixmaps.len != 0)
        return;

    const ico =
        tray_icon_ico;

    if (try readLe(
        u16,
        ico,
        0,
    ) != 0 or
        try readLe(
            u16,
            ico,
            2,
        ) != 1)
    {
        return error.InvalidIcon;
    }

    if (try readLe(
        u16,
        ico,
        4,
    ) == 0) {
        return error.InvalidIcon;
    }

    const entry = 6;

    const width_u8 =
        ico[entry];

    const height_u8 =
        ico[entry + 1];

    const width: usize =
        if (width_u8 == 0)
            256
        else
            width_u8;

    const entry_height: usize =
        if (height_u8 == 0)
            256
        else
            height_u8;

    const bit_count =
        try readLe(
            u16,
            ico,
            entry + 6,
        );

    const image_size =
        try readLe(
            u32,
            ico,
            entry + 8,
        );

    const image_offset =
        try readLe(
            u32,
            ico,
            entry + 12,
        );

    if (bit_count != 32)
        return error.UnsupportedIcon;

    if (@as(
        usize,
        image_offset,
    ) +
        @as(
            usize,
            image_size,
        ) >
        ico.len)
    {
        return error.EndOfIcon;
    }

    const dib: usize =
        @intCast(image_offset);

    const header_size =
        try readLe(
            u32,
            ico,
            dib,
        );

    const dib_width =
        try readLe(
            i32,
            ico,
            dib + 4,
        );

    const dib_height =
        try readLe(
            i32,
            ico,
            dib + 8,
        );

    const dib_bpp =
        try readLe(
            u16,
            ico,
            dib + 14,
        );

    const compression =
        try readLe(
            u32,
            ico,
            dib + 16,
        );

    if (header_size < 40 or
        dib_width <= 0 or
        dib_bpp != 32 or
        compression != 0)
    {
        return error.UnsupportedIcon;
    }

    const pixel_width: usize =
        @intCast(dib_width);

    const pixel_height: usize =
        if (dib_height > 0)
            @as(
                usize,
                @intCast(dib_height),
            ) / 2
        else
            entry_height;

    if (pixel_width != width or
        pixel_height == 0)
    {
        return error.UnsupportedIcon;
    }

    const src =
        dib + @as(
            usize,
            header_size,
        );

    const stride =
        pixel_width * 4;

    if (src +
        stride *
            pixel_height >
        ico.len)
    {
        return error.EndOfIcon;
    }

    const argb =
        try allocator.alloc(
            u8,
            pixel_width *
                pixel_height *
                4,
        );

    errdefer allocator.free(argb);

    for (0..pixel_height) |y| {
        const src_y =
            pixel_height -
            1 -
            y;

        for (0..pixel_width) |x| {
            const si =
                src +
                src_y * stride +
                x * 4;

            const di =
                (y *
                    pixel_width +
                    x) *
                4;

            argb[di + 0] =
                ico[si + 3];

            argb[di + 1] =
                ico[si + 2];

            argb[di + 2] =
                ico[si + 1];

            argb[di + 3] =
                ico[si + 0];
        }
    }

    tray_icon_argb =
        argb;

    tray_icon_pixmap_storage[0] = .{
        .width = @intCast(pixel_width),

        .height = @intCast(pixel_height),

        .bytes = ByteArray.new(
            tray_icon_argb,
        ),
    };

    tray_icon_pixmaps =
        &tray_icon_pixmap_storage;
}

const TrayItem = struct {
    pub const INTERFACE_NAME =
        "org.kde.StatusNotifierItem";

    Category: GStr =
        GStr.new(
            "ApplicationStatus",
        ),

    Id: GStr =
        GStr.new(
            "netease-music-webplayer",
        ),

    Title: GStr =
        GStr.new(
            "Netease Cloud Music",
        ),

    Status: GStr =
        GStr.new("Active"),

    WindowId: i32 = 0,

    IconName: GStr =
        GStr.new(
            "netease-cloud-music",
        ),

    IconThemePath: GStr =
        GStr.new(""),

    IconPixmap: PixmapArray =
        PixmapArray.new(
            &empty_pixmaps,
        ),

    AttentionIconName: GStr =
        GStr.new(""),

    AttentionIconPixmap: PixmapArray =
        PixmapArray.new(
            &empty_pixmaps,
        ),

    AttentionMovieName: GStr =
        GStr.new(""),

    OverlayIconName: GStr =
        GStr.new(""),

    OverlayIconPixmap: PixmapArray =
        PixmapArray.new(
            &empty_pixmaps,
        ),

    ToolTip: ToolTip = .{
        .icon_name = GStr.new(
            "netease-cloud-music",
        ),

        .icon_pixmap = PixmapArray.new(
            &empty_pixmaps,
        ),

        .title = GStr.new(
            "Netease Cloud Music",
        ),

        .description = GStr.new(""),
    },

    ItemIsMenu: bool = false,

    Menu: GPath =
        GPath.new(menu_path),

    pub fn init(
        _: *goose.Connection,
        _: void,
    ) TrayItem {
        return .{
            .IconPixmap = PixmapArray.new(
                tray_icon_pixmaps,
            ),

            .ToolTip = .{
                .icon_name = GStr.new(
                    "netease-cloud-music",
                ),

                .icon_pixmap = PixmapArray.new(
                    tray_icon_pixmaps,
                ),

                .title = GStr.new(
                    "Netease Cloud Music",
                ),

                .description = GStr.new(""),
            },
        };
    }

    pub fn Activate(
        _: *TrayItem,
        _: i32,
        _: i32,
    ) !void {
        performAction(.show);
    }

    pub fn SecondaryActivate(
        _: *TrayItem,
        _: i32,
        _: i32,
    ) !void {
        performAction(
            .play_pause,
        );
    }

    pub fn ContextMenu(
        _: *TrayItem,
        _: i32,
        _: i32,
    ) !void {}

    pub fn Scroll(
        _: *TrayItem,
        delta: i32,
        _: GStr,
    ) !void {
        performAction(
            if (delta < 0)
                .previous
            else
                .next,
        );
    }
};

const TrayMenu = struct {
    pub const INTERFACE_NAME =
        "com.canonical.dbusmenu";

    Version: u32 = 3,

    TextDirection: GStr =
        GStr.new("ltr"),

    Status: GStr =
        GStr.new("normal"),

    IconThemePath: []const GStr =
        &.{},

    pub fn init(
        _: *goose.Connection,
        _: void,
    ) TrayMenu {
        return .{};
    }

    pub fn GetLayout(
        _: *TrayMenu,
        _: i32,
        _: i32,
        _: []const GStr,
    ) !struct {
        u32,
        MenuLayout,
    } {
        syncMenuProperties();

        return .{
            menu_revision,
            menuLayoutById(0),
        };
    }

    pub fn GetGroupProperties(
        _: *TrayMenu,
        _: []const i32,
        _: []const GStr,
    ) !goose.core.value.Value.Array(
        GroupProp,
    ) {
        syncMenuProperties();

        return goose.core.value.Value
            .Array(GroupProp)
            .new(
            &menu_group_props,
        );
    }

    pub fn AboutToShow(
        _: *TrayMenu,
        _: i32,
    ) !bool {
        refreshSnapshot();
        syncMenuProperties();
        emitMenuUpdated();

        return true;
    }

    pub fn AboutToShowGroup(
        _: *TrayMenu,
        _: []const i32,
    ) !struct {
        IntArray,
        IntArray,
    } {
        refreshSnapshot();
        syncMenuProperties();
        emitMenuUpdated();

        return .{
            IntArray.new(
                &menu_root_update_ids,
            ),

            IntArray.new(
                &empty_menu_ids,
            ),
        };
    }

    pub fn Event(
        _: *TrayMenu,
        id: i32,
        event_id: GStr,
        _: GVariant,
        _: u32,
    ) !void {
        dispatchEvent(
            id,
            event_id,
        );
    }

    pub fn EventGroup(
        _: *TrayMenu,
        events: []const MenuEvent,
    ) !IntArray {
        for (events) |event| {
            dispatchEvent(
                event.id,
                event.event_id,
            );
        }

        return IntArray.new(
            &empty_menu_ids,
        );
    }

    fn dispatchEvent(
        id: i32,
        event_id: GStr,
    ) void {
        if (!std.mem.eql(
            u8,
            event_id.s,
            "clicked",
        )) {
            return;
        }

        switch (id) {
            1 => performAction(
                .play_pause,
            ),

            2 => performAction(
                .previous,
            ),

            3 => performAction(
                .next,
            ),

            4 => performAction(
                .toggle_like,
            ),

            13 => performAction(
                .toggle_mute,
            ),

            6 => performAction(
                .repeat_random,
            ),

            7 => performAction(
                .repeat_order,
            ),

            8 => performAction(
                .repeat_heart,
            ),

            9 => performAction(
                .repeat_list,
            ),

            10 => performAction(
                .repeat_single,
            ),

            11 => performAction(
                .show,
            ),

            12 => performAction(
                .quit,
            ),

            else => {},
        }
    }
};

fn emitMenuSignal(
    conn: *goose.Connection,
    member: [:0]const u8,
    payload: anytype,
) void {
    var encoder =
        goose.message.BodyEncoder
            .encode(
            conn.__allocator,
            payload,
        ) catch |err| {
            std.debug.print(
                "[tray] failed to encode {s}: {s}\n",
                .{
                    member,
                    @errorName(err),
                },
            );

            return;
        };

    defer encoder.deinit();

    const serial =
        conn.serial_counter;

    conn.serial_counter += 1;

    const header =
        goose.core.MessageHeader{
            .message_type = .Signal,

            .flags = 0,

            .proto_version = 1,

            .body_length = @intCast(
                encoder
                    .body()
                    .len,
            ),

            .serial = serial,

            .header_fields = @constCast(
                &[_]goose.core.HeaderField{
                    .{
                        .code = .Path,

                        .value = .{
                            .Path = menu_path,
                        },
                    },

                    .{
                        .code = .Interface,

                        .value = .{
                            .Interface = "com.canonical.dbusmenu",
                        },
                    },

                    .{
                        .code = .Member,

                        .value = .{
                            .Member = member,
                        },
                    },

                    .{
                        .code = .Signature,

                        .value = .{
                            .Signature = encoder
                                .signature(),
                        },
                    },
                },
            ),
        };

    const msg =
        goose.core.Message.new(
            header,
            encoder.body(),
        );

    conn.sendMessage(
        msg,
    ) catch |err| {
        std.debug.print(
            "[tray] failed to emit {s}: {s}\n",
            .{
                member,
                @errorName(err),
            },
        );
    };
}

fn emitMenuUpdated() void {
    const conn =
        tray_conn orelse return;

    const props =
        menu_props orelse return;

    menu_revision +%= 1;

    if (menu_revision == 0)
        menu_revision = 1;

    const changed_props =
        [_]PropertyUpdate{
            .{
                .id = 100,
                .props = props.now_playing,
            },

            .{
                .id = 1,
                .props = props.play_pause,
            },

            .{
                .id = 4,
                .props = props.like,
            },

            .{
                .id = 13,
                .props = props.mute,
            },

            .{
                .id = 5,
                .props = props.repeat,
            },
        };

    emitMenuSignal(
        conn,
        "ItemsPropertiesUpdated",
        .{
            PropertyUpdateArray.new(
                &changed_props,
            ),

            RemovedPropArray.new(
                &empty_removed_props,
            ),
        },
    );

    emitMenuSignal(
        conn,
        "LayoutUpdated",
        .{
            menu_revision,
            @as(i32, 0),
        },
    );
}

fn registerTrayWithWatcher(
    conn: *goose.Connection,
) void {
    const watcher =
        goose.proxy.Proxy.init(
            conn,
            "org.kde.StatusNotifierWatcher",
            "/StatusNotifierWatcher",
            "org.kde.StatusNotifierWatcher",
        );

    if (watcher.call(
        "RegisterStatusNotifierItem",
        .{
            GStr.new(
                tray_path,
            ),
        },
    )) |result_value| {
        var result =
            result_value;

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
        @ptrCast(
            @alignCast(
                ctx.?,
            ),
        );

    registerTrayWithWatcher(
        conn,
    );
}

pub fn run(
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *std.process.Environ.Map,
    ctl: *player.Controller,
) !void {
    controller = ctl;
    defer controller = null;

    var props =
        try MenuProps.init(
            allocator,
        );

    defer props.deinit();

    menu_props = &props;
    defer menu_props = null;

    refreshMenuGroupProps();

    refreshSnapshot();
    syncMenuProperties();

    initTrayIcon(
        allocator,
    ) catch |err| {
        std.debug.print(
            "[tray] failed to load embedded favicon: {s}\n",
            .{@errorName(err)},
        );
    };

    var conn =
        try goose.Connection.init(
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

    registerTrayWithWatcher(
        &conn,
    );

    std.debug.print(
        "[tray] ready\n",
        .{},
    );

    try conn.waitOnHandle(0);
}
