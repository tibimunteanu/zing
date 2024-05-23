const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("glfw");
const math = @import("zmath");
const vk = @import("vk.zig");
const config = @import("../config.zig");

const Buffer = @import("buffer.zig");
const CommandBuffer = @import("command_buffer.zig");
const RenderPass = @import("renderpass.zig");
const Swapchain = @import("swapchain.zig");

const Material = @import("material.zig");
const Geometry = @import("geometry.zig");

const Shader = @import("shader.zig");
const ShaderResource = @import("../resources/shader_resource.zig");

const resources_image = @import("../resources/image_resource.zig");
const resources_material = @import("../resources/material_resource.zig");

const Allocator = std.mem.Allocator;
const Array = std.BoundedArray;

const Renderer = @This();

const required_device_extensions = [_][*:0]const u8{
    vk.extension_info.khr_swapchain.name,
};

const optional_device_extensions = [_][*:0]const u8{
    // nothing here yet
};

const optional_instance_extensions = [_][*:0]const u8{
    // nothing here yet
} ++ if (builtin.os.tag == .macos)
    [_][*:0]const u8{vk.extension_info.khr_portability_enumeration.name}
else
    [_][*:0]const u8{};

const BaseAPI = vk.BaseWrapper(.{
    .createInstance = true,
    .enumerateInstanceExtensionProperties = true,
    .getInstanceProcAddr = true,
});

const InstanceAPI = vk.InstanceWrapper(.{
    .createDevice = true,
    .destroyInstance = true,
    .destroySurfaceKHR = true,
    .enumerateDeviceExtensionProperties = true,
    .enumeratePhysicalDevices = true,
    .getDeviceProcAddr = true,
    .getPhysicalDeviceFeatures = true,
    .getPhysicalDeviceFormatProperties = true,
    .getPhysicalDeviceMemoryProperties = true,
    .getPhysicalDeviceProperties = true,
    .getPhysicalDeviceQueueFamilyProperties = true,
    .getPhysicalDeviceSurfaceCapabilitiesKHR = true,
    .getPhysicalDeviceSurfaceFormatsKHR = true,
    .getPhysicalDeviceSurfacePresentModesKHR = true,
    .getPhysicalDeviceSurfaceSupportKHR = true,
});

const DeviceAPI = vk.DeviceWrapper(.{
    .acquireNextImageKHR = true,
    .allocateCommandBuffers = true,
    .allocateDescriptorSets = true,
    .allocateMemory = true,
    .beginCommandBuffer = true,
    .bindBufferMemory = true,
    .bindImageMemory = true,
    .cmdBeginRenderPass = true,
    .cmdBindDescriptorSets = true,
    .cmdBindIndexBuffer = true,
    .cmdBindPipeline = true,
    .cmdBindVertexBuffers = true,
    .cmdCopyBuffer = true,
    .cmdCopyBufferToImage = true,
    .cmdDraw = true,
    .cmdDrawIndexed = true,
    .cmdEndRenderPass = true,
    .cmdPipelineBarrier = true,
    .cmdPushConstants = true,
    .cmdSetScissor = true,
    .cmdSetViewport = true,
    .createBuffer = true,
    .createCommandPool = true,
    .createDescriptorPool = true,
    .createDescriptorSetLayout = true,
    .createFence = true,
    .createFramebuffer = true,
    .createGraphicsPipelines = true,
    .createImage = true,
    .createImageView = true,
    .createPipelineLayout = true,
    .createRenderPass = true,
    .createSampler = true,
    .createSemaphore = true,
    .createShaderModule = true,
    .createSwapchainKHR = true,
    .destroyBuffer = true,
    .destroyCommandPool = true,
    .destroyDescriptorPool = true,
    .destroyDescriptorSetLayout = true,
    .destroyDevice = true,
    .destroyFence = true,
    .destroyFramebuffer = true,
    .destroyImage = true,
    .destroyImageView = true,
    .destroyPipeline = true,
    .destroyPipelineLayout = true,
    .destroyRenderPass = true,
    .destroySampler = true,
    .destroySemaphore = true,
    .destroyShaderModule = true,
    .destroySwapchainKHR = true,
    .deviceWaitIdle = true,
    .endCommandBuffer = true,
    .freeCommandBuffers = true,
    .freeDescriptorSets = true,
    .freeMemory = true,
    .getBufferMemoryRequirements = true,
    .getDeviceQueue = true,
    .getImageMemoryRequirements = true,
    .getSwapchainImagesKHR = true,
    .mapMemory = true,
    .queuePresentKHR = true,
    .queueSubmit = true,
    .queueWaitIdle = true,
    .resetCommandBuffer = true,
    .resetFences = true,
    .unmapMemory = true,
    .updateDescriptorSets = true,
    .waitForFences = true,
});

const desired_depth_formats: []const vk.Format = &[_]vk.Format{
    .d32_sfloat,
    .d32_sfloat_s8_uint,
    .d24_unorm_s8_uint,
};

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

pub const GeometryRenderData = struct {
    model: math.Mat,
    geometry: Geometry.Handle,
};

pub const RenderPacket = struct {
    delta_time: f32,
    geometries: []const GeometryRenderData,
    ui_geometries: []const GeometryRenderData,
};

pub var allocator: Allocator = undefined;

pub var base_api: BaseAPI = undefined;
pub var instance_api: InstanceAPI = undefined;
pub var device_api: DeviceAPI = undefined;

pub var instance: vk.Instance = undefined;
pub var surface: vk.SurfaceKHR = undefined;
pub var physical_device: PhysicalDevice = undefined;
pub var device: vk.Device = undefined;

pub var graphics_queue: Queue = undefined;
pub var present_queue: Queue = undefined;
pub var compute_queue: Queue = undefined;
pub var transfer_queue: Queue = undefined;

pub var swapchain: Swapchain = undefined;

pub var framebuffers: Array(vk.Framebuffer, config.swapchain_max_images) = undefined;
pub var world_framebuffers: Array(vk.Framebuffer, config.swapchain_max_images) = undefined;

pub var graphics_command_pool: vk.CommandPool = undefined;
pub var graphics_command_buffers: Array(CommandBuffer, config.swapchain_max_images) = undefined;

pub var world_render_pass: RenderPass = undefined;
pub var ui_render_pass: RenderPass = undefined;

pub var phong_shader: Shader = undefined;
pub var ui_shader: Shader = undefined;

pub var vertex_buffer: Buffer = undefined;
pub var index_buffer: Buffer = undefined;

pub var geometries: [geometry_max_count]Geometry.Data = undefined;

pub var projection: math.Mat = undefined;
pub var view: math.Mat = undefined;
pub var ui_projection: math.Mat = undefined;
pub var ui_view: math.Mat = undefined;
pub var fov: f32 = undefined;
pub var near_clip: f32 = undefined;
pub var far_clip: f32 = undefined;

pub var desired_extent: glfw.Window.Size = undefined;
pub var desired_extent_generation: u32 = undefined;
pub var frame_index: u64 = undefined;
pub var delta_time: f32 = undefined;

pub fn init(ally: Allocator, window: glfw.Window) !void {
    allocator = ally;

    desired_extent = window.getFramebufferSize();
    desired_extent_generation = 0;

    // load base api
    const base_loader = @as(vk.PfnGetInstanceProcAddr, @ptrCast(&glfw.getInstanceProcAddress));
    base_api = try BaseAPI.load(base_loader);

    // create instance and load instance api
    instance = try createInstance("Zing engine");

    const instance_loader = base_api.dispatch.vkGetInstanceProcAddr;
    instance_api = try InstanceAPI.load(instance, instance_loader);
    errdefer instance_api.destroyInstance(instance, null);

    // create surface
    surface = try createSurface(window);
    errdefer instance_api.destroySurfaceKHR(instance, surface, null);

    // pick a suitable physical device
    physical_device = try pickPhysicalDevice();

    std.log.info("Graphics device: {?s}", .{physical_device.properties.device_name});

    // create logical device and load device api
    device = try createDevice();

    const device_loader = instance_api.dispatch.vkGetDeviceProcAddr;
    device_api = try DeviceAPI.load(device, device_loader);
    errdefer device_api.destroyDevice(device, null);

    // get queues
    graphics_queue = Queue.init(physical_device.graphics_family_index);
    present_queue = Queue.init(physical_device.present_family_index);
    compute_queue = Queue.init(physical_device.compute_family_index);
    transfer_queue = Queue.init(physical_device.transfer_family_index);

    // create swapchain
    swapchain = try Swapchain.init(allocator, .{});
    errdefer swapchain.deinit();

    // create renderpasses
    world_render_pass = try RenderPass.init(
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
    errdefer world_render_pass.deinit();

    ui_render_pass = try RenderPass.init(
        .{
            .has_prev = true,
            .has_next = false,
        },
    );
    errdefer ui_render_pass.deinit();

    // create framebuffers
    try initFramebuffers();
    errdefer deinitFramebuffers();

    // create command pool
    graphics_command_pool = try device_api.createCommandPool(
        device,
        &vk.CommandPoolCreateInfo{
            .queue_family_index = graphics_queue.family_index,
            .flags = .{ .reset_command_buffer_bit = true },
        },
        null,
    );
    errdefer device_api.destroyCommandPool(device, graphics_command_pool, null);

    // create command buffers
    try initCommandBuffers();
    errdefer deinitCommandBuffers();

    // create shaders
    var phong_shader_resource = try ShaderResource.init(allocator, "phong");
    defer phong_shader_resource.deinit();

    phong_shader = try Shader.init(allocator, phong_shader_resource.config.value);
    errdefer phong_shader.deinit();

    var ui_shader_resource = try ShaderResource.init(allocator, "ui");
    defer ui_shader_resource.deinit();

    ui_shader = try Shader.init(allocator, ui_shader_resource.config.value);
    errdefer ui_shader.deinit();

    // create buffers
    vertex_buffer = try Buffer.init(
        allocator,
        100 * 1024 * 1024,
        .{ .vertex_buffer_bit = true, .transfer_dst_bit = true, .transfer_src_bit = true },
        .{ .device_local_bit = true },
        .{ .managed = true, .bind_on_create = true },
    );
    errdefer vertex_buffer.deinit();

    index_buffer = try Buffer.init(
        allocator,
        10 * 1024 * 1024,
        .{ .index_buffer_bit = true, .transfer_dst_bit = true, .transfer_src_bit = true },
        .{ .device_local_bit = true },
        .{ .managed = true, .bind_on_create = true },
    );
    errdefer index_buffer.deinit();

    // reset geometry storage
    for (&geometries) |*geometry| {
        geometry.*.id = null;
        geometry.*.generation = null;
    }

    view = math.inverse(math.translation(0.0, 0.0, -30.0));
    ui_view = math.inverse(math.identity());

    fov = std.math.degreesToRadians(45.0);
    near_clip = 0.1;
    far_clip = 1000.0;

    window.setFramebufferSizeCallback(framebufferSizeCallback);
    setProjection(window.getFramebufferSize());

    frame_index = 0;
    delta_time = config.target_frame_seconds;
}

pub fn deinit() void {
    device_api.deviceWaitIdle(device) catch {};

    deinitCommandBuffers();
    device_api.destroyCommandPool(device, graphics_command_pool, null);

    deinitFramebuffers();

    ui_render_pass.deinit();
    world_render_pass.deinit();

    vertex_buffer.deinit();
    index_buffer.deinit();

    ui_shader.deinit();
    phong_shader.deinit();

    swapchain.deinit();

    device_api.destroyDevice(device, null);
    instance_api.destroySurfaceKHR(instance, surface, null);
    instance_api.destroyInstance(instance, null);
}

pub fn getMemoryIndex(type_bits: u32, flags: vk.MemoryPropertyFlags) !u32 {
    // TODO: should we always get fresh memory properties from the device?
    // const memory_properties = self.instance_api.getPhysicalDeviceMemoryProperties(self.physical_device.handle);

    for (0..physical_device.memory_properties.memory_type_count) |i| {
        if ((type_bits & std.math.shl(u32, 1, i) != 0) and physical_device.memory_properties.memory_types[i].property_flags.contains(flags)) {
            return @intCast(i);
        }
    }

    return error.GetMemoryIndexFailed;
}

pub fn allocate(requirements: vk.MemoryRequirements, flags: vk.MemoryPropertyFlags) !vk.DeviceMemory {
    return try device_api.allocateMemory(device, &.{
        .allocation_size = requirements.size,
        .memory_type_index = try getMemoryIndex(requirements.memory_type_bits, flags),
    }, null);
}

pub fn onResized(new_desired_extent: glfw.Window.Size) void {
    setProjection(new_desired_extent);

    desired_extent = new_desired_extent;
    desired_extent_generation += 1;
}

pub fn waitIdle() !void {
    try swapchain.waitForAllFences();
}

pub fn getCurrentCommandBuffer() *const CommandBuffer {
    return &graphics_command_buffers.constSlice()[swapchain.image_index];
}

pub fn getCurrentFramebuffer() vk.Framebuffer {
    return framebuffers.constSlice()[swapchain.image_index];
}

pub fn getCurrentWorldFramebuffer() vk.Framebuffer {
    return world_framebuffers.constSlice()[swapchain.image_index];
}

pub fn beginFrame(dt: f32) !bool {
    delta_time = dt;

    if (desired_extent_generation != swapchain.extent_generation) {
        // NOTE: we could skip this and let the frame render and present will throw error.OutOfDateKHR
        // which is handled by endFrame() by recreating resources, but this way we avoid a best practices warning
        try reinitSwapchainFramebuffersAndCmdBuffers();
        return false;
    }

    const current_image = swapchain.getCurrentImage();
    const command_buffer = getCurrentCommandBuffer();

    // make sure the current frame has finished rendering.
    // NOTE: the fences start signaled so the first frame can get past them.
    try current_image.waitForFrameFence(.{ .reset = true });

    try command_buffer.begin(.{});

    const viewport: vk.Viewport = .{
        .x = 0.0,
        .y = @floatFromInt(swapchain.extent.height),
        .width = @floatFromInt(swapchain.extent.width),
        .height = @floatFromInt(-@as(i32, @intCast(swapchain.extent.height))),
        .min_depth = 0.0,
        .max_depth = 1.0,
    };

    const scissor: vk.Rect2D = .{
        .offset = .{ .x = 0, .y = 0 },
        .extent = swapchain.extent,
    };

    device_api.cmdSetViewport(command_buffer.handle, 0, 1, @ptrCast(&viewport));
    device_api.cmdSetScissor(command_buffer.handle, 0, 1, @ptrCast(&scissor));

    return true;
}

pub fn endFrame() !void {
    const current_image = swapchain.getCurrentImage();
    var command_buffer = getCurrentCommandBuffer();

    // end the command buffer
    try command_buffer.end();

    // submit the command buffer
    try device_api.queueSubmit(
        graphics_queue.handle,
        1,
        @ptrCast(&vk.SubmitInfo{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&current_image.image_acquired_semaphore),
            .p_wait_dst_stage_mask = @ptrCast(&vk.PipelineStageFlags{ .color_attachment_output_bit = true }),
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&command_buffer.handle),
            .signal_semaphore_count = 1,
            .p_signal_semaphores = @ptrCast(&current_image.render_finished_semaphore),
        }),
        current_image.frame_fence,
    );

    const state = swapchain.present() catch |err| switch (err) {
        error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
        else => |narrow| return narrow,
    };

    // NOTE: we should always recreate resources when error.OutOfDateKHR, but here,
    // we decided to also always recreate resources when the result is .suboptimal.
    // this should be configurable, so that you can choose if you only want to recreate on error.
    if (state == .suboptimal) {
        std.log.info("endFrame() Present was suboptimal. Recreating resources.", .{});
        try reinitSwapchainFramebuffersAndCmdBuffers();
    }
}

pub fn drawFrame(packet: RenderPacket) !void {
    if (try beginFrame(packet.delta_time)) {
        try beginRenderPass(.world);

        phong_shader.bindGlobal();

        try phong_shader.setUniform("projection", projection);
        try phong_shader.setUniform("view", view);

        try phong_shader.applyGlobal();

        for (packet.geometries) |geometry| {
            try drawGeometry(geometry);
        }

        try endRenderPass(.world);

        try beginRenderPass(.ui);

        ui_shader.bindGlobal();

        try ui_shader.setUniform("projection", ui_projection);
        try ui_shader.setUniform("view", ui_view);

        try ui_shader.applyGlobal();

        for (packet.ui_geometries) |ui_geometry| {
            try drawGeometry(ui_geometry);
        }
        try endRenderPass(.ui);

        try endFrame();

        frame_index += 1;
    }
}

pub fn drawGeometry(data: GeometryRenderData) !void {
    const command_buffer = getCurrentCommandBuffer();

    const geometry = try Geometry.get(data.geometry);
    const material = geometry.material.getOrDefault();

    switch (material.material_type) {
        .world => {
            try phong_shader.setUniform("model", data.model);

            try phong_shader.bindInstance(material.instance_handle.?);

            try phong_shader.setUniform("diffuse_color", material.diffuse_color);
            try phong_shader.setUniform("diffuse_texture", material.diffuse_map.texture);

            try phong_shader.applyInstance();
        },
        .ui => {
            try ui_shader.setUniform("model", data.model);

            try ui_shader.bindInstance(material.instance_handle.?);

            try ui_shader.setUniform("diffuse_color", material.diffuse_color);
            try ui_shader.setUniform("diffuse_texture", material.diffuse_map.texture);

            try ui_shader.applyInstance();
        },
    }

    const buffer_data = geometries[geometry.internal_id.?];

    device_api.cmdBindVertexBuffers(
        command_buffer.handle,
        0,
        1,
        @ptrCast(&vertex_buffer.handle),
        @ptrCast(&[_]u64{buffer_data.vertex_buffer_offset}),
    );

    if (buffer_data.index_count > 0) {
        device_api.cmdBindIndexBuffer(
            command_buffer.handle,
            index_buffer.handle,
            buffer_data.index_buffer_offset,
            .uint32,
        );

        device_api.cmdDrawIndexed(command_buffer.handle, buffer_data.index_count, 1, 0, 0, 0);
    } else {
        device_api.cmdDraw(command_buffer.handle, buffer_data.vertex_count, 1, 0, 0);
    }
}

pub fn beginRenderPass(render_pass_type: RenderPass.Type) !void {
    const command_buffer = getCurrentCommandBuffer();

    switch (render_pass_type) {
        .world => {
            world_render_pass.begin(command_buffer, getCurrentWorldFramebuffer());
            phong_shader.bind();
        },
        .ui => {
            ui_render_pass.begin(command_buffer, getCurrentFramebuffer());
            ui_shader.bind();
        },
    }
}

pub fn endRenderPass(render_pass_type: RenderPass.Type) !void {
    const command_buffer = getCurrentCommandBuffer();

    switch (render_pass_type) {
        .world => world_render_pass.end(command_buffer),
        .ui => ui_render_pass.end(command_buffer),
    }
}

// utils
fn createInstance(app_name: [*:0]const u8) !vk.Instance {
    const required_instance_extensions = glfw.getRequiredInstanceExtensions() orelse return error.GetRequiredInstanceExtensionsFailed;

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

    return try base_api.createInstance(&.{
        .flags = if (builtin.os.tag == .macos) .{ .enumerate_portability_bit_khr = true } else .{},
        .p_application_info = &.{
            .p_application_name = app_name,
            .application_version = vk.makeApiVersion(0, 0, 0, 1),
            .p_engine_name = "Zing engine",
            .engine_version = vk.makeApiVersion(0, 0, 0, 1),
            .api_version = vk.API_VERSION_1_1,
        },
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = null,
        .enabled_extension_count = @intCast(instance_extensions.items.len),
        .pp_enabled_extension_names = @ptrCast(instance_extensions.items),
    }, null);
}

fn createSurface(window: glfw.Window) !vk.SurfaceKHR {
    var window_surface: vk.SurfaceKHR = undefined;
    if (glfw.createWindowSurface(instance, window, null, &window_surface) != @intFromEnum(vk.Result.success)) {
        return error.SurfaceCreationFailed;
    }
    return window_surface;
}

fn pickPhysicalDevice() !PhysicalDevice {
    var count: u32 = undefined;
    _ = try instance_api.enumeratePhysicalDevices(instance, &count, null);

    const physical_devices = try allocator.alloc(vk.PhysicalDevice, count);
    defer allocator.free(physical_devices);
    _ = try instance_api.enumeratePhysicalDevices(instance, &count, physical_devices.ptr);

    var max_score: u32 = 0;
    var best_physical_device: ?PhysicalDevice = null;

    for (physical_devices) |handle| {
        const candidate = PhysicalDevice.init(handle) catch continue;

        if (candidate.score > max_score) {
            max_score = candidate.score;
            best_physical_device = candidate;
        }
    }

    return best_physical_device orelse error.NoSuitablePhysicalDeviceFound;
}

fn createDevice() !vk.Device {
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
                .p_queue_priorities = &[_]f32{1},
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

    return try instance_api.createDevice(physical_device.handle, &.{
        .flags = .{},
        .queue_create_info_count = queue_count,
        .p_queue_create_infos = &queue_create_infos,
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = null,
        .enabled_extension_count = @intCast(device_extensions.items.len),
        .pp_enabled_extension_names = @ptrCast(device_extensions.items),
        .p_enabled_features = null,
    }, null);
}

fn initFramebuffers() !void {
    errdefer deinitFramebuffers();

    try world_framebuffers.resize(0);
    for (swapchain.images.slice()) |image| {
        const attachments = [_]vk.ImageView{
            image.view,
            swapchain.depth_image.view,
        };

        try world_framebuffers.append(
            try device_api.createFramebuffer(
                device,
                &vk.FramebufferCreateInfo{
                    .render_pass = world_render_pass.handle,
                    .attachment_count = @intCast(attachments.len),
                    .p_attachments = &attachments,
                    .width = swapchain.extent.width,
                    .height = swapchain.extent.height,
                    .layers = 1,
                },
                null,
            ),
        );
    }

    try framebuffers.resize(0);
    for (swapchain.images.slice()) |image| {
        const attachments = [_]vk.ImageView{
            image.view,
        };

        try framebuffers.append(
            try device_api.createFramebuffer(
                device,
                &vk.FramebufferCreateInfo{
                    .render_pass = ui_render_pass.handle,
                    .attachment_count = @intCast(attachments.len),
                    .p_attachments = &attachments,
                    .width = swapchain.extent.width,
                    .height = swapchain.extent.height,
                    .layers = 1,
                },
                null,
            ),
        );
    }
}

fn deinitFramebuffers() void {
    for (framebuffers.slice()) |framebuffer| {
        if (framebuffer != .null_handle) {
            device_api.destroyFramebuffer(device, framebuffer, null);
        }
    }
    framebuffers.len = 0;

    for (world_framebuffers.slice()) |framebuffer| {
        if (framebuffer != .null_handle) {
            device_api.destroyFramebuffer(device, framebuffer, null);
        }
    }
    world_framebuffers.len = 0;
}

fn initCommandBuffers() !void {
    errdefer deinitCommandBuffers();

    try graphics_command_buffers.resize(0);
    for (0..swapchain.images.len) |_| {
        try graphics_command_buffers.append(
            try CommandBuffer.init(graphics_command_pool, .{}),
        );
    }
}

fn deinitCommandBuffers() void {
    for (graphics_command_buffers.slice()) |*buffer| {
        if (buffer.handle != .null_handle) {
            buffer.deinit();
        }
    }
    graphics_command_buffers.len = 0;
}

fn reinitSwapchainFramebuffersAndCmdBuffers() !void {
    if (desired_extent.width == 0 or desired_extent.height == 0) {
        // NOTE: don't bother recreating resources if width or height are 0
        return;
    }

    try device_api.deviceWaitIdle(device);

    try swapchain.reinit();
    errdefer swapchain.deinit();

    deinitFramebuffers();
    try initFramebuffers();
    errdefer deinitFramebuffers();

    deinitCommandBuffers();
    try initCommandBuffers();

    swapchain.extent_generation = desired_extent_generation;
}

fn setProjection(size: glfw.Window.Size) void {
    const width: f32 = @floatFromInt(size.width);
    const height: f32 = @floatFromInt(size.height);

    projection = math.perspectiveFovLh(fov, width / height, near_clip, far_clip);
    ui_projection = math.orthographicOffCenterLh(0, width, height, 0, -1.0, 1.0);
}

fn framebufferSizeCallback(_: glfw.Window, width: u32, height: u32) void {
    onResized(glfw.Window.Size{ .width = width, .height = height });
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
    pub fn init(handle: vk.PhysicalDevice) !PhysicalDevice {
        var self: PhysicalDevice = undefined;
        self.handle = handle;
        self.score = 1;

        try self.initFeatureSupport();
        try self.initMemorySupport();
        try self.initDepthFormat();
        try self.initSurfaceSupport();
        try self.initExtensionSupport();
        try self.initQueueSupport();

        return self;
    }

    // utils
    fn initFeatureSupport(self: *PhysicalDevice) !void {
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

    fn initMemorySupport(self: *PhysicalDevice) !void {
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

    fn initDepthFormat(self: *PhysicalDevice) !void {
        for (desired_depth_formats) |desired_format| {
            const format_properties = instance_api.getPhysicalDeviceFormatProperties(self.handle, desired_format);

            if (format_properties.linear_tiling_features.depth_stencil_attachment_bit or format_properties.optimal_tiling_features.depth_stencil_attachment_bit) {
                self.depth_format = desired_format;
                return;
            }
        }

        return error.CouldNotFindDepthFormat;
    }

    fn initSurfaceSupport(self: *PhysicalDevice) !void {
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

    fn initExtensionSupport(self: PhysicalDevice) !void {
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

    fn initQueueSupport(self: *PhysicalDevice) !void {
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

    fn init(family_index: u32) Queue {
        return .{
            .handle = device_api.getDeviceQueue(device, family_index, 0),
            .family_index = family_index,
        };
    }
};
