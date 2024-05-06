const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zing",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const zmath_dep = b.dependency("zmath", .{ .enable_cross_platform_determinism = true });
    exe.root_module.addImport("zmath", zmath_dep.module("root"));

    const zstbi_dep = b.dependency("zstbi", .{});
    exe.root_module.addImport("zstbi", zstbi_dep.module("root"));
    exe.linkLibrary(zstbi_dep.artifact("zstbi"));

    const zpool_dep = b.dependency("zpool", .{});
    exe.root_module.addImport("zpool", zpool_dep.module("root"));

    const glfw_dep = b.dependency("mach_glfw", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("glfw", glfw_dep.module("mach-glfw"));

    const copy_assets = b.addSystemCommand(switch (builtin.os.tag) {
        .windows => &.{ "xcopy", "assets", "zig-out\\bin\\assets\\", "/E/D/Y" },
        .linux => &.{ "rsync", "-r", "-R", "./assets/", "./zig-out/bin/assets" },
        .macos => &.{ "rsync", "-a", "--mkpath", "assets/", "zig-out/bin/assets/" },
        else => unreachable,
    });

    const shader_steps = try compileShaders(b, &.{
        "phong",
        "ui",
    });
    for (shader_steps.items) |step| {
        copy_assets.step.dependOn(step);
    }

    exe.step.dependOn(&copy_assets.step);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

fn compileShaders(b: *std.Build, comptime shaders: []const []const u8) !std.ArrayList(*std.Build.Step) {
    const shader_types = [_][]const u8{ "vertex", "fragment" };

    var steps = std.ArrayList(*std.Build.Step).init(b.allocator);

    inline for (shader_types) |shader_type| {
        inline for (shaders) |shader| {
            const shader_path = "assets/shaders/" ++ shader ++ "." ++ shader_type[0..4];

            const compile_shader = b.addSystemCommand(&.{
                "glslc",
                "-fshader-stage=" ++ shader_type,
                shader_path ++ ".glsl",
                "--target-env=vulkan1.1",
                "-o",
                shader_path ++ ".spv",
            });

            try steps.append(&compile_shader.step);
        }
    }

    return steps;
}
