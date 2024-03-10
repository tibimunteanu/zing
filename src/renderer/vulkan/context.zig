const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("glfw");
const vk = @import("vk.zig");
const math = @import("zmath");

const Engine = @import("../../engine.zig");
const Renderer = @import("../renderer.zig");
const Swapchain = @import("swapchain.zig");
const RenderPass = @import("renderpass.zig");
const CommandBuffer = @import("command_buffer.zig");
const MaterialShader = @import("material_shader.zig");
const UIShader = @import("ui_shader.zig");
const Buffer = @import("buffer.zig");
const Image = @import("image.zig");
const Texture = @import("../texture.zig");
const Material = @import("../material.zig");
const Geometry = @import("../geometry.zig");

const resources_image = @import("../../resources/image_resource.zig");
const resources_material = @import("../../resources/material_resource.zig");

const Vertex3D = Renderer.Vertex3D;
const GeometryRenderData = Renderer.GeometryRenderData;

const Allocator = std.mem.Allocator;

const Context = @This();

const required_device_extensions = [_][*:0]const u8{
    vk.extension_info.khr_swapchain.name,
};

const optional_device_extensions = [_][*:0]const u8{
    // nothing here yet
};

const optional_instance_extensions = [_][*:0]const u8{
    // nothing here yet
};

const BaseAPI = vk.BaseWrapper(.{
    .createInstance = true,
    .enumerateInstanceExtensionProperties = true,
    .getInstanceProcAddr = true,
});

const InstanceAPI = vk.InstanceWrapper(.{
    .destroyInstance = true,
    .createDevice = true,
    .destroySurfaceKHR = true,
    .enumeratePhysicalDevices = true,
    .getPhysicalDeviceFeatures = true,
    .getPhysicalDeviceProperties = true,
    .enumerateDeviceExtensionProperties = true,
    .getPhysicalDeviceFormatProperties = true,
    .getPhysicalDeviceSurfaceFormatsKHR = true,
    .getPhysicalDeviceSurfacePresentModesKHR = true,
    .getPhysicalDeviceSurfaceCapabilitiesKHR = true,
    .getPhysicalDeviceQueueFamilyProperties = true,
    .getPhysicalDeviceSurfaceSupportKHR = true,
    .getPhysicalDeviceMemoryProperties = true,
    .getDeviceProcAddr = true,
});

const DeviceAPI = vk.DeviceWrapper(.{
    .destroyDevice = true,
    .getDeviceQueue = true,
    .createSemaphore = true,
    .createFence = true,
    .createImageView = true,
    .createDescriptorSetLayout = true,
    .createDescriptorPool = true,
    .allocateDescriptorSets = true,
    .cmdBindDescriptorSets = true,
    .updateDescriptorSets = true,
    .freeDescriptorSets = true,
    .createSampler = true,
    .destroySampler = true,
    .destroyImageView = true,
    .destroySemaphore = true,
    .destroyFence = true,
    .destroyDescriptorSetLayout = true,
    .destroyDescriptorPool = true,
    .getSwapchainImagesKHR = true,
    .createSwapchainKHR = true,
    .destroySwapchainKHR = true,
    .acquireNextImageKHR = true,
    .deviceWaitIdle = true,
    .waitForFences = true,
    .resetFences = true,
    .queueSubmit = true,
    .queuePresentKHR = true,
    .createImage = true,
    .destroyImage = true,
    .bindImageMemory = true,
    .createCommandPool = true,
    .destroyCommandPool = true,
    .allocateCommandBuffers = true,
    .freeCommandBuffers = true,
    .resetCommandBuffer = true,
    .queueWaitIdle = true,
    .createShaderModule = true,
    .destroyShaderModule = true,
    .createPipelineLayout = true,
    .destroyPipelineLayout = true,
    .createRenderPass = true,
    .destroyRenderPass = true,
    .createGraphicsPipelines = true,
    .destroyPipeline = true,
    .createFramebuffer = true,
    .destroyFramebuffer = true,
    .beginCommandBuffer = true,
    .endCommandBuffer = true,
    .allocateMemory = true,
    .freeMemory = true,
    .createBuffer = true,
    .destroyBuffer = true,
    .getBufferMemoryRequirements = true,
    .getImageMemoryRequirements = true,
    .mapMemory = true,
    .unmapMemory = true,
    .bindBufferMemory = true,
    .cmdBeginRenderPass = true,
    .cmdEndRenderPass = true,
    .cmdBindPipeline = true,
    .cmdPipelineBarrier = true,
    .cmdDraw = true,
    .cmdDrawIndexed = true,
    .cmdSetViewport = true,
    .cmdSetScissor = true,
    .cmdBindVertexBuffers = true,
    .cmdBindIndexBuffer = true,
    .cmdCopyBuffer = true,
    .cmdCopyBufferToImage = true,
    .cmdPushConstants = true,
});

const desired_depth_formats: []const vk.Format = &[_]vk.Format{
    .d32_sfloat,
    .d32_sfloat_s8_uint,
    .d24_unorm_s8_uint,
};

pub const TextureData = struct {
    image: Image,
    sampler: vk.Sampler,
};

pub const geometry_max_count: u32 = 4096;

pub const GeometryData = struct {
    id: ?u32,
    generation: ?u32,
    vertex_count: u32,
    vertex_size: u32,
    vertex_buffer_offset: u32,
    index_count: u32,
    index_size: u32,
    index_buffer_offset: u32,
};

// TODO: replace ArrayList(XXX) with BoundedArray(XXX, 3)
// NOTE: used to:
// - dynamic arrays for framebuffers and cmd buffers
// - prep instance and device extensions
// - enumerate physical devices
// - passed to the swapchain to interogate surface formats and presentation modes
// - passed to shaders to load shader resources
// - allocate internal data on createTexture calls
allocator: Allocator,

base_api: BaseAPI,
instance_api: InstanceAPI,
device_api: DeviceAPI,

instance: vk.Instance,
surface: vk.SurfaceKHR,
physical_device: PhysicalDevice,
device: vk.Device,

graphics_queue: Queue,
present_queue: Queue,
compute_queue: Queue,
transfer_queue: Queue,

swapchain: Swapchain,
framebuffers: std.ArrayList(vk.Framebuffer),
world_framebuffers: std.ArrayList(vk.Framebuffer),

world_render_pass: RenderPass,
ui_render_pass: RenderPass,

graphics_command_pool: vk.CommandPool,
graphics_command_buffers: std.ArrayList(CommandBuffer),

material_shader: MaterialShader,
ui_shader: UIShader,

vertex_buffer: Buffer,
vertex_offset: usize,

index_buffer: Buffer,
index_offset: usize,

geometries: [geometry_max_count]GeometryData,

desired_extent: glfw.Window.Size,
desired_extent_generation: u32,

frame_index: u64,
delta_time: f32,

// public
pub fn init(self: *Context, allocator: Allocator, app_name: [*:0]const u8, window: glfw.Window) !void {
    self.allocator = allocator;

    self.desired_extent = window.getFramebufferSize();
    self.desired_extent_generation = 0;

    // load base api
    const base_loader = @as(vk.PfnGetInstanceProcAddr, @ptrCast(&glfw.getInstanceProcAddress));
    self.base_api = try BaseAPI.load(base_loader);

    // create instance and load instance api
    self.instance = try createInstance(allocator, self.base_api, app_name);

    const instance_loader = self.base_api.dispatch.vkGetInstanceProcAddr;
    self.instance_api = try InstanceAPI.load(self.instance, instance_loader);
    errdefer self.instance_api.destroyInstance(self.instance, null);

    // create surface
    self.surface = try createSurface(self.instance, window);
    errdefer self.instance_api.destroySurfaceKHR(self.instance, self.surface, null);

    // pick a suitable physical device
    self.physical_device = try pickPhysicalDevice(allocator, self.instance, self.instance_api, self.surface);

    // create logical device and load device api
    self.device = try createDevice(allocator, self.physical_device, self.instance_api);

    const device_loader = self.instance_api.dispatch.vkGetDeviceProcAddr;
    self.device_api = try DeviceAPI.load(self.device, device_loader);
    errdefer self.device_api.destroyDevice(self.device, null);

    // get queues
    self.graphics_queue = Queue.init(self, self.physical_device.graphics_family_index);
    self.present_queue = Queue.init(self, self.physical_device.present_family_index);
    self.compute_queue = Queue.init(self, self.physical_device.compute_family_index);
    self.transfer_queue = Queue.init(self, self.physical_device.transfer_family_index);

    // create swapchain
    self.swapchain = try Swapchain.init(allocator, self, .{});
    errdefer self.swapchain.deinit();

    // create renderpasses
    self.world_render_pass = try RenderPass.init(
        self,
        .{
            .clear_flags = .{
                .color = true,
                .depth = true,
                .stencil = true,
            },
            .clear_values = .{
                .color = [_]f32{ 0.1, 0.2, 0.6, 1.0 },
                .depth = 1.0,
                .stencil = 0,
            },
            .has_prev = false,
            .has_next = true,
        },
    );
    errdefer self.world_render_pass.deinit();

    self.ui_render_pass = try RenderPass.init(
        self,
        .{
            .has_prev = true,
            .has_next = false,
        },
    );
    errdefer self.ui_render_pass.deinit();

    // create framebuffers
    self.framebuffers = try std.ArrayList(vk.Framebuffer).initCapacity(allocator, self.swapchain.images.len);
    errdefer self.framebuffers.deinit();

    self.world_framebuffers = try std.ArrayList(vk.Framebuffer).initCapacity(allocator, self.swapchain.images.len);
    errdefer self.world_framebuffers.deinit();

    try self.initFramebuffers();
    errdefer self.deinitFramebuffers();

    // create command pool
    self.graphics_command_pool = try self.device_api.createCommandPool(self.device, &vk.CommandPoolCreateInfo{
        .queue_family_index = self.graphics_queue.family_index,
        .flags = .{ .reset_command_buffer_bit = true },
    }, null);
    errdefer self.device_api.destroyCommandPool(self.device, self.graphics_command_pool, null);

    // create command buffers
    self.graphics_command_buffers = try std.ArrayList(CommandBuffer).initCapacity(
        self.allocator,
        self.swapchain.images.len,
    );
    errdefer self.graphics_command_buffers.deinit();

    try self.initCommandBuffers();
    errdefer self.deinitCommandBuffers();

    // create shaders
    self.material_shader = try MaterialShader.init(allocator, self);
    errdefer self.material_shader.deinit();

    self.ui_shader = try UIShader.init(allocator, self);
    errdefer self.ui_shader.deinit();

    // create buffers
    self.vertex_buffer = try Buffer.init(
        self,
        100 * 1024 * 1024,
        .{ .vertex_buffer_bit = true, .transfer_dst_bit = true, .transfer_src_bit = true },
        .{ .device_local_bit = true },
        .{ .bind_on_create = true },
    );
    self.vertex_offset = 0;
    errdefer self.vertex_buffer.deinit();

    self.index_buffer = try Buffer.init(
        self,
        10 * 1024 * 1024,
        .{ .index_buffer_bit = true, .transfer_dst_bit = true, .transfer_src_bit = true },
        .{ .device_local_bit = true },
        .{ .bind_on_create = true },
    );
    self.index_offset = 0;
    errdefer self.index_buffer.deinit();

    // reset geometry storage
    for (&self.geometries) |*geometry| {
        geometry.*.id = null;
        geometry.*.generation = null;
    }

    self.frame_index = 0;
    self.delta_time = 1.0 / 60.0;
}

pub fn deinit(self: *Context) void {
    self.device_api.deviceWaitIdle(self.device) catch {};

    self.vertex_buffer.deinit();
    self.index_buffer.deinit();

    self.ui_shader.deinit();
    self.material_shader.deinit();

    self.deinitCommandBuffers();
    self.graphics_command_buffers.deinit();

    self.device_api.destroyCommandPool(self.device, self.graphics_command_pool, null);

    self.deinitFramebuffers();
    self.world_framebuffers.deinit();
    self.framebuffers.deinit();

    self.ui_render_pass.deinit();
    self.world_render_pass.deinit();

    self.swapchain.deinit();

    self.device_api.destroyDevice(self.device, null);
    self.instance_api.destroySurfaceKHR(self.instance, self.surface, null);
    self.instance_api.destroyInstance(self.instance, null);
}

pub fn onResized(self: *Context, new_desired_extent: glfw.Window.Size) void {
    self.desired_extent = new_desired_extent;
    self.desired_extent_generation += 1;
}

pub fn getMemoryIndex(self: Context, type_bits: u32, flags: vk.MemoryPropertyFlags) !u32 {
    // TODO: should we always get fresh memory properties from the device?
    // const memory_properties = self.instance_api.getPhysicalDeviceMemoryProperties(self.physical_device.handle);

    for (0..self.physical_device.memory_properties.memory_type_count) |i| {
        if ((type_bits & std.math.shl(u32, 1, i) != 0) and self.physical_device.memory_properties.memory_types[i].property_flags.contains(flags)) {
            return @intCast(i);
        }
    }

    return error.GetMemoryIndexFailed;
}

pub fn allocate(self: Context, requirements: vk.MemoryRequirements, flags: vk.MemoryPropertyFlags) !vk.DeviceMemory {
    return try self.device_api.allocateMemory(self.device, &.{
        .allocation_size = requirements.size,
        .memory_type_index = try self.getMemoryIndex(requirements.memory_type_bits, flags),
    }, null);
}

pub fn beginFrame(self: *Context, delta_time: f32) !Renderer.BeginFrameResult {
    self.delta_time = delta_time;

    if (self.desired_extent_generation != self.swapchain.extent_generation) {
        // NOTE: we could skip this and let the frame render and present will throw error.OutOfDateKHR
        // which is handled by endFrame() by recreating resources, but this way we avoid a best practices warning
        try self.reinitSwapchainFramebuffersAndCmdBuffers();
        return .resize;
    }

    const current_image = self.swapchain.getCurrentImage();
    var command_buffer = self.getCurrentCommandBuffer();

    // make sure the current frame has finished rendering.
    // NOTE: the fences start signaled so the first frame can get past them.
    try current_image.waitForFrameFence(.{ .reset = true });

    try command_buffer.begin(.{});

    const viewport: vk.Viewport = .{
        .x = 0.0,
        .y = @floatFromInt(self.swapchain.extent.height),
        .width = @floatFromInt(self.swapchain.extent.width),
        .height = @floatFromInt(-@as(i32, @intCast(self.swapchain.extent.height))),
        .min_depth = 0.0,
        .max_depth = 1.0,
    };

    const scissor: vk.Rect2D = .{
        .offset = .{ .x = 0, .y = 0 },
        .extent = self.swapchain.extent,
    };

    self.device_api.cmdSetViewport(command_buffer.handle, 0, 1, @ptrCast(&viewport));
    self.device_api.cmdSetScissor(command_buffer.handle, 0, 1, @ptrCast(&scissor));

    return .render;
}

pub fn endFrame(self: *Context) !void {
    const current_image = self.swapchain.getCurrentImage();
    var command_buffer = self.getCurrentCommandBuffer();

    // end the command buffer
    try command_buffer.end();

    // submit the command buffer
    try self.device_api.queueSubmit(self.graphics_queue.handle, 1, &[_]vk.SubmitInfo{.{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&current_image.image_acquired_semaphore),
        .p_wait_dst_stage_mask = &[_]vk.PipelineStageFlags{.{ .color_attachment_output_bit = true }},
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&command_buffer.handle),
        .signal_semaphore_count = 1,
        .p_signal_semaphores = @ptrCast(&current_image.render_finished_semaphore),
    }}, current_image.frame_fence);

    const state = self.swapchain.present() catch |err| switch (err) {
        error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
        else => |narrow| return narrow,
    };

    // NOTE: we should always recreate resources when error.OutOfDateKHR, but here,
    // we decided to also always recreate resources when the result is .suboptimal.
    // this should be configurable, so that you can choose if you only want to recreate on error.
    if (state == .suboptimal) {
        std.log.info("endFrame() Present was suboptimal. Recreating resources.", .{});
        try self.reinitSwapchainFramebuffersAndCmdBuffers();
    }
}

pub fn beginRenderPass(self: *Context, render_pass_type: RenderPass.Type) !void {
    const command_buffer = self.getCurrentCommandBuffer();

    switch (render_pass_type) {
        .world => {
            self.world_render_pass.begin(command_buffer, self.getCurrentWorldFramebuffer());
            self.material_shader.bind(command_buffer);
        },
        .ui => {
            self.ui_render_pass.begin(command_buffer, self.getCurrentFramebuffer());
            self.ui_shader.bind(command_buffer);
        },
    }
}

pub fn endRenderPass(self: *Context, render_pass_type: RenderPass.Type) !void {
    const command_buffer = self.getCurrentCommandBuffer();

    switch (render_pass_type) {
        .world => self.world_render_pass.end(command_buffer),
        .ui => self.ui_render_pass.end(command_buffer),
    }
}

pub fn getCurrentCommandBuffer(self: Context) *CommandBuffer {
    return &self.graphics_command_buffers.items[self.swapchain.image_index];
}

pub fn getCurrentFramebuffer(self: Context) vk.Framebuffer {
    return self.framebuffers.items[self.swapchain.image_index];
}

pub fn getCurrentWorldFramebuffer(self: Context) vk.Framebuffer {
    return self.world_framebuffers.items[self.swapchain.image_index];
}

pub fn updateGlobalWorldState(self: *Context, projection: math.Mat, view: math.Mat) !void {
    // const command_buffer = self.getCurrentCommandBuffer();
    // self.material_shader.bind(command_buffer);

    self.material_shader.global_uniform_data.projection = projection;
    self.material_shader.global_uniform_data.view = view;

    try self.material_shader.updateGlobalUniformData();
}

pub fn updateGlobalUIState(self: *Context, projection: math.Mat, view: math.Mat) !void {
    // const command_buffer = self.getCurrentCommandBuffer();
    // self.ui_shader.bind(command_buffer);

    self.ui_shader.global_uniform_data.projection = projection;
    self.ui_shader.global_uniform_data.view = view;

    try self.ui_shader.updateGlobalUniformData();
}

pub fn createTexture(self: *Context, texture: *Texture, pixels: []const u8) !void {
    const internal_data = try self.allocator.create(TextureData);
    errdefer self.allocator.destroy(internal_data);

    texture.internal_data = internal_data;

    const image_size: vk.DeviceSize = texture.width * texture.height * texture.channel_count;
    const image_format: vk.Format = .r8g8b8a8_srgb;

    var staging_buffer = try Buffer.init(
        self,
        image_size,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        .{ .bind_on_create = true },
    );
    defer staging_buffer.deinit();

    try staging_buffer.loadData(0, image_size, .{}, pixels);

    internal_data.image = try Image.init(self, .{
        .width = texture.width,
        .height = texture.height,
        .format = image_format,
        .usage = .{
            .transfer_src_bit = true,
            .transfer_dst_bit = true,
            .color_attachment_bit = true,
            .sampled_bit = true,
        },
        .memory_flags = .{ .device_local_bit = true },
        .init_view = true,
        .view_aspect_flags = .{ .color_bit = true },
    });
    errdefer internal_data.image.deinit();

    var command_buffer = try CommandBuffer.initAndBeginSingleUse(self, self.graphics_command_pool);

    try internal_data.image.transitionLayout(
        command_buffer,
        image_format,
        .undefined,
        .transfer_dst_optimal,
    );

    internal_data.image.copyFromBuffer(command_buffer, staging_buffer.handle);

    try internal_data.image.transitionLayout(
        command_buffer,
        image_format,
        .transfer_dst_optimal,
        .shader_read_only_optimal,
    );

    try command_buffer.endSingleUseAndDeinit(self.graphics_queue.handle);

    internal_data.sampler = try self.device_api.createSampler(self.device, &vk.SamplerCreateInfo{
        .mag_filter = .linear,
        .min_filter = .linear,
        .address_mode_u = .repeat,
        .address_mode_v = .repeat,
        .address_mode_w = .repeat,
        .anisotropy_enable = 0,
        .max_anisotropy = 16,
        .border_color = .int_opaque_black,
        .unnormalized_coordinates = 0,
        .compare_enable = 0,
        .compare_op = .always,
        .mipmap_mode = .linear,
        .mip_lod_bias = 0,
        .min_lod = 0,
        .max_lod = 0,
    }, null);
}

pub fn destroyTexture(self: *Context, texture: *Texture) void {
    self.device_api.deviceWaitIdle(self.device) catch {};

    const internal_data: ?*TextureData = @ptrCast(@alignCast(texture.internal_data));
    if (internal_data) |data| {
        data.image.deinit();
        self.device_api.destroySampler(self.device, data.sampler, null);

        self.allocator.destroy(data);
    }
}

pub fn createMaterial(self: *Context, material: *Material) !void {
    switch (material.material_type) {
        .world => try self.material_shader.acquireResources(material),
        .ui => try self.ui_shader.acquireResources(material),
    }
}

pub fn destroyMaterial(self: *Context, material: *Material) void {
    if (material.internal_id != null) {
        switch (material.material_type) {
            .world => self.material_shader.releaseResources(material),
            .ui => self.ui_shader.releaseResources(material),
        }
    }
}

pub fn createGeometry(
    self: *Context,
    comptime Vertex: type,
    comptime Index: type,
    geometry: *Geometry,
    vertices: []const Vertex,
    indices: []const u32,
) !void {
    if (vertices.len == 0) {
        return error.VerticesCannotBeEmpty;
    }

    var old_region: GeometryData = undefined;
    var internal_data: ?*GeometryData = null;

    const is_reupload = geometry.internal_id != null;
    if (is_reupload) {
        internal_data = &self.geometries[geometry.internal_id.?];

        // take a copy of the old region
        old_region = internal_data.?.*;
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
        // vertex data
        data.vertex_buffer_offset = @truncate(self.vertex_offset);
        data.vertex_count = @truncate(vertices.len);
        data.vertex_size = @truncate(@sizeOf(Vertex) * vertices.len);

        // upload data to buffers
        try self.uploadDataRegion(
            &self.vertex_buffer,
            data.vertex_buffer_offset,
            data.vertex_size,
            std.mem.sliceAsBytes(vertices),
        );

        self.vertex_offset += data.vertex_size;

        if (indices.len > 0) {
            data.index_buffer_offset = @truncate(self.index_offset);
            data.index_count = @truncate(indices.len);
            data.index_size = @truncate(@sizeOf(Index) * indices.len);

            try self.uploadDataRegion(
                &self.index_buffer,
                data.index_buffer_offset,
                data.index_size,
                std.mem.sliceAsBytes(indices),
            );

            self.index_offset += data.index_size;
        }

        data.generation = if (geometry.generation) |g| g +% 1 else 0;

        if (is_reupload) {
            self.freeDataRegion(
                &self.vertex_buffer,
                old_region.vertex_buffer_offset,
                old_region.vertex_size,
            );

            if (old_region.index_size > 0) {
                self.freeDataRegion(
                    &self.index_buffer,
                    old_region.index_buffer_offset,
                    old_region.index_size,
                );
            }
        }
    } else {
        return error.FaildToReserveInternalData;
    }
}

pub fn destroyGeometry(self: *Context, geometry: *Geometry) void {
    if (geometry.internal_id != null) {
        self.device_api.deviceWaitIdle(self.device) catch {
            std.log.err("Could not destroy geometry {s}", .{geometry.name.slice()});
        };

        const internal_data = &self.geometries[geometry.internal_id.?];

        self.freeDataRegion(
            &self.vertex_buffer,
            internal_data.vertex_buffer_offset,
            internal_data.vertex_size,
        );

        if (internal_data.index_size > 0) {
            self.freeDataRegion(
                &self.index_buffer,
                internal_data.index_buffer_offset,
                internal_data.index_size,
            );
        }

        internal_data.* = std.mem.zeroes(GeometryData);
        internal_data.id = null;
        internal_data.generation = null;
    }
}

pub fn drawGeometry(self: *Context, data: GeometryRenderData) !void {
    const command_buffer = self.getCurrentCommandBuffer();

    const geometry: *Geometry = try Engine.instance.geometry_system.geometries.getColumnPtr(data.geometry, .geometry);

    const material_handle = if (Engine.instance.material_system.materials.isLiveHandle(geometry.material)) //
        geometry.material
    else
        Engine.instance.material_system.getDefaultMaterial();

    const material: *Material = try Engine.instance.material_system.materials.getColumnPtr(material_handle, .material);

    switch (material.material_type) {
        .world => {
            self.material_shader.setModel(data.model);
            try self.material_shader.applyMaterial(material_handle);
        },
        .ui => {
            self.ui_shader.setModel(data.model);
            try self.ui_shader.applyMaterial(material_handle);
        },
    }

    const buffer_data = self.geometries[geometry.internal_id.?];

    self.device_api.cmdBindVertexBuffers(
        command_buffer.handle,
        0,
        1,
        @ptrCast(&self.vertex_buffer.handle),
        @ptrCast(&[_]u64{buffer_data.vertex_buffer_offset}),
    );

    if (buffer_data.index_count > 0) {
        self.device_api.cmdBindIndexBuffer(
            command_buffer.handle,
            self.index_buffer.handle,
            buffer_data.index_buffer_offset,
            .uint32,
        );

        self.device_api.cmdDrawIndexed(command_buffer.handle, buffer_data.index_count, 1, 0, 0, 0);
    } else {
        self.device_api.cmdDraw(command_buffer.handle, buffer_data.vertex_count, 1, 0, 0);
    }
}

// utils
fn createInstance(allocator: Allocator, base_api: BaseAPI, app_name: [*:0]const u8) !vk.Instance {
    const required_instance_extensions = glfw.getRequiredInstanceExtensions() orelse return blk: {
        const err = glfw.mustGetError();
        std.log.err("Failed to get required instance extensions because {s}", .{err.description});
        break :blk error.GetRequiredInstanceExtensionsFailed;
    };

    // list of extensions to be requested when creating the instance
    // includes all required extensions and optional extensions that the driver supports
    var instance_extensions = try std.ArrayList([*:0]const u8).initCapacity(
        allocator,
        required_instance_extensions.len + optional_instance_extensions.len,
    );
    defer instance_extensions.deinit();

    try instance_extensions.appendSlice(required_instance_extensions);

    var count: u32 = undefined;
    _ = try base_api.enumerateInstanceExtensionProperties(null, &count, null);

    const existing_instance_extensions = try allocator.alloc(vk.ExtensionProperties, count);
    defer allocator.free(existing_instance_extensions);

    _ = try base_api.enumerateInstanceExtensionProperties(null, &count, existing_instance_extensions.ptr);

    for (optional_instance_extensions) |optional_inst_ext| {
        for (existing_instance_extensions) |existing_inst_ext| {
            const len = std.mem.indexOfScalar(u8, &existing_inst_ext.extension_name, 0) //
            orelse existing_inst_ext.extension_name.len;

            if (std.mem.eql(u8, existing_inst_ext.extension_name[0..len], std.mem.span(optional_inst_ext))) {
                try instance_extensions.append(optional_inst_ext);
                break;
            }
        }
    }

    const instance = try base_api.createInstance(&.{
        .flags = if (builtin.os.tag == .macos) .{ .enumerate_portability_bit_khr = true } else .{},
        .p_application_info = &.{
            .p_application_name = app_name,
            .application_version = vk.makeApiVersion(0, 0, 0, 1),
            .p_engine_name = "Zing engine",
            .engine_version = vk.makeApiVersion(0, 0, 0, 1),
            .api_version = vk.API_VERSION_1_3,
        },
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = null,
        .enabled_extension_count = @intCast(instance_extensions.items.len),
        .pp_enabled_extension_names = @ptrCast(instance_extensions.items),
    }, null);

    return instance;
}

fn createSurface(instance: vk.Instance, window: glfw.Window) !vk.SurfaceKHR {
    var surface: vk.SurfaceKHR = undefined;
    if (glfw.createWindowSurface(instance, window, null, &surface) != @intFromEnum(vk.Result.success)) {
        return error.SurfaceCreationFailed;
    }
    return surface;
}

fn pickPhysicalDevice(allocator: Allocator, instance: vk.Instance, instance_api: InstanceAPI, surface: vk.SurfaceKHR) !PhysicalDevice {
    var count: u32 = undefined;
    _ = try instance_api.enumeratePhysicalDevices(instance, &count, null);

    const physical_devices = try allocator.alloc(vk.PhysicalDevice, count);
    defer allocator.free(physical_devices);
    _ = try instance_api.enumeratePhysicalDevices(instance, &count, physical_devices.ptr);

    var max_score: u32 = 0;
    var best_physical_device: ?PhysicalDevice = null;

    for (physical_devices) |handle| {
        const physical_device = PhysicalDevice.init(allocator, handle, instance_api, surface) catch continue;

        if (physical_device.score > max_score) {
            max_score = physical_device.score;
            best_physical_device = physical_device;
        }
    }

    return best_physical_device orelse error.NoSuitablePhysicalDeviceFound;
}

fn createDevice(allocator: Allocator, physical_device: PhysicalDevice, instance_api: InstanceAPI) !vk.Device {
    const priority = [_]f32{1};

    var queue_count: u32 = 0;
    var queue_family_indices = [1]u32{std.math.maxInt(u32)} ** 4;
    var queue_create_infos: [4]vk.DeviceQueueCreateInfo = undefined;

    for ([_]u32{
        physical_device.graphics_family_index,
        physical_device.present_family_index,
        physical_device.compute_family_index,
        physical_device.transfer_family_index,
    }) |queue_family_index| {
        if (std.mem.indexOfScalar(u32, &queue_family_indices, queue_family_index) == null) {
            queue_family_indices[queue_count] = queue_family_index;
            queue_create_infos[queue_count] = .{
                .flags = .{},
                .queue_family_index = queue_family_index,
                .queue_count = 1,
                .p_queue_priorities = &priority,
            };
            queue_count += 1;
        }
    }

    var device_extensions = try std.ArrayList([*:0]const u8).initCapacity(
        allocator,
        required_device_extensions.len + optional_device_extensions.len,
    );
    defer device_extensions.deinit();

    // list of extensions to be requested when creating the device
    // includes all required extensions and optional extensions that the device supports
    try device_extensions.appendSlice(required_device_extensions[0..]);

    var count: u32 = undefined;
    _ = try instance_api.enumerateDeviceExtensionProperties(physical_device.handle, null, &count, null);

    const existing_extensions = try allocator.alloc(vk.ExtensionProperties, count);
    defer allocator.free(existing_extensions);

    _ = try instance_api.enumerateDeviceExtensionProperties(physical_device.handle, null, &count, existing_extensions.ptr);

    for (optional_device_extensions) |optional_ext| {
        for (existing_extensions) |existing_ext| {
            const len = std.mem.indexOfScalar(existing_ext.extension_name, 0) orelse existing_ext.extension_name.len;

            if (std.mem.eql(u8, existing_ext.extension_name[0..len], std.mem.span(optional_ext))) {
                try device_extensions.append(optional_ext);
                break;
            }
        }
    }

    const device = try instance_api.createDevice(physical_device.handle, &.{
        .flags = .{},
        .queue_create_info_count = queue_count,
        .p_queue_create_infos = &queue_create_infos,
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = null,
        .enabled_extension_count = @intCast(device_extensions.items.len),
        .pp_enabled_extension_names = @ptrCast(device_extensions.items),
        .p_enabled_features = null,
    }, null);

    return device;
}

fn initCommandBuffers(self: *Context) !void {
    errdefer self.deinitCommandBuffers();

    for (0..self.swapchain.images.len) |_| {
        try self.graphics_command_buffers.append(try CommandBuffer.init(self, self.graphics_command_pool, true));
    }
}

fn deinitCommandBuffers(self: *Context) void {
    for (self.graphics_command_buffers.items) |*buffer| {
        if (buffer.handle != .null_handle) {
            buffer.deinit();
        }
    }
    self.graphics_command_buffers.clearRetainingCapacity();
}

fn initFramebuffers(self: *Context) !void {
    errdefer self.deinitFramebuffers();

    for (self.swapchain.images.slice()) |image| {
        const attachments = [_]vk.ImageView{
            image.view,
            self.swapchain.depth_image.view,
        };

        try self.world_framebuffers.append(
            try self.device_api.createFramebuffer(self.device, &vk.FramebufferCreateInfo{
                .render_pass = self.world_render_pass.handle,
                .attachment_count = @intCast(attachments.len),
                .p_attachments = &attachments,
                .width = self.swapchain.extent.width,
                .height = self.swapchain.extent.height,
                .layers = 1,
            }, null),
        );
    }

    for (self.swapchain.images.slice()) |image| {
        const attachments = [_]vk.ImageView{
            image.view,
        };

        try self.framebuffers.append(
            try self.device_api.createFramebuffer(self.device, &vk.FramebufferCreateInfo{
                .render_pass = self.ui_render_pass.handle,
                .attachment_count = @intCast(attachments.len),
                .p_attachments = &attachments,
                .width = self.swapchain.extent.width,
                .height = self.swapchain.extent.height,
                .layers = 1,
            }, null),
        );
    }
}

fn deinitFramebuffers(self: *Context) void {
    for (self.framebuffers.items) |framebuffer| {
        if (framebuffer != .null_handle) {
            self.device_api.destroyFramebuffer(self.device, framebuffer, null);
        }
    }
    self.framebuffers.clearRetainingCapacity();

    for (self.world_framebuffers.items) |framebuffer| {
        if (framebuffer != .null_handle) {
            self.device_api.destroyFramebuffer(self.device, framebuffer, null);
        }
    }
    self.world_framebuffers.clearRetainingCapacity();
}

fn reinitSwapchainFramebuffersAndCmdBuffers(self: *Context) !void {
    if (self.desired_extent.width == 0 or self.desired_extent.height == 0) {
        // NOTE: don't bother recreating resources if width or height are 0
        return;
    }

    try self.device_api.deviceWaitIdle(self.device);

    try self.swapchain.reinit();
    errdefer self.swapchain.deinit();

    self.deinitFramebuffers();
    try self.initFramebuffers();
    errdefer self.deinitFramebuffers();

    self.deinitCommandBuffers();
    try self.initCommandBuffers();

    self.swapchain.extent_generation = self.desired_extent_generation;
}

fn uploadDataRegion(self: *Context, buffer: *Buffer, offset: vk.DeviceSize, size: vk.DeviceSize, data: []const u8) !void {
    var staging_buffer = try Buffer.init(
        self,
        buffer.total_size,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        .{ .bind_on_create = true },
    );
    defer staging_buffer.deinit();

    try staging_buffer.loadData(0, buffer.total_size, .{}, data);

    try staging_buffer.copyTo(buffer, self.graphics_command_pool, self.graphics_queue.handle, vk.BufferCopy{
        .src_offset = 0,
        .dst_offset = offset,
        .size = size,
    });
}

fn freeDataRegion(self: *Context, buffer: *Buffer, offset: vk.DeviceSize, size: vk.DeviceSize) void {
    _ = self; // autofix
    _ = buffer; // autofix
    _ = offset; // autofix
    _ = size; // autofix
}

const PhysicalDevice = struct {
    handle: vk.PhysicalDevice,
    features: vk.PhysicalDeviceFeatures,
    properties: vk.PhysicalDeviceProperties,
    memory_properties: vk.PhysicalDeviceMemoryProperties,
    depth_format: vk.Format,
    graphics_family_index: u32,
    present_family_index: u32,
    compute_family_index: u32,
    transfer_family_index: u32,
    supports_local_host_visible: bool,
    score: u32,

    // public
    pub fn init(allocator: Allocator, handle: vk.PhysicalDevice, instance_api: InstanceAPI, surface: vk.SurfaceKHR) !PhysicalDevice {
        var self: PhysicalDevice = undefined;
        self.handle = handle;
        self.score = 1;

        try self.initFeatureSupport(instance_api);
        try self.initMemorySupport(instance_api);
        try self.initDepthFormat(instance_api);
        try self.initSurfaceSupport(instance_api, surface);
        try self.initExtensionSupport(allocator, instance_api);
        try self.initQueueSupport(allocator, instance_api, surface);

        return self;
    }

    // utils
    fn initFeatureSupport(self: *PhysicalDevice, instance_api: InstanceAPI) !void {
        const features = instance_api.getPhysicalDeviceFeatures(self.handle);
        const properties = instance_api.getPhysicalDeviceProperties(self.handle);

        if (features.sampler_anisotropy != vk.TRUE) {
            return error.SamplerAnisotropyNotSupported;
        }

        if (features.geometry_shader == vk.TRUE) {
            self.score += 100;
        }

        if (features.tessellation_shader == vk.TRUE) {
            self.score += 50;
        }

        if (properties.device_type == .discrete_gpu) {
            self.score += 1000;
        }

        // TODO: declare a struct with required features and a map with pairs of optional features and weights
        //       to be used in here to prune the checking of this device or to increment it's score
        self.features = features;
        self.properties = properties;
    }

    fn initMemorySupport(self: *PhysicalDevice, instance_api: InstanceAPI) !void {
        self.supports_local_host_visible = false;

        const memory_properties = instance_api.getPhysicalDeviceMemoryProperties(self.handle);

        for (0..memory_properties.memory_type_count) |i| {
            const flags = memory_properties.memory_types[i].property_flags;

            if (flags.device_local_bit and flags.host_visible_bit) {
                self.supports_local_host_visible = true;
                self.score += 500;
                break;
            }
        }

        self.memory_properties = memory_properties;
    }

    fn initDepthFormat(self: *PhysicalDevice, instance_api: InstanceAPI) !void {
        for (desired_depth_formats) |desired_format| {
            const format_properties = instance_api.getPhysicalDeviceFormatProperties(self.handle, desired_format);

            if (format_properties.linear_tiling_features.depth_stencil_attachment_bit or format_properties.optimal_tiling_features.depth_stencil_attachment_bit) {
                self.depth_format = desired_format;
                return;
            }
        }

        return error.CouldNotFindDepthFormat;
    }

    fn initSurfaceSupport(self: *PhysicalDevice, instance_api: InstanceAPI, surface: vk.SurfaceKHR) !void {
        var format_count: u32 = undefined;
        _ = try instance_api.getPhysicalDeviceSurfaceFormatsKHR(self.handle, surface, &format_count, null);

        if (format_count == 0) {
            return error.NoDeviceSurfaceFormatsFound;
        }

        var present_mode_count: u32 = undefined;
        _ = try instance_api.getPhysicalDeviceSurfacePresentModesKHR(self.handle, surface, &present_mode_count, null);

        if (present_mode_count == 0) {
            return error.NoDevicePresentModesFound;
        }

        const surface_capabilities = try instance_api.getPhysicalDeviceSurfaceCapabilitiesKHR(self.handle, surface);

        if (surface_capabilities.min_image_count > 3 or //
            (surface_capabilities.max_image_count > 0 and surface_capabilities.max_image_count < 3))
        {
            return error.TripleBufferingNotSupported;
        }
    }

    fn initExtensionSupport(self: PhysicalDevice, allocator: Allocator, instance_api: InstanceAPI) !void {
        // TODO: make the optional extensions list into a map of pairs of extensions and weights
        //       which can then be used to increment the device score.
        var count: u32 = undefined;
        _ = try instance_api.enumerateDeviceExtensionProperties(self.handle, null, &count, null);

        const existing_extensions = try allocator.alloc(vk.ExtensionProperties, count);
        defer allocator.free(existing_extensions);
        _ = try instance_api.enumerateDeviceExtensionProperties(self.handle, null, &count, existing_extensions.ptr);

        for (required_device_extensions) |required_ext| {
            for (existing_extensions) |existing_ext| {
                const len = std.mem.indexOfScalar(u8, &existing_ext.extension_name, 0) orelse existing_ext.extension_name.len;

                if (std.mem.eql(u8, existing_ext.extension_name[0..len], std.mem.span(required_ext))) {
                    break;
                }
            } else {
                return error.ExtensionNotSupported;
            }
        }
    }

    fn initQueueSupport(self: *PhysicalDevice, allocator: Allocator, instance_api: InstanceAPI, surface: vk.SurfaceKHR) !void {
        var count: u32 = undefined;
        instance_api.getPhysicalDeviceQueueFamilyProperties(self.handle, &count, null);

        const queue_families = try allocator.alloc(vk.QueueFamilyProperties, count);
        defer allocator.free(queue_families);
        instance_api.getPhysicalDeviceQueueFamilyProperties(self.handle, &count, queue_families.ptr);

        var graphics_family_index: ?u32 = null;
        var present_family_index: ?u32 = null;
        var compute_family_index: ?u32 = null;
        var transfer_family_index: ?u32 = null;

        // prioritize a queue family that can do graphics and present to surface
        for (queue_families, 0..) |queue_family, i| {
            const queue_family_index: u32 = @intCast(i);

            if (queue_family.queue_flags.graphics_bit) {
                if (try instance_api.getPhysicalDeviceSurfaceSupportKHR(self.handle, queue_family_index, surface) == vk.TRUE) {
                    graphics_family_index = queue_family_index;
                    present_family_index = queue_family_index;
                }
            }
        }

        var min_transfer_score: u8 = std.math.maxInt(u8);
        for (queue_families, 0..) |queue_family, i| {
            const queue_family_index: u32 = @intCast(i);

            var transfer_score: u8 = 0;

            if (queue_family.queue_flags.graphics_bit) {
                if (graphics_family_index == null) {
                    graphics_family_index = queue_family_index;
                }
                if (graphics_family_index == queue_family_index) {
                    transfer_score += 1;
                }
            }

            if (present_family_index == null) {
                if (try instance_api.getPhysicalDeviceSurfaceSupportKHR(self.handle, queue_family_index, surface) == vk.TRUE) {
                    present_family_index = queue_family_index;
                }
            }

            if (compute_family_index == null and queue_family.queue_flags.compute_bit) {
                compute_family_index = queue_family_index;
                transfer_score += 1;
            }

            if (transfer_score < min_transfer_score and queue_family.queue_flags.transfer_bit) {
                transfer_family_index = queue_family_index;
                min_transfer_score = transfer_score;
            }
        }

        if (graphics_family_index == null or present_family_index == null or compute_family_index == null or transfer_family_index == null) {
            return error.QueueFamilyTypeNotSupported;
        }

        self.graphics_family_index = graphics_family_index.?;
        self.present_family_index = present_family_index.?;
        self.compute_family_index = compute_family_index.?;
        self.transfer_family_index = transfer_family_index.?;
    }
};

const Queue = struct {
    handle: vk.Queue,
    family_index: u32,

    fn init(context: *const Context, family_index: u32) Queue {
        return .{
            .handle = context.device_api.getDeviceQueue(context.device, family_index, 0),
            .family_index = family_index,
        };
    }
};
