const std = @import("std");
const glfw = @import("glfw");
const math = @import("zmath");
const config = @import("../config.zig");

const Engine = @import("../engine.zig");
const Context = @import("context.zig");
const Buffer = @import("buffer.zig");
const Material = @import("material.zig");
const Geometry = @import("geometry.zig");
const RenderPass = @import("renderpass.zig");

const MaterialHandle = @import("../systems/material_system.zig").MaterialHandle;
const GeometryHandle = @import("../systems/geometry_system.zig").GeometryHandle;

const Shader = @import("shader.zig");
const ShaderResource = @import("../resources/shader_resource.zig");

const resources_image = @import("../resources/image_resource.zig");
const resources_material = @import("../resources/material_resource.zig");

const Allocator = std.mem.Allocator;
const Array = std.BoundedArray;

const Renderer = @This();

pub const Vertex3D = struct {
    position: [3]f32,
    texcoord: [2]f32,
    color: [4]f32,
};

pub const Vertex2D = struct {
    position: [2]f32,
    texcoord: [2]f32,
    color: [4]f32,
};

pub const geometry_max_count: u32 = 4096;

pub const GeometryData = struct {
    id: ?u32,
    generation: ?u32,
    vertex_count: u32,
    vertex_size: u64,
    vertex_buffer_offset: u64,
    index_count: u32,
    index_size: u64,
    index_buffer_offset: u64,
};

pub const GeometryRenderData = struct {
    model: math.Mat,
    geometry: GeometryHandle,
};

pub const RenderPacket = struct {
    delta_time: f32,
    geometries: []const GeometryRenderData,
    ui_geometries: []const GeometryRenderData,
};

allocator: Allocator, // only to be passed to context
context: *Context,

phong_shader: Shader,
ui_shader: Shader,

vertex_buffer: Buffer,
index_buffer: Buffer,

geometries: [geometry_max_count]GeometryData,

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

    // create shaders
    var phong_shader_resource = try ShaderResource.init(allocator, "phong");
    defer phong_shader_resource.deinit();

    self.phong_shader = try Shader.init(allocator, phong_shader_resource.config.value);
    errdefer self.phong_shader.deinit();

    var ui_shader_resource = try ShaderResource.init(allocator, "ui");
    defer ui_shader_resource.deinit();

    self.ui_shader = try Shader.init(allocator, ui_shader_resource.config.value);
    errdefer self.ui_shader.deinit();

    // create buffers
    self.vertex_buffer = try Buffer.init(
        self.context,
        100 * 1024 * 1024,
        .{ .vertex_buffer_bit = true, .transfer_dst_bit = true, .transfer_src_bit = true },
        .{ .device_local_bit = true },
        .{ .managed = true, .bind_on_create = true },
    );
    errdefer self.vertex_buffer.deinit();

    self.index_buffer = try Buffer.init(
        self.context,
        10 * 1024 * 1024,
        .{ .index_buffer_bit = true, .transfer_dst_bit = true, .transfer_src_bit = true },
        .{ .device_local_bit = true },
        .{ .managed = true, .bind_on_create = true },
    );
    errdefer self.index_buffer.deinit();

    // reset geometry storage
    for (&self.geometries) |*geometry| {
        geometry.*.id = null;
        geometry.*.generation = null;
    }

    self.view = math.inverse(math.translation(0.0, 0.0, -30.0));
    self.ui_view = math.inverse(math.identity());

    self.fov = std.math.degreesToRadians(45.0);
    self.near_clip = 0.1;
    self.far_clip = 1000.0;

    window.setFramebufferSizeCallback(framebufferSizeCallback);
    self.setProjection(window.getFramebufferSize());
}

pub fn deinit(self: *Renderer) void {
    self.context.device_api.deviceWaitIdle(self.context.device) catch {};

    self.vertex_buffer.deinit();
    self.index_buffer.deinit();

    self.ui_shader.deinit();
    self.phong_shader.deinit();

    self.context.deinit();
    self.allocator.destroy(self.context);
}

pub fn drawFrame(self: *Renderer, packet: RenderPacket) !void {
    if (try self.context.beginFrame(packet.delta_time)) {
        try self.beginRenderPass(.world);
        try self.updateGlobalWorldState(self.projection, self.view);
        for (packet.geometries) |geometry| {
            try self.drawGeometry(geometry);
        }

        // TODO: temporary
        {
            var shader = Engine.instance.shader;
            const instance = Engine.instance.shader_instance;

            shader.bind();

            const model_handle = try shader.getUniformHandle("model");

            try shader.setUniform(model_handle, [16]f32{
                1.0, 2.0, 3.0, 1.0, //
                1.0, 2.0, 3.0, 1.0, //
                1.0, 2.0, 3.0, 1.0, //
                1.0, 2.0, 3.0, 1.0,
            });

            shader.bindGlobal();
            try shader.applyGlobal();

            try shader.bindInstance(instance);

            try shader.setUniform("diffuse_color", [4]f32{ 0.1, 0.2, 0.8, 1.0 });
            try shader.setUniform("diffuse_texture", Engine.instance.texture_system.acquireDefaultTexture());

            try shader.applyInstance();
        }
        // TODO: end temporary

        try self.endRenderPass(.world);

        try self.beginRenderPass(.ui);
        try self.updateGlobalUIState(self.ui_projection, self.ui_view);
        for (packet.ui_geometries) |ui_geometry| {
            try self.drawGeometry(ui_geometry);
        }
        try self.endRenderPass(.ui);

        try self.context.endFrame();

        self.context.frame_index += 1;
    }
}

pub fn onResized(self: *Renderer, new_desired_extent: glfw.Window.Size) void {
    self.setProjection(new_desired_extent);

    self.context.onResized(new_desired_extent);
}

pub fn waitIdle(self: *const Renderer) !void {
    try self.context.swapchain.waitForAllFences();
}

pub fn createMaterial(self: *Renderer, material: *Material) !void {
    switch (material.material_type) {
        .world => material.instance_handle = try self.phong_shader.initInstance(),
        .ui => material.instance_handle = try self.ui_shader.initInstance(),
    }
}

pub fn destroyMaterial(self: *Renderer, material: *Material) void {
    if (material.instance_handle) |instance_handle| {
        switch (material.material_type) {
            .world => self.phong_shader.deinitInstance(instance_handle),
            .ui => self.ui_shader.deinitInstance(instance_handle),
        }
    }
}

pub fn createGeometry(self: *Renderer, geometry: *Geometry, vertices: anytype, indices: anytype) !void {
    if (vertices.len == 0) {
        return error.VerticesCannotBeEmpty;
    }

    var prev_internal_data: GeometryData = undefined;
    var internal_data: ?*GeometryData = null;

    const is_reupload = geometry.internal_id != null;
    if (is_reupload) {
        internal_data = &self.geometries[geometry.internal_id.?];

        // take a copy of the old region
        prev_internal_data = internal_data.?.*;
    } else {
        for (&self.geometries, 0..) |*slot, i| {
            if (slot.id == null) {
                const id: u32 = @truncate(i);
                geometry.internal_id = id;
                slot.*.id = id;
                internal_data = slot;
                break;
            }
        }
    }

    if (internal_data) |data| {
        data.vertex_count = @truncate(vertices.len);
        data.vertex_size = @sizeOf(std.meta.Elem(@TypeOf(vertices)));
        data.vertex_buffer_offset = try self.vertex_buffer.allocAndUpload(std.mem.sliceAsBytes(vertices));

        if (indices.len > 0) {
            data.index_count = @truncate(indices.len);
            data.index_size = @sizeOf(std.meta.Elem(@TypeOf(indices)));
            data.index_buffer_offset = try self.index_buffer.allocAndUpload(std.mem.sliceAsBytes(indices));
        }

        data.generation = if (geometry.generation) |g| g +% 1 else 0;

        if (is_reupload) {
            try self.vertex_buffer.free(
                prev_internal_data.vertex_buffer_offset,
                prev_internal_data.vertex_count * prev_internal_data.vertex_size,
            );

            if (prev_internal_data.index_count > 0) {
                try self.index_buffer.free(
                    prev_internal_data.index_buffer_offset,
                    prev_internal_data.index_count * prev_internal_data.index_size,
                );
            }
        }
    } else {
        return error.FaildToReserveInternalData;
    }
}

pub fn destroyGeometry(self: *Renderer, geometry: *Geometry) void {
    if (geometry.internal_id != null) {
        self.context.device_api.deviceWaitIdle(self.context.device) catch {
            std.log.err("Could not destroy geometry {s}", .{geometry.name.slice()});
        };

        const internal_data = &self.geometries[geometry.internal_id.?];

        self.vertex_buffer.free(
            internal_data.vertex_buffer_offset,
            internal_data.vertex_size,
        ) catch unreachable;

        if (internal_data.index_size > 0) {
            self.index_buffer.free(
                internal_data.index_buffer_offset,
                internal_data.index_size,
            ) catch unreachable;
        }

        internal_data.* = std.mem.zeroes(GeometryData);
        internal_data.id = null;
        internal_data.generation = null;
    }
}

pub fn drawGeometry(self: *Renderer, data: GeometryRenderData) !void {
    const command_buffer = self.context.getCurrentCommandBuffer();

    const geometry: *Geometry = try Engine.instance.geometry_system.geometries.getColumnPtr(data.geometry, .geometry);

    const material_handle = if (Engine.instance.material_system.materials.isLiveHandle(geometry.material)) //
        geometry.material
    else
        Engine.instance.material_system.getDefaultMaterial();

    const material: *Material = try Engine.instance.material_system.materials.getColumnPtr(material_handle, .material);

    switch (material.material_type) {
        .world => {
            try self.phong_shader.setUniform("model", data.model);

            try self.phong_shader.bindInstance(material.instance_handle.?);

            try self.phong_shader.setUniform("diffuse_color", material.diffuse_color);
            try self.phong_shader.setUniform("diffuse_texture", material.diffuse_map.texture);

            try self.phong_shader.applyInstance();
        },
        .ui => {
            try self.ui_shader.setUniform("model", data.model);

            try self.ui_shader.bindInstance(material.instance_handle.?);

            try self.ui_shader.setUniform("diffuse_color", material.diffuse_color);
            try self.ui_shader.setUniform("diffuse_texture", material.diffuse_map.texture);

            try self.ui_shader.applyInstance();
        },
    }

    const buffer_data = self.geometries[geometry.internal_id.?];

    self.context.device_api.cmdBindVertexBuffers(
        command_buffer.handle,
        0,
        1,
        @ptrCast(&self.vertex_buffer.handle),
        @ptrCast(&[_]u64{buffer_data.vertex_buffer_offset}),
    );

    if (buffer_data.index_count > 0) {
        self.context.device_api.cmdBindIndexBuffer(
            command_buffer.handle,
            self.index_buffer.handle,
            buffer_data.index_buffer_offset,
            .uint32,
        );

        self.context.device_api.cmdDrawIndexed(command_buffer.handle, buffer_data.index_count, 1, 0, 0, 0);
    } else {
        self.context.device_api.cmdDraw(command_buffer.handle, buffer_data.vertex_count, 1, 0, 0);
    }
}

pub fn beginRenderPass(self: *Renderer, render_pass_type: RenderPass.Type) !void {
    const command_buffer = self.context.getCurrentCommandBuffer();

    switch (render_pass_type) {
        .world => {
            self.context.world_render_pass.begin(command_buffer, self.context.getCurrentWorldFramebuffer());
            self.phong_shader.bind();
        },
        .ui => {
            self.context.ui_render_pass.begin(command_buffer, self.context.getCurrentFramebuffer());
            self.ui_shader.bind();
        },
    }
}

pub fn endRenderPass(self: *Renderer, render_pass_type: RenderPass.Type) !void {
    const command_buffer = self.context.getCurrentCommandBuffer();

    switch (render_pass_type) {
        .world => self.context.world_render_pass.end(command_buffer),
        .ui => self.context.ui_render_pass.end(command_buffer),
    }
}

pub fn updateGlobalWorldState(self: *Renderer, projection: math.Mat, view: math.Mat) !void {
    self.phong_shader.bindGlobal();

    try self.phong_shader.setUniform("projection", projection);
    try self.phong_shader.setUniform("view", view);

    try self.phong_shader.applyGlobal();
}

pub fn updateGlobalUIState(self: *Renderer, projection: math.Mat, view: math.Mat) !void {
    self.ui_shader.bindGlobal();

    try self.ui_shader.setUniform("projection", projection);
    try self.ui_shader.setUniform("view", view);

    try self.ui_shader.applyGlobal();
}

// utils
fn setProjection(self: *Renderer, size: glfw.Window.Size) void {
    const width = @as(f32, @floatFromInt(size.width));
    const height = @as(f32, @floatFromInt(size.height));

    self.projection = math.perspectiveFovLh(self.fov, width / height, self.near_clip, self.far_clip);
    self.ui_projection = math.orthographicOffCenterLh(0, width, height, 0, -1.0, 1.0);
}

fn framebufferSizeCallback(_: glfw.Window, width: u32, height: u32) void {
    Engine.instance.renderer.onResized(glfw.Window.Size{ .width = width, .height = height });
}
