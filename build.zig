const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const goose = b.dependency("goose", .{ .target = target, .optimize = optimize });

    // Goose currently needs a couple of small Zig 0.16 compatibility fixes for
    // object dispatch and sentinel-slice decoding used by D-Bus strings.
    const patch_goose = b.addSystemCommand(&.{
        "sh",
        "-c",
        \\
        \\set -eu
        \\pkg="$0"
        \\python3 - <<'PY' "$pkg"
        \\from pathlib import Path
        \\import sys
        \\pkg = Path(sys.argv[1])
        \\repls = {
        \\  "src/dispatcher.zig": [
        \\    ("""const is_prop = if (type_info == .@\"struct\" and @hasDecl(FType, \"__is_goose_property\")) true else pblk: {\n                        const is_signal = (type_info == .@\"struct\" and @hasDecl(FType, \"__is_goose_signal\"));\n                        const is_conn = std.mem.eql(u8, f.name, \"conn\");\n                        const is_ptr = (type_info == .pointer and type_info.pointer.size != .slice);\n                        break :pblk !is_signal and !is_conn and !is_ptr;\n                    };\n\n                    if (is_prop) {""", """const is_prop = comptime if (type_info == .@\"struct\" and @hasDecl(FType, \"__is_goose_property\")) true else pblk: {\n                        const is_signal = (type_info == .@\"struct\" and @hasDecl(FType, \"__is_goose_signal\"));\n                        const is_conn = std.mem.eql(u8, f.name, \"conn\");\n                        const is_ptr = (type_info == .pointer and type_info.pointer.size != .slice);\n                        break :pblk !is_signal and !is_conn and !is_ptr;\n                    };\n\n                    if (comptime is_prop) {"""),
        \\    ("""const result = try @call(.auto, field_val, args);\n                                var encoder = try message.BodyEncoder.encode(conn.__allocator, result);""", """const result = switch (@typeInfo(fn_info.return_type.?)) {\n                                    .error_union => try @call(.auto, field_val, args),\n                                    else => @call(.auto, field_val, args),\n                                };\n                                var encoder = try message.BodyEncoder.encode(conn.__allocator, result);"""),
        \\    ("""            // Dispatch to method\n            inline for (@typeInfo(T).@\"struct\".decls) |decl| {""", """            if (comptime @hasDecl(T, \"handleEventRaw\")) {\n                if (std.mem.eql(u8, member, \"Event\")) {\n                    const result = T.handleEventRaw(msg, self_obj);\n                    var encoder = try message.BodyEncoder.encode(conn.__allocator, result);\n                    defer encoder.deinit();\n                    try conn.sendReply(msg, encoder);\n                    return;\n                }\n            }\n\n            if (comptime @hasDecl(T, \"handleEventGroupRaw\")) {\n                if (std.mem.eql(u8, member, \"EventGroup\")) {\n                    const result = T.handleEventGroupRaw(msg, self_obj);\n                    var encoder = try message.BodyEncoder.encode(conn.__allocator, result);\n                    defer encoder.deinit();\n                    try conn.sendReply(msg, encoder);\n                    return;\n                }\n            }\n\n            // Dispatch to method\n            inline for (@typeInfo(T).@\"struct\".decls) |decl| {"""),
        \\    ("if (!std.mem.eql(u8, decl.name, \"init\")) {", "if (!std.mem.eql(u8, decl.name, \"init\") and !std.mem.eql(u8, decl.name, \"handleEventRaw\") and !std.mem.eql(u8, decl.name, \"handleEventGroupRaw\")) {"),
        \\  ],
        \\  "src/xml_generator.zig": [
        \\    ("if (!std.mem.eql(u8, decl.name, \"init\")) {", "if (!std.mem.eql(u8, decl.name, \"init\") and !std.mem.eql(u8, decl.name, \"handleEventRaw\") and !std.mem.eql(u8, decl.name, \"handleEventGroupRaw\")) {"),
        \\  ],
        \\  "src/message_utils.zig": [
        \\    ("return try list.toOwnedSlice(self.allocator);", """if (info.sentinel()) |_| {\n                    const slice = try list.toOwnedSlice(self.allocator);\n                    const sentinel_slice = try self.allocator.allocSentinel(Elem, slice.len, 0);\n                    @memcpy(sentinel_slice, slice);\n                    self.allocator.free(slice);\n                    return sentinel_slice;\n                }\n                return try list.toOwnedSlice(self.allocator);"""),
        \\  ],
        \\}
        \\for rel, items in repls.items():
        \\    path = pkg / rel
        \\    text = path.read_text()
        \\    if rel == "src/message_utils.zig" and "allocSentinel(Elem" in text:
        \\        path.write_text(text)
        \\        continue
        \\    for old, new in items:
        \\        if rel == "src/dispatcher.zig" and "handleEventRaw" in text and "handleEventRaw" in new:
        \\            continue
        \\        text = text.replace(old, new)
        \\    path.write_text(text)
        \\PY
    });
    patch_goose.addDirectoryArg(goose.path("."));

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    exe_mod.addImport("goose", goose.module("goose"));
    exe_mod.linkSystemLibrary("libcurl", .{});
    const exe = b.addExecutable(.{
        .name = "netease-music-webplayer",
        .root_module = exe_mod,
    });

    exe.step.dependOn(&patch_goose.step);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
