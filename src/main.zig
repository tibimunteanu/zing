const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("mach-glfw");
const GraphicsContext = @import("renderer/vulkan/context.zig").Context;

const app_name = "Zing app";

fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}\n", .{ error_code, description });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit() != .ok) unreachable;
    }
    const allocator = gpa.allocator();

    glfw.setErrorCallback(errorCallback);

    if (!glfw.init(.{})) {
        std.log.err("Failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    }
    defer glfw.terminate();

    const window = glfw.Window.create(640, 480, app_name, null, null, .{
        .client_api = .no_api,
    }) orelse {
        std.log.err("Failed to create window: {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    };
    defer window.destroy();

    const renderer = try GraphicsContext.init(allocator, app_name, window);
    defer renderer.deinit();

    std.log.info("Graphics device: {?s}\n", .{renderer.physical_device.properties.device_name});
    std.log.info("GQ: {}, PQ: {}, CQ: {}, TQ: {}\n", .{
        renderer.graphics_queue.family_index,
        renderer.present_queue.family_index,
        renderer.compute_queue.family_index,
        renderer.transfer_queue.family_index,
    });

    while (!window.shouldClose()) {
        glfw.pollEvents();
    }
}
