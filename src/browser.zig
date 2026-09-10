const std = @import("std");

pub const default_url = "https://music.163.com/st/webplayer";

pub const Options = struct {
    browser: ?[]const u8 = null,
    auto_play: bool = false,
};

pub const Launch = struct {
    profile_dir: []const u8,
    devtools_file: []const u8,
};

const chromium_candidates = [_][]const u8{
    "chromium",
    "chromium-browser",
};

const chrome_candidates = [_][]const u8{
    "google-chrome-stable",
    "google-chrome",
    "chrome",
};

const brave_candidates = [_][]const u8{
    "brave",
    "brave-browser",
};

const vivaldi_candidates = [_][]const u8{
    "vivaldi-stable",
    "vivaldi",
};

const edge_candidates = [_][]const u8{
    "microsoft-edge-stable",
    "microsoft-edge",
    "microsoft-edge-beta",
    "microsoft-edge-dev",
};

const other_candidates = [_][]const u8{
    "thorium-browser",
    "thorium",
    "ungoogled-chromium",
};

const blocked_names = [_][]const u8{
    "firefox",
    "firefox-esr",
    "firefox-beta",
    "firefox-devedition",
    "firefox-developer-edition",
    "zen",
    "zen-beta",
    "zen-browser",
    "librewolf",
    "floorp",
    "waterfox",
    "mullvad-browser",
    "tor-browser",
};

pub fn printUsage() void {
    std.debug.print(
        \\Usage:
        \\  netease-music-webplayer [options]
        \\
        \\Options:
        \\  -b, --browser <browser>   Select Chromium/CDP compatible browser
        \\      --browser=<browser>
        \\  -a, --auto-play           Try to start playback after launch
        \\  -h, --help                Show this help
        \\
        \\Aliases:
        \\  auto
        \\  chromium
        \\  chrome
        \\  brave
        \\  vivaldi
        \\  edge
        \\
        \\Custom Chromium-based executable names/paths are also accepted.
        \\Firefox-family browsers (Firefox, Zen, LibreWolf, Floorp, etc.)
        \\are explicitly unsupported because this application requires CDP.
        \\
    , .{});
}

pub fn parseArgs(init: std.process.Init) !Options {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var options: Options = .{};
    var i: usize = 1;

    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printUsage();
            std.process.exit(0);
        }

        if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--auto-play")) {
            options.auto_play = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "-b") or std.mem.eql(u8, arg, "--browser")) {
            if (i + 1 >= args.len) return error.MissingBrowserArgument;
            i += 1;
            options.browser = args[i];
            continue;
        }

        const prefix = "--browser=";
        if (std.mem.startsWith(u8, arg, prefix)) {
            const value = arg[prefix.len..];
            if (value.len == 0) return error.MissingBrowserArgument;
            options.browser = value;
            continue;
        }

        std.debug.print("[cli] unknown argument: {s}\n", .{arg});
        return error.UnknownArgument;
    }

    return options;
}

fn basename(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |idx| {
        return path[idx + 1 ..];
    }
    return path;
}

fn isBlockedName(value: []const u8) bool {
    const name = basename(value);
    for (blocked_names) |blocked| {
        if (std.mem.eql(u8, name, blocked)) return true;
    }
    return false;
}

fn executableWorks(io: std.Io, executable: []const u8) bool {
    var child = std.process.spawn(io, .{
        .argv = &.{ executable, "--version" },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return false;

    const term = child.wait(io) catch return false;
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

fn firstWorking(io: std.Io, candidates: []const []const u8) ?[]const u8 {
    for (candidates) |candidate| {
        if (executableWorks(io, candidate)) return candidate;
    }
    return null;
}

fn findAutomatic(io: std.Io) ?[]const u8 {
    if (firstWorking(io, &chromium_candidates)) |v| return v;
    if (firstWorking(io, &chrome_candidates)) |v| return v;
    if (firstWorking(io, &brave_candidates)) |v| return v;
    if (firstWorking(io, &vivaldi_candidates)) |v| return v;
    if (firstWorking(io, &edge_candidates)) |v| return v;
    if (firstWorking(io, &other_candidates)) |v| return v;
    return null;
}

pub fn resolve(io: std.Io, requested: ?[]const u8) ![]const u8 {
    const value = requested orelse
        return findAutomatic(io) orelse error.NoSupportedBrowser;

    if (isBlockedName(value)) {
        std.debug.print(
            "[browser] '{s}' is explicitly unsupported: Firefox-family browsers do not provide Chromium CDP\n",
            .{value},
        );
        return error.UnsupportedBrowser;
    }

    if (std.mem.eql(u8, value, "auto"))
        return findAutomatic(io) orelse error.NoSupportedBrowser;

    if (std.mem.eql(u8, value, "chromium"))
        return firstWorking(io, &chromium_candidates) orelse error.BrowserNotFound;

    if (std.mem.eql(u8, value, "chrome"))
        return firstWorking(io, &chrome_candidates) orelse error.BrowserNotFound;

    if (std.mem.eql(u8, value, "brave"))
        return firstWorking(io, &brave_candidates) orelse error.BrowserNotFound;

    if (std.mem.eql(u8, value, "vivaldi"))
        return firstWorking(io, &vivaldi_candidates) orelse error.BrowserNotFound;

    if (std.mem.eql(u8, value, "edge"))
        return firstWorking(io, &edge_candidates) orelse error.BrowserNotFound;

    if (!executableWorks(io, value)) {
        std.debug.print("[browser] executable not found or unusable: {s}\n", .{value});
        return error.BrowserNotFound;
    }

    return value;
}

pub fn launch(init: std.process.Init, executable: []const u8) !Launch {
    const io = init.io;
    const arena = init.arena.allocator();

    const home = init.environ_map.get("HOME") orelse return error.HomeNotSet;
    const profile_dir = try std.fmt.allocPrint(
        arena,
        "{s}/.config/netease-music-webplayer/browser-profile",
        .{home},
    );

    try std.Io.Dir.createDirPath(.cwd(), io, profile_dir);

    const devtools_file = try std.fmt.allocPrint(
        arena,
        "{s}/DevToolsActivePort",
        .{profile_dir},
    );

    std.Io.Dir.deleteFile(.cwd(), io, devtools_file) catch {};

    const user_data_arg = try std.fmt.allocPrint(
        arena,
        "--user-data-dir={s}",
        .{profile_dir},
    );

    const app_arg = try std.fmt.allocPrint(
        arena,
        "--app={s}",
        .{default_url},
    );

    const argv = [_][]const u8{
        executable,
        "--remote-debugging-address=127.0.0.1",
        "--remote-debugging-port=0",
        user_data_arg,
        app_arg,
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-background-mode",
    };

    std.debug.print("[browser] selected: {s}\n", .{executable});
    std.debug.print("[browser] profile: {s}\n", .{profile_dir});

    _ = try std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .inherit,
    });

    return .{
        .profile_dir = profile_dir,
        .devtools_file = devtools_file,
    };
}

pub fn waitForDevToolsPort(io: std.Io, path: []const u8) !u16 {
    var attempt: usize = 0;
    while (attempt < 300) : (attempt += 1) {
        const content = std.Io.Dir.readFileAlloc(
            .cwd(),
            io,
            path,
            std.heap.smp_allocator,
            .limited(4096),
        ) catch {
            try io.sleep(.fromMilliseconds(50), .awake);
            continue;
        };
        defer std.heap.smp_allocator.free(content);

        var lines = std.mem.splitScalar(u8, content, '\n');
        const port_text = lines.next() orelse {
            try io.sleep(.fromMilliseconds(50), .awake);
            continue;
        };

        const port = std.fmt.parseInt(
            u16,
            std.mem.trim(u8, port_text, " \t\r\n"),
            10,
        ) catch {
            try io.sleep(.fromMilliseconds(50), .awake);
            continue;
        };

        if (port != 0) return port;
    }

    return error.DevToolsStartupTimeout;
}
