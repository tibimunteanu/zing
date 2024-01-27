const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("mach-glfw");
const Context = @import("renderer/vulkan/context.zig").Context;
const Allocator = std.mem.Allocator;

pub var engine: Engine = undefined;

fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}\n", .{ error_code, description });
}

fn framebufferSizeCallback(_: glfw.Window, width: u32, height: u32) void {
    engine.context.onResized(glfw.Window.Size{ .width = width, .height = height });
}

pub const Engine = struct {
    const Self = @This();

    window: glfw.Window,
    context: Context,

    pub fn init(allocator: Allocator) !Self {
        var self: Self = undefined;

        glfw.setErrorCallback(errorCallback);

        if (!glfw.init(.{})) {
            std.log.err("Failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
            std.process.exit(1);
        }
        errdefer glfw.terminate();

        self.window = glfw.Window.create(800, 600, "Zing", null, null, .{
            .client_api = .no_api,
        }) orelse {
            std.log.err("Failed to create window: {?s}", .{glfw.getErrorString()});
            std.process.exit(1);
        };
        errdefer self.window.destroy();

        self.context = try Context.init(allocator, "Zing app", self.window);
        errdefer self.context.deinit();

        std.log.info("Graphics device: {?s}", .{self.context.physical_device.properties.device_name});
        std.log.info("GQ: {}, PQ: {}, CQ: {}, TQ: {}", .{
            self.context.graphics_queue.family_index,
            self.context.present_queue.family_index,
            self.context.compute_queue.family_index,
            self.context.transfer_queue.family_index,
        });

        self.window.setFramebufferSizeCallback(framebufferSizeCallback);

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.context.deinit();
        self.window.destroy();
        glfw.terminate();
    }

    pub fn run(self: *Self) !void {
        while (!self.window.shouldClose()) {
            if (self.window.getAttrib(.iconified) == 0) {
                switch (try self.context.beginFrame()) {
                    .resize => {
                        // NOTE: Skip rendering this frame.
                    },
                    .render => {
                        try self.context.endFrame();
                    },
                }
            }
            glfw.pollEvents();
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit() != .ok) unreachable;
    }
    const allocator = gpa.allocator();

    engine = try Engine.init(allocator);
    defer engine.deinit();

    try engine.run();
}
