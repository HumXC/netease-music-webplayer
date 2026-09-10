const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const goose_dep = b.dependency("goose", .{
        .target = target,
        .optimize = optimize,
    });

    const websocket_dep = b.dependency("websocket", .{
        .target = target,
        .optimize = optimize,
    });

    const project_root = b.build_root.path orelse ".";
    const goose_abs = goose_dep.path(".").getPath(b);

    const rel_goose = std.fs.path.relative(
        b.allocator,
        project_root,
        null,
        project_root,
        goose_abs,
    ) catch unreachable;

    const patch_goose_cmd = b.addSystemCommand(&.{ "git", "apply", "--directory" });
    patch_goose_cmd.addArg(rel_goose);
    patch_goose_cmd.addArg(b.pathFromRoot("patches/goose-zig016.patch"));
    const patch_goose_step = b.step("patch-goose", "Apply Zig 0.16 compatibility patch to Goose");
    patch_goose_step.dependOn(&patch_goose_cmd.step);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "goose", .module = goose_dep.module("goose") },
            .{ .name = "websocket", .module = websocket_dep.module("websocket") },
        },
    });

    const exe = b.addExecutable(.{
        .name = "netease-music-webplayer",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
