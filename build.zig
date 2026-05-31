const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const vulkan_sdk = b.option([]const u8, "vulkan-sdk", "Path to the macOS Vulkan SDK") orelse "";

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "zing",
        .root_module = exe_mod,
    });

    exe.root_module.addIncludePath(b.path("vendor/stb"));
    exe.root_module.addCSourceFile(.{
        .file = b.path("vendor/stb/stb_image.c"),
        .flags = &.{ "-std=c99", "-fno-sanitize=undefined" },
    });
    exe.root_module.link_libc = true;

    addGlfw(b, exe, target.result.os.tag, vulkan_sdk);

    const copy_assets = b.addSystemCommand(switch (builtin.os.tag) {
        .windows => &.{ "xcopy", "assets", "zig-out\\bin\\assets\\", "/E/D/Y" },
        .linux => &.{ "rsync", "-r", "-R", "./assets/", "./zig-out/bin/assets" },
        .macos => &.{ "rsync", "-a", "--mkpath", "assets/", "zig-out/bin/assets/" },
        else => unreachable,
    });

    compileShaders(b, &copy_assets.step, &.{
        "phong",
        "ui",
    });

    exe.step.dependOn(&copy_assets.step);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (vulkan_sdk.len > 0) {
        run_cmd.setEnvironmentVariable("VULKAN_SDK", vulkan_sdk);
        run_cmd.setEnvironmentVariable("VK_ICD_FILENAMES", b.fmt("{s}/share/vulkan/icd.d/MoltenVK_icd.json", .{vulkan_sdk}));
        run_cmd.setEnvironmentVariable("VK_DRIVER_FILES", b.fmt("{s}/share/vulkan/icd.d/MoltenVK_icd.json", .{vulkan_sdk}));
        run_cmd.setEnvironmentVariable("VK_ADD_LAYER_PATH", b.fmt("{s}/share/vulkan/explicit_layer.d", .{vulkan_sdk}));
    }

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const unit_tests = b.addTest(.{
        .root_module = unit_tests_mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const test_glfw_step = b.step("test_glfw", "Run GLFW C tests");
    addGlfwTests(b, test_glfw_step, target, optimize, vulkan_sdk);
}

fn addGlfw(b: *std.Build, exe: *std.Build.Step.Compile, os_tag: std.Target.Os.Tag, vulkan_sdk: []const u8) void {
    exe.root_module.addIncludePath(b.path("vendor/glfw/include"));
    exe.root_module.addIncludePath(b.path("vendor/glfw/src"));

    switch (os_tag) {
        .macos => {
            const vulkan_library = if (vulkan_sdk.len > 0)
                b.fmt("{s}/lib/libvulkan.1.dylib", .{vulkan_sdk})
            else
                "libvulkan.1.dylib";
            const flags = &.{
                "-std=c99",
                "-D_GLFW_COCOA",
                b.fmt("-D_GLFW_VULKAN_LIBRARY=\"{s}\"", .{vulkan_library}),
            };

            exe.root_module.addCSourceFiles(.{
                .files = &glfw_common_sources,
                .flags = flags,
            });
            exe.root_module.addCSourceFiles(.{
                .files = &glfw_macos_sources,
                .flags = flags,
            });
            exe.root_module.linkFramework("Cocoa", .{});
            exe.root_module.linkFramework("IOKit", .{});
            exe.root_module.linkFramework("CoreFoundation", .{});
        },
        .windows => {
            const flags = &.{ "-std=c99", "-D_GLFW_WIN32" };
            exe.root_module.addCSourceFiles(.{
                .files = &glfw_common_sources,
                .flags = flags,
            });
            exe.root_module.addCSourceFiles(.{
                .files = &glfw_windows_sources,
                .flags = flags,
            });
            exe.root_module.linkSystemLibrary("gdi32", .{});
            exe.root_module.linkSystemLibrary("user32", .{});
            exe.root_module.linkSystemLibrary("shell32", .{});
        },
        .linux => {
            const flags = &.{ "-std=c99", "-D_GLFW_X11" };
            exe.root_module.addCSourceFiles(.{
                .files = &glfw_common_sources,
                .flags = flags,
            });
            exe.root_module.addCSourceFiles(.{
                .files = &glfw_linux_x11_sources,
                .flags = flags,
            });
            exe.root_module.linkSystemLibrary("dl", .{});
            exe.root_module.linkSystemLibrary("pthread", .{});
            exe.root_module.linkSystemLibrary("m", .{});
        },
        else => @panic("unsupported GLFW target OS"),
    }
}

fn addGlfwTests(
    b: *std.Build,
    test_step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    vulkan_sdk: []const u8,
) void {
    var previous_run: ?*std.Build.Step = null;

    for (glfw_tests) |test_name| {
        const test_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
        });
        const test_exe = b.addExecutable(.{
            .name = b.fmt("glfw-{s}-tests", .{test_name}),
            .root_module = test_mod,
        });

        test_exe.root_module.link_libc = true;
        test_exe.root_module.addIncludePath(b.path("vendor/glfw/include"));
        test_exe.root_module.addIncludePath(b.path("vendor/glfw/tests"));
        test_exe.root_module.addCSourceFile(.{
            .file = b.path(b.fmt("vendor/glfw/tests/{s}.c", .{test_name})),
            .flags = &.{ "-std=c99", "-fno-sanitize=undefined" },
        });

        addGlfw(b, test_exe, target.result.os.tag, vulkan_sdk);

        const run_test = b.addRunArtifact(test_exe);
        if (previous_run) |step|
            run_test.step.dependOn(step);

        previous_run = &run_test.step;
        test_step.dependOn(&run_test.step);
    }
}

const glfw_tests = [_][]const u8{
    "window",
    "monitor",
    "time",
    "joystick",
    "cursor",
    "thread",
};

const glfw_common_sources = [_][]const u8{
    "vendor/glfw/src/init.c",
    "vendor/glfw/src/input.c",
    "vendor/glfw/src/monitor.c",
    "vendor/glfw/src/platform.c",
    "vendor/glfw/src/vulkan.c",
    "vendor/glfw/src/window.c",
};

const glfw_macos_sources = [_][]const u8{
    "vendor/glfw/src/cocoa_time.c",
    "vendor/glfw/src/posix_module.c",
    "vendor/glfw/src/posix_thread.c",
    "vendor/glfw/src/cocoa_init.m",
    "vendor/glfw/src/cocoa_joystick.m",
    "vendor/glfw/src/cocoa_monitor.m",
    "vendor/glfw/src/cocoa_window.m",
};

const glfw_windows_sources = [_][]const u8{
    "vendor/glfw/src/win32_init.c",
    "vendor/glfw/src/win32_joystick.c",
    "vendor/glfw/src/win32_module.c",
    "vendor/glfw/src/win32_monitor.c",
    "vendor/glfw/src/win32_thread.c",
    "vendor/glfw/src/win32_time.c",
    "vendor/glfw/src/win32_window.c",
};

const glfw_linux_x11_sources = [_][]const u8{
    "vendor/glfw/src/posix_module.c",
    "vendor/glfw/src/posix_poll.c",
    "vendor/glfw/src/posix_thread.c",
    "vendor/glfw/src/posix_time.c",
    "vendor/glfw/src/linux_joystick.c",
    "vendor/glfw/src/x11_init.c",
    "vendor/glfw/src/x11_monitor.c",
    "vendor/glfw/src/x11_window.c",
    "vendor/glfw/src/xkb_unicode.c",
};

fn compileShaders(b: *std.Build, copy_assets: *std.Build.Step, comptime shaders: []const []const u8) void {
    const shader_types = [_][]const u8{ "vertex", "fragment" };

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

            copy_assets.dependOn(&compile_shader.step);
        }
    }
}
