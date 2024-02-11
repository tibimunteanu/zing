const std = @import("std");
const zmath = @import("zmath");
const zstbi = @import("zstbi");
const zpool = @import("zpool");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zing",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const zmath_pkg = zmath.package(b, target, optimize, .{
        .options = .{ .enable_cross_platform_determinism = true },
    });
    zmath_pkg.link(exe);

    const zstbi_pkg = zstbi.package(b, target, optimize, .{});
    zstbi_pkg.link(exe);

    const zpool_pkg = zpool.package(b, target, optimize, .{});
    zpool_pkg.link(exe);

    const glfw_dep = b.dependency("mach_glfw", .{
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("mach-glfw", glfw_dep.module("mach-glfw"));

    b.installArtifact(exe);

    const compile_vert_shader = b.addSystemCommand(&.{
        "glslc",
        "assets/shaders/material_shader.vert",
        "--target-env=vulkan1.3",
        "-o",
        "assets/shaders/material_shader.vert.spv",
    });

    const compile_frag_shader = b.addSystemCommand(&.{
        "glslc",
        "assets/shaders/material_shader.frag",
        "--target-env=vulkan1.3",
        "-o",
        "assets/shaders/material_shader.frag.spv",
    });

    const copy_assets = b.addSystemCommand(&.{ "xcopy", "assets", "zig-out\\bin\\assets\\", "/E/D/Y" });

    copy_assets.step.dependOn(&compile_vert_shader.step);
    copy_assets.step.dependOn(&compile_frag_shader.step);

    exe.step.dependOn(&copy_assets.step);

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
