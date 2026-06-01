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
    try addGamepadMappingsImport(b, exe_mod);
    try addObjcSupport(b, exe_mod, target, optimize);
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

    addPlatformFrameworks(b, exe, target.result.os.tag);

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
    try addGamepadMappingsImport(b, unit_tests_mod);
    const unit_tests = b.addTest(.{
        .root_module = unit_tests_mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const api_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/api_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    try addZingTestImports(b, api_tests_mod, target, optimize);
    const api_tests = b.addTest(.{
        .root_module = api_tests_mod,
    });
    addPlatformFrameworks(b, api_tests, target.result.os.tag);
    const run_api_tests = b.addRunArtifact(api_tests);

    const test_api_step = b.step("test_api", "Run engine API tests");
    test_api_step.dependOn(&run_api_tests.step);

    const live_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/live_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    try addZingTestImports(b, live_tests_mod, target, optimize);
    const live_tests = b.addTest(.{
        .root_module = live_tests_mod,
    });
    addPlatformFrameworks(b, live_tests, target.result.os.tag);
    const run_live_tests = b.addRunArtifact(live_tests);

    const test_live_step = b.step("test_live", "Run local live engine tests that open and drive native windows");
    test_live_step.dependOn(&run_live_tests.step);

    const test_win32_live_step = b.step("test_win32_live", "Build and run Win32 live tests in the UTM Windows ARM64 VM");
    try addWin32LiveTests(b, test_win32_live_step, optimize);

    const test_glfw_step = b.step("test_glfw", "Run GLFW C tests");
    addGlfwTests(b, test_glfw_step, target, optimize, vulkan_sdk);
}

fn addZingTestImports(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !void {
    const zing_mod = b.createModule(.{
        .root_source_file = b.path("src/zing.zig"),
        .target = target,
        .optimize = optimize,
    });
    try addGamepadMappingsImport(b, zing_mod);
    try addObjcSupport(b, zing_mod, target, optimize);
    module.addImport("zing", zing_mod);
}

fn addGamepadMappingsImport(b: *std.Build, module: *std.Build.Module) !void {
    const mappings_h = try std.Io.Dir.cwd().readFileAlloc(
        b.graph.io,
        "vendor/glfw/src/mappings.h",
        b.allocator,
        .limited(1024 * 1024),
    );

    var source = try std.ArrayList(u8).initCapacity(b.allocator, mappings_h.len + 64);
    defer source.deinit(b.allocator);

    try source.appendSlice(b.allocator, "pub const text =\n");
    var lines = std.mem.splitScalar(u8, mappings_h, '\n');
    while (lines.next()) |line| {
        try source.appendSlice(b.allocator, "\\\\");
        try source.appendSlice(b.allocator, line);
        try source.append(b.allocator, '\n');
    }
    try source.appendSlice(b.allocator, ";\n");

    const write_files = b.addWriteFiles();
    const mappings_zig = write_files.add("gamepad_mappings.zig", source.items);
    const mappings_mod = b.createModule(.{
        .root_source_file = mappings_zig,
        .target = module.resolved_target.?,
        .optimize = module.optimize.?,
    });
    module.addImport("gamepad_mappings", mappings_mod);
}

fn addObjcSupport(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !void {
    switch (target.result.os.tag) {
        .macos => {
            const objc_c = try translateObjcCModule(b, target, optimize);
            module.addImport("objc-c", objc_c);
            module.linkSystemLibrary("objc", .{});
            module.linkFramework("Foundation", .{});
            try addAppleSDK(b, module);
        },
        else => {},
    }
}

fn addPlatformFrameworks(b: *std.Build, compile: *std.Build.Step.Compile, os_tag: std.Target.Os.Tag) void {
    _ = b;
    switch (os_tag) {
        .macos => {
            compile.root_module.link_libc = true;
            compile.root_module.linkFramework("Cocoa", .{});
            compile.root_module.linkFramework("ApplicationServices", .{});
            compile.root_module.linkFramework("Carbon", .{});
            compile.root_module.linkFramework("QuartzCore", .{});
            compile.root_module.linkFramework("IOKit", .{});
            compile.root_module.linkFramework("CoreFoundation", .{});
        },
        .windows => {
            compile.root_module.link_libc = true;
            compile.root_module.linkSystemLibrary("user32", .{});
            compile.root_module.linkSystemLibrary("gdi32", .{});
            compile.root_module.linkSystemLibrary("shell32", .{});
            compile.root_module.linkSystemLibrary("kernel32", .{});
        },
        .linux => {
            compile.root_module.link_libc = true;
            compile.root_module.linkSystemLibrary("dl", .{});
            compile.root_module.linkSystemLibrary("pthread", .{});
            compile.root_module.linkSystemLibrary("m", .{});
        },
        else => {},
    }
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

fn addWin32LiveTests(
    b: *std.Build,
    test_step: *std.Build.Step,
    optimize: std.builtin.OptimizeMode,
) !void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        .os_tag = .windows,
    });
    const test_mod = b.createModule(.{
        .root_source_file = b.path("tests/win32_live_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    try addZingTestImports(b, test_mod, target, optimize);

    const test_exe = b.addExecutable(.{
        .name = "zing-win32-live-tests",
        .root_module = test_mod,
    });
    addPlatformFrameworks(b, test_exe, .windows);

    const install_test = b.addInstallArtifact(test_exe, .{});
    const run_in_vm = b.addSystemCommand(&.{
        "/bin/zsh",
        "scripts/run-utm-windows-test.zsh",
        "zig-out/bin/zing-win32-live-tests.exe",
    });
    run_in_vm.step.dependOn(&install_test.step);
    test_step.dependOn(&run_in_vm.step);
}

fn translateObjcCModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !*std.Build.Module {
    const sdk_path = try appleSDKPath(b, target);
    const include_path = b.pathJoin(&.{ sdk_path, "/usr/include" });
    const runtime_path = b.pathJoin(&.{ include_path, "/objc/runtime.h" });
    const runtime_h = try std.Io.Dir.cwd().readFileAlloc(
        b.graph.io,
        runtime_path,
        b.allocator,
        .limited(1024 * 1024),
    );

    const needle =
        \\objc_enumerateClasses(const void * _Nullable image,
        \\                      const char * _Nullable namePrefix,
        \\                      Protocol * _Nullable conformingTo,
        \\                      Class _Nullable subclassing,
        \\                      void (^ _Nonnull block)(Class _Nonnull aClass, BOOL * _Nonnull stop)
        \\                      OBJC_NOESCAPE)
    ;
    if (std.mem.indexOf(u8, runtime_h, needle) == null) {
        return error.ObjCRuntimeHeaderChanged;
    }

    const patched_runtime_h = try std.mem.replaceOwned(u8, b.allocator, runtime_h, needle,
        \\objc_enumerateClasses(const void * _Nullable image,
        \\                      const char * _Nullable namePrefix,
        \\                      Protocol * _Nullable conformingTo,
        \\                      Class _Nullable subclassing,
        \\                      void * _Nonnull block)
    );

    const write_files = b.addWriteFiles();
    _ = write_files.add("objc/runtime.h", patched_runtime_h);
    const import_h = write_files.add("objc-import.h",
        \\#include <objc/runtime.h>
        \\#include <objc/message.h>
        \\
    );

    const translate_c = b.addTranslateC(.{
        .root_source_file = import_h,
        .target = target,
        .optimize = optimize,
    });
    translate_c.addIncludePath(write_files.getDirectory());
    translate_c.addSystemIncludePath(.{ .cwd_relative = include_path });
    return translate_c.createModule();
}

fn addAppleSDK(b: *std.Build, module: *std.Build.Module) !void {
    const path = try appleSDKPath(b, module.resolved_target.?);
    module.addSystemFrameworkPath(.{ .cwd_relative = b.pathJoin(&.{ path, "/System/Library/Frameworks" }) });
    module.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ path, "/usr/include" }) });
    module.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ path, "/usr/lib" }) });
}

fn appleSDKPath(b: *std.Build, target: std.Build.ResolvedTarget) ![]const u8 {
    const Cache = struct {
        const Key = struct {
            arch: std.Target.Cpu.Arch,
            os: std.Target.Os.Tag,
            abi: std.Target.Abi,
        };

        var map: std.AutoHashMapUnmanaged(Key, ?[]const u8) = .{};
    };

    const gop = try Cache.map.getOrPut(b.allocator, .{
        .arch = target.result.cpu.arch,
        .os = target.result.os.tag,
        .abi = target.result.abi,
    });

    if (!gop.found_existing) {
        gop.value_ptr.* = std.zig.system.darwin.getSdk(
            b.allocator,
            b.graph.io,
            &target.result,
        );
    }

    return gop.value_ptr.* orelse switch (target.result.os.tag) {
        .macos => error.XcodeMacOSSDKNotFound,
        .ios => error.XcodeiOSSDKNotFound,
        .tvos => error.XcodeTVOSSDKNotFound,
        .watchos => error.XcodeWatchOSSDKNotFound,
        else => error.XcodeAppleSDKNotFound,
    };
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
