const std = @import("std");
const Context = @import("vulkan/context.zig").Context;
const glfw = @import("mach-glfw");
const zm = @import("zmath");
const Allocator = std.mem.Allocator;
const BeginFrameResult = @import("types.zig").BeginFrameResult;
const Engine = @import("../main.zig").Engine;
const deg2rad = std.math.degreesToRadians;

fn framebufferSizeCallback(window: glfw.Window, width: u32, height: u32) void {
    const engine = window.getUserPointer(Engine).?;
    engine.renderer.onResized(glfw.Window.Size{ .width = width, .height = height });
}

pub const Renderer = struct {
    const Self = @This();

    context: Context,

    projection: zm.Mat,
    view: zm.Mat,
    fov: f32,
    near_clip: f32,
    far_clip: f32,

    pub fn init(allocator: Allocator, window: glfw.Window) !Self {
        var self: Self = undefined;

        self.context = try Context.init(allocator, "Zing app", window);
        errdefer self.context.deinit();

        std.log.info("Graphics device: {?s}", .{self.context.physical_device.properties.device_name});
        std.log.info("GQ: {}, PQ: {}, CQ: {}, TQ: {}", .{
            self.context.graphics_queue.family_index,
            self.context.present_queue.family_index,
            self.context.compute_queue.family_index,
            self.context.transfer_queue.family_index,
        });

        window.setFramebufferSizeCallback(framebufferSizeCallback);

        self.fov = deg2rad(f32, 45.0);
        self.near_clip = 0.1;
        self.far_clip = 1000.0;

        const fb_size = window.getFramebufferSize();

        self.projection = zm.perspectiveFovLh(
            self.fov,
            @as(f32, @floatFromInt(fb_size.width)) / @as(f32, @floatFromInt(fb_size.height)),
            self.near_clip,
            self.far_clip,
        );

        self.view = zm.inverse(zm.translation(0.0, 0.0, -30.0));

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.context.deinit();
    }

    pub fn beginFrame(self: *Self) !BeginFrameResult {
        return try self.context.beginFrame();
    }

    pub fn endFrame(self: *Self) !void {
        try self.context.endFrame();
    }

    pub fn drawFrame(self: *Self) !void {
        switch (try self.beginFrame()) {
            .resize => {
                // NOTE: Skip rendering this frame.
            },
            .render => {
                try self.context.updateGlobalState(self.projection, self.view);

                const model = zm.mul(zm.translation(-5, 0.0, 0.0), zm.rotationY(-0.3));

                self.context.updateObjectState(model);

                self.context.drawFrame();

                try self.endFrame();
            },
        }
    }

    pub fn onResized(self: *Self, new_desired_extent: glfw.Window.Size) void {
        self.projection = zm.perspectiveFovLh(
            self.fov,
            @as(f32, @floatFromInt(new_desired_extent.width)) / @as(f32, @floatFromInt(new_desired_extent.height)),
            self.near_clip,
            self.far_clip,
        );
        self.context.onResized(new_desired_extent);
    }

    pub fn waitIdle(self: Self) !void {
        try self.context.swapchain.waitForAllFences();
    }
};
