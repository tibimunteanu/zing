const std = @import("std");
const glfw = @import("glfw");
const math = @import("zmath");

const Engine = @import("../engine.zig").Engine;
const Context = @import("vulkan/context.zig").Context;
const MaterialHandle = @import("../systems/material_system.zig").MaterialHandle;

const renderer_types = @import("renderer_types.zig");
const resources_image = @import("../resources/image_resource.zig");
const resources_material = @import("../resources/material_resource.zig");
const resources_geomerty = @import("../resources/geometry_resource.zig");

const Vertex = renderer_types.Vertex;
const RenderPacket = renderer_types.RenderPacket;
const BeginFrameResult = renderer_types.BeginFrameResult;
const GeometryRenderData = renderer_types.GeometryRenderData;

const Texture = resources_image.Texture;
const Material = resources_material.Material;
const Geometry = resources_geomerty.Geometry;

const Allocator = std.mem.Allocator;

const deg2rad = std.math.degreesToRadians;

fn framebufferSizeCallback(_: glfw.Window, width: u32, height: u32) void {
    Engine.instance.renderer.onResized(glfw.Window.Size{ .width = width, .height = height });
}

pub const Renderer = struct {
    allocator: Allocator,
    context: *Context,

    projection: math.Mat,
    view: math.Mat,
    fov: f32,
    near_clip: f32,
    far_clip: f32,

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

        self.projection = math.perspectiveFovLh(
            self.fov,
            @as(f32, @floatFromInt(fb_size.width)) / @as(f32, @floatFromInt(fb_size.height)),
            self.near_clip,
            self.far_clip,
        );

        self.view = math.inverse(math.translation(0.0, 0.0, -30.0));
    }

    pub fn deinit(self: *Renderer) void {
        self.context.deinit();
        self.allocator.destroy(self.context);
    }

    pub fn beginFrame(self: *Renderer, delta_time: f32) !BeginFrameResult {
        return try self.context.beginFrame(delta_time);
    }

    pub fn endFrame(self: *Renderer) !void {
        try self.context.endFrame();
    }

    pub fn drawFrame(self: *Renderer, packet: RenderPacket) !void {
        switch (try self.beginFrame(packet.delta_time)) {
            .resize => {
                // NOTE: Skip rendering this frame.
            },
            .render => {
                try self.context.updateGlobalState(self.projection, self.view);

                for (packet.geometries) |geometry| {
                    try self.context.drawGeometry(geometry);
                }

                try self.endFrame();
            },
        }
    }

    pub fn onResized(self: *Renderer, new_desired_extent: glfw.Window.Size) void {
        self.projection = math.perspectiveFovLh(
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

    pub fn createTexture(self: *Renderer, texture: *Texture, pixels: []const u8) !void {
        try self.context.createTexture(texture, pixels);
    }

    pub fn destroyTexture(self: *Renderer, texture: *Texture) void {
        self.context.destroyTexture(texture);
    }

    pub fn createMaterial(self: *Renderer, material: *Material) !void {
        try self.context.createMaterial(material);
    }

    pub fn destroyMaterial(self: *Renderer, material: *Material) void {
        self.context.destroyMaterial(material);
    }

    pub fn createGeometry(self: *Renderer, geometry: *Geometry, vertices: []const Vertex, indices: []const u32) !void {
        try self.context.createGeometry(geometry, vertices, indices);
    }

    pub fn destroyGeometry(self: *Renderer, geometry: *Geometry) void {
        if (geometry.internal_id != null) {
            self.context.destroyGeometry(geometry);
        }
    }
};
