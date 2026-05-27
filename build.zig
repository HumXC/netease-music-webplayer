const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gobject = b.dependency("gobject", .{ .target = target, .optimize = optimize });
    const goose = b.dependency("goose", .{ .target = target, .optimize = optimize });

    // zig-gobject v0.3.1 bindings still contain a few Zig <=0.15 @Type calls.
    // Patch the fetched package in-place so it builds with nixpkgs zig_0_16.
    const patch_gobject = b.addSystemCommand(&.{
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
        \\  "src/cairo1/cairo1.zig": [
        \\    ("_: @Type(.{ .int = .{ .signedness = .unsigned, .bits = @bitSizeOf(c_int) - 1 } }) = 0,", "_: @Int(.unsigned, @bitSizeOf(c_int) - 1) = 0,"),
        \\  ],
        \\  "src/gobject2/ext.zig": [
        \\    ("""_padding1: @Type(.{ .int = .{\n            .signedness = .unsigned,\n            .bits = @bitSizeOf(c_uint) - 5,\n        } }) = 0,""", "_padding1: @Int(.unsigned, @bitSizeOf(c_uint) - 5) = 0,"),
        \\    ("""return *const @Type(.{ .@\"fn\" = .{\n        .calling_convention = .c,\n        .is_generic = false,\n        .is_var_args = false,\n        .return_type = ReturnType,\n        .params = params: {\n            var params: [param_types.len + 2]std.builtin.Type.Fn.Param = undefined;\n            params[0] = .{ .is_generic = false, .is_noalias = false, .type = *Itype };\n            for (param_types, params[1 .. params.len - 1]) |ParamType, *type_param| {\n                type_param.* = .{ .is_generic = false, .is_noalias = false, .type = ParamType };\n            }\n            params[params.len - 1] = .{ .is_generic = false, .is_noalias = false, .type = DataType };\n            break :params &params;\n        },\n    } });""", """const FnType = @Fn(\n        params: {\n            var params: [param_types.len + 2]type = undefined;\n            params[0] = *Itype;\n            for (param_types, params[1 .. params.len - 1]) |ParamType, *type_param| {\n                type_param.* = ParamType;\n            }\n            params[params.len - 1] = DataType;\n            break :params &params;\n        },\n        null,\n        ReturnType,\n        .{ .calling_convention = .c },\n    );\n    return *const FnType;"""),
        \\    ("""const EmitParams = @Type(.{ .@\"struct\" = .{\n        .layout = .auto,\n        .fields = fields: {\n            var fields: [param_types.len]std.builtin.Type.StructField = undefined;\n            for (param_types, &fields, 0..) |ParamType, *field, i| {\n                field.* = .{\n                    .name = std.fmt.comptimePrint(\"{}\", .{i}),\n                    .type = ParamType,\n                    .default_value_ptr = null,\n                    .is_comptime = false,\n                    .alignment = @alignOf(ParamType),\n                };\n            }\n            break :fields &fields;\n        },\n        .decls = &.{},\n        .is_tuple = true,\n    } });""", "const EmitParams = @Tuple(param_types);"),
        \\    ("""_padding1: @Type(.{ .int = .{\n            .signedness = .unsigned,\n            .bits = @bitSizeOf(c_uint) - 3,\n        } }) = 0,""", "_padding1: @Int(.unsigned, @bitSizeOf(c_uint) - 3) = 0,"),
        \\  ],
        \\}
        \\for rel, items in repls.items():
        \\    path = pkg / rel
        \\    text = path.read_text()
        \\    for old, new in items:
        \\        text = text.replace(old, new)
        \\    path.write_text(text)
        \\PY
    });
    patch_gobject.addDirectoryArg(gobject.path("."));

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

    exe_mod.addImport("gtk", gobject.module("gtk4"));
    exe_mod.addImport("glib", gobject.module("glib2"));
    exe_mod.addImport("gio", gobject.module("gio2"));
    exe_mod.addImport("gobject", gobject.module("gobject2"));
    exe_mod.addImport("webkit", gobject.module("webkit6"));
    exe_mod.addImport("javascriptcore", gobject.module("javascriptcore6"));
    exe_mod.addImport("goose", goose.module("goose"));

    const exe = b.addExecutable(.{
        .name = "netease-music-webplayer",
        .root_module = exe_mod,
    });

    exe.step.dependOn(&patch_gobject.step);
    exe.step.dependOn(&patch_goose.step);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
