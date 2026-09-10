const std = @import("std");

const browser = @import("browser.zig");
const cdp = @import("cdp.zig");
const player = @import("player.zig");
const tray = @import("tray.zig");

pub fn main(init: std.process.Init) !void {
    const options = try browser.parseArgs(init);

    try cdp.globalInit();
    defer cdp.globalDeinit();

    std.debug.print(
        "\n========================================\n" ++
            " Netease Music WebPlayer (CDP)\n" ++
            "========================================\n\n",
        .{},
    );

    const executable = browser.resolve(
        init.io,
        options.browser,
    ) catch |err| {
        switch (err) {
            error.UnsupportedBrowser => {
                std.debug.print(
                    "\nThis application requires a Chromium/CDP compatible browser.\n" ++
                        "Supported examples: Chromium, Chrome, Brave, Vivaldi, Edge, Thorium.\n",
                    .{},
                );
            },
            error.NoSupportedBrowser => {
                std.debug.print(
                    "\nNo supported Chromium/CDP browser was found.\n" ++
                        "Use --browser <executable> to select one explicitly.\n",
                    .{},
                );
            },
            else => {},
        }
        return err;
    };

    const launch = try browser.launch(init, executable);

    const port = browser.waitForDevToolsPort(
        init.io,
        launch.devtools_file,
    ) catch |err| {
        if (err == error.DevToolsStartupTimeout) {
            std.debug.print(
                "\n[browser] browser launched, but Chromium DevTools Protocol did not start.\n" ++
                    "[browser] selected executable: {s}\n" ++
                    "[browser] this usually means the selected executable is not Chromium/CDP compatible.\n",
                .{executable},
            );
        }
        return err;
    };

    std.debug.print("[cdp] DevTools port: {d}\n", .{port});

    const ws_url = try cdp.findNeteaseTarget(init.io, port);
    defer std.heap.smp_allocator.free(ws_url);

    var client = try cdp.Client.connect(init.io, ws_url);
    defer client.deinit();

    var controller = player.Controller.init(&client);
    try controller.initialize();

    if (options.auto_play) {
        try init.io.sleep(.fromMilliseconds(1000), .awake);
        controller.play();
    }

    try tray.run(
        std.heap.smp_allocator,
        init.io,
        init.environ_map,
        &controller,
    );
}
