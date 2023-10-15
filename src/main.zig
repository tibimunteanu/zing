const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("mach-glfw");
const vk = @import("renderer/vulkan/vk.zig");
const Context = @import("renderer/vulkan/context.zig").Context;

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

    var extent = vk.Extent2D{ .width = 800, .height = 600 };

    const window = glfw.Window.create(extent.width, extent.height, app_name, null, null, .{
        .client_api = .no_api,
    }) orelse {
        std.log.err("Failed to create window: {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    };
    defer window.destroy();

    var context = try Context.init(allocator, app_name, window, .{
        .swapchain = .{
            .desired_extent = extent,
        },
    });
    defer context.deinit();

    std.log.info("Graphics device: {?s}\n", .{context.physical_device.properties.device_name});
    std.log.info("GQ: {}, PQ: {}, CQ: {}, TQ: {}\n", .{
        context.graphics_queue.family_index,
        context.present_queue.family_index,
        context.compute_queue.family_index,
        context.transfer_queue.family_index,
    });

    while (!window.shouldClose()) {
        // const cmdbuf = cmdbufs[swapchain.image_index];

        // const state = swapchain.present(cmdbuf) catch |err| switch (err) {
        //     error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
        //     else => |narrow| return narrow,
        // };

        // if (state == .suboptimal) {
        //     const size = window.getSize();
        //     extent.width = @intCast(size.width);
        //     extent.height = @intCast(size.height);
        //     try swapchain.recreate(extent);

        //     destroyFramebuffers(&gc, allocator, framebuffers);
        //     framebuffers = try createFramebuffers(&gc, allocator, render_pass, swapchain);

        //     destroyCommandBuffers(&gc, pool, allocator, cmdbufs);
        //     cmdbufs = try createCommandBuffers(
        //         &gc,
        //         pool,
        //         allocator,
        //         buffer,
        //         swapchain.extent,
        //         render_pass,
        //         pipeline,
        //         framebuffers,
        //     );
        // }

        glfw.pollEvents();
    }
}
