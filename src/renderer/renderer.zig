const std = @import("std");
const Context = @import("vulkan/context.zig").Context;
const glfw = @import("mach-glfw");
const zm = @import("zmath");
const Allocator = std.mem.Allocator;
const BeginFrameResult = @import("types.zig").BeginFrameResult;
const GeometryRenderData = @import("types.zig").GeometryRenderData;
const Engine = @import("../engine.zig").Engine;
const Texture = @import("../resources/texture.zig").Texture;
const deg2rad = std.math.degreesToRadians;

fn framebufferSizeCallback(_: glfw.Window, width: u32, height: u32) void {
    Engine.instance.renderer.onResized(glfw.Window.Size{ .width = width, .height = height });
}

pub const Renderer = struct {
    allocator: Allocator,
    context: *Context,

    projection: zm.Mat,
    view: zm.Mat,
    fov: f32,
    near_clip: f32,
    far_clip: f32,

    default_texture: Texture,

    pub fn init(self: *Renderer, allocator: Allocator, window: glfw.Window) !void {
        self.allocator = allocator;

        self.context = try allocator.create(Context);
        errdefer allocator.destroy(self.context);

        try self.context.init(allocator, "Zing app", window);
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

        const tex_dimension: u32 = 64;
        const channels: u32 = 4;
        const pixel_count = tex_dimension * tex_dimension;

        var pixels: [pixel_count * channels]u8 = undefined;
        @memset(&pixels, 255);

        for (0..tex_dimension) |row| {
            for (0..tex_dimension) |col| {
                const index = (row * tex_dimension) + col;
                const index_channel = index * channels;

                if (row % 2 == col % 2) {
                    pixels[index_channel + 0] = 0;
                    pixels[index_channel + 1] = 0;
                }
            }
        }

        self.default_texture = try self.createTexture("default", tex_dimension, tex_dimension, 4, false, false, &pixels);
        errdefer self.destroyTexture(&self.default_texture);
    }

    pub fn deinit(self: *Renderer) void {
        self.destroyTexture(&self.default_texture);

        self.context.deinit();
        self.allocator.destroy(self.context);
    }

    pub fn beginFrame(self: *Renderer, delta_time: f32) !BeginFrameResult {
        return try self.context.beginFrame(delta_time);
    }

    pub fn endFrame(self: *Renderer) !void {
        try self.context.endFrame();
    }

    pub fn drawFrame(self: *Renderer, delta_time: f32) !void {
        switch (try self.beginFrame(delta_time)) {
            .resize => {
                // NOTE: Skip rendering this frame.
            },
            .render => {
                try self.context.updateGlobalState(self.projection, self.view);

                var data: GeometryRenderData = undefined;
                data.object_id = @enumFromInt(0);
                data.model = zm.mul(zm.translation(-5, 0.0, 0.0), zm.rotationY(-0.0));
                data.textures = [_]?*Texture{null} ** 16;
                data.textures[0] = &self.default_texture;

                try self.context.updateObjectState(data);

                self.context.drawFrame();

                try self.endFrame();
            },
        }
    }

    pub fn onResized(self: *Renderer, new_desired_extent: glfw.Window.Size) void {
        self.projection = zm.perspectiveFovLh(
            self.fov,
            @as(f32, @floatFromInt(new_desired_extent.width)) / @as(f32, @floatFromInt(new_desired_extent.height)),
            self.near_clip,
            self.far_clip,
        );
        self.context.onResized(new_desired_extent);
    }

    pub fn waitIdle(self: Renderer) !void {
        try self.context.swapchain.waitForAllFences();
    }

    pub fn createTexture(
        self: *Renderer,
        name: []const u8,
        width: u32,
        height: u32,
        channel_count: u8,
        has_transparency: bool,
        auto_release: bool,
        pixels: []const u8,
    ) !Texture {
        return try self.context.createTexture(
            self.allocator,
            name,
            width,
            height,
            channel_count,
            has_transparency,
            auto_release,
            pixels,
        );
    }

    pub fn destroyTexture(self: *Renderer, texture: *Texture) void {
        self.context.destroyTexture(texture);
    }
};
