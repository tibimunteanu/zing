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

const Vertex3D = renderer_types.Vertex3D;
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
    ui_projection: math.Mat,
    ui_view: math.Mat,
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

        self.view = math.inverse(math.translation(0.0, 0.0, -30.0));
        self.ui_view = math.inverse(math.identity());

        self.fov = deg2rad(f32, 45.0);
        self.near_clip = 0.1;
        self.far_clip = 1000.0;

        window.setFramebufferSizeCallback(framebufferSizeCallback);
        self.setProjection(window.getFramebufferSize());
    }

    pub fn deinit(self: *Renderer) void {
        self.context.deinit();
        self.allocator.destroy(self.context);
    }

    pub fn drawFrame(self: *Renderer, packet: RenderPacket) !void {
        switch (try self.context.beginFrame(packet.delta_time)) {
            .resize => {
                // NOTE: Skip rendering this frame.
            },
            .render => {
                try self.context.beginRenderPass(.world);
                try self.context.updateGlobalWorldState(self.projection, self.view);
                for (packet.geometries) |geometry| {
                    try self.context.drawGeometry(geometry);
                }
                try self.context.endRenderPass(.world);

                try self.context.beginRenderPass(.ui);
                try self.context.updateGlobalUIState(self.ui_projection, self.ui_view);
                for (packet.ui_geometries) |ui_geometry| {
                    try self.context.drawGeometry(ui_geometry);
                }
                try self.context.endRenderPass(.ui);

                try self.context.endFrame();

                self.context.frame_index += 1;
            },
        }
    }

    pub fn onResized(self: *Renderer, new_desired_extent: glfw.Window.Size) void {
        self.setProjection(new_desired_extent);

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

    pub fn createGeometry(
        self: *Renderer,
        comptime Vertex: type,
        comptime Index: type,
        geometry: *Geometry,
        vertices: []const Vertex,
        indices: []const Index,
    ) !void {
        try self.context.createGeometry(Vertex, Index, geometry, vertices, indices);
    }

    pub fn destroyGeometry(self: *Renderer, geometry: *Geometry) void {
        if (geometry.internal_id != null) {
            self.context.destroyGeometry(geometry);
        }
    }

    // utils
    fn setProjection(self: *Renderer, size: glfw.Window.Size) void {
        const width = @as(f32, @floatFromInt(size.width));
        const height = @as(f32, @floatFromInt(size.height));

        self.projection = math.perspectiveFovLh(self.fov, width / height, self.near_clip, self.far_clip);
        self.ui_projection = math.orthographicOffCenterLh(0, width, height, 0, -1.0, 1.0);
    }
};
