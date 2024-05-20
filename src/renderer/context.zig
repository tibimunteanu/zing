const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("glfw");
const vk = @import("vk.zig");
const math = @import("zmath");

const Swapchain = @import("swapchain.zig");
const RenderPass = @import("renderpass.zig");
const CommandBuffer = @import("command_buffer.zig");

const config = @import("../config.zig");

const Allocator = std.mem.Allocator;
const Array = std.BoundedArray;

const Context = @This();

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

// NOTE: used to:
// - prep instance and device extensions
// - enumerate physical devices
// - passed to the swapchain to enumerate surface formats and presentation modes
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

framebuffers: Array(vk.Framebuffer, config.swapchain_max_images),
world_framebuffers: Array(vk.Framebuffer, config.swapchain_max_images),

world_render_pass: RenderPass,
ui_render_pass: RenderPass,

graphics_command_pool: vk.CommandPool,
graphics_command_buffers: Array(CommandBuffer, config.swapchain_max_images),

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

    // create command pool
    self.graphics_command_pool = try self.device_api.createCommandPool(
        self.device,
        &vk.CommandPoolCreateInfo{
            .queue_family_index = self.graphics_queue.family_index,
            .flags = .{ .reset_command_buffer_bit = true },
        },
        null,
    );
    errdefer self.device_api.destroyCommandPool(self.device, self.graphics_command_pool, null);

    // create command buffers
    try self.initCommandBuffers();
    errdefer self.deinitCommandBuffers();

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
    try self.initFramebuffers();
    errdefer self.deinitFramebuffers();

    self.frame_index = 0;
    self.delta_time = config.target_frame_seconds;

    std.log.info("Graphics device: {?s}", .{
        self.context.physical_device.properties.device_name,
    });
    std.log.info("GQ: {}, PQ: {}, CQ: {}, TQ: {}", .{
        self.context.graphics_queue.family_index,
        self.context.present_queue.family_index,
        self.context.compute_queue.family_index,
        self.context.transfer_queue.family_index,
    });
}

pub fn deinit(self: *Context) void {
    self.deinitFramebuffers();

    self.ui_render_pass.deinit();
    self.world_render_pass.deinit();

    self.deinitCommandBuffers();
    self.device_api.destroyCommandPool(self.device, self.graphics_command_pool, null);

    self.swapchain.deinit();

    self.device_api.destroyDevice(self.device, null);
    self.instance_api.destroySurfaceKHR(self.instance, self.surface, null);
    self.instance_api.destroyInstance(self.instance, null);
}

pub fn onResized(self: *Context, new_desired_extent: glfw.Window.Size) void {
    self.desired_extent = new_desired_extent;
    self.desired_extent_generation += 1;
}

pub fn getMemoryIndex(self: *const Context, type_bits: u32, flags: vk.MemoryPropertyFlags) !u32 {
    // TODO: should we always get fresh memory properties from the device?
    // const memory_properties = self.instance_api.getPhysicalDeviceMemoryProperties(self.physical_device.handle);

    for (0..self.physical_device.memory_properties.memory_type_count) |i| {
        if ((type_bits & std.math.shl(u32, 1, i) != 0) and self.physical_device.memory_properties.memory_types[i].property_flags.contains(flags)) {
            return @intCast(i);
        }
    }

    return error.GetMemoryIndexFailed;
}

pub fn allocate(self: *const Context, requirements: vk.MemoryRequirements, flags: vk.MemoryPropertyFlags) !vk.DeviceMemory {
    return try self.device_api.allocateMemory(self.device, &.{
        .allocation_size = requirements.size,
        .memory_type_index = try self.getMemoryIndex(requirements.memory_type_bits, flags),
    }, null);
}

pub fn beginFrame(self: *Context, delta_time: f32) !bool {
    self.delta_time = delta_time;

    if (self.desired_extent_generation != self.swapchain.extent_generation) {
        // NOTE: we could skip this and let the frame render and present will throw error.OutOfDateKHR
        // which is handled by endFrame() by recreating resources, but this way we avoid a best practices warning
        try self.reinitSwapchainFramebuffersAndCmdBuffers();
        return false;
    }

    const current_image = self.swapchain.getCurrentImage();
    const command_buffer = self.getCurrentCommandBuffer();

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

    return true;
}

pub fn endFrame(self: *Context) !void {
    const current_image = self.swapchain.getCurrentImage();
    var command_buffer = self.getCurrentCommandBuffer();

    // end the command buffer
    try command_buffer.end();

    // submit the command buffer
    try self.device_api.queueSubmit(
        self.graphics_queue.handle,
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

pub fn getCurrentCommandBuffer(self: *const Context) *const CommandBuffer {
    return &self.graphics_command_buffers.constSlice()[self.swapchain.image_index];
}

pub fn getCurrentFramebuffer(self: *const Context) vk.Framebuffer {
    return self.framebuffers.constSlice()[self.swapchain.image_index];
}

pub fn getCurrentWorldFramebuffer(self: *const Context) vk.Framebuffer {
    return self.world_framebuffers.constSlice()[self.swapchain.image_index];
}

// utils
fn createInstance(allocator: Allocator, base_api: BaseAPI, app_name: [*:0]const u8) !vk.Instance {
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

    const instance = try base_api.createInstance(&.{
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

    try self.graphics_command_buffers.resize(0);
    for (0..self.swapchain.images.len) |_| {
        try self.graphics_command_buffers.append(
            try CommandBuffer.init(self, self.graphics_command_pool, .{}),
        );
    }
}

fn deinitCommandBuffers(self: *Context) void {
    for (self.graphics_command_buffers.slice()) |*buffer| {
        if (buffer.handle != .null_handle) {
            buffer.deinit();
        }
    }
    self.graphics_command_buffers.len = 0;
}

fn initFramebuffers(self: *Context) !void {
    errdefer self.deinitFramebuffers();

    try self.world_framebuffers.resize(0);
    for (self.swapchain.images.slice()) |image| {
        const attachments = [_]vk.ImageView{
            image.view,
            self.swapchain.depth_image.view,
        };

        try self.world_framebuffers.append(
            try self.device_api.createFramebuffer(
                self.device,
                &vk.FramebufferCreateInfo{
                    .render_pass = self.world_render_pass.handle,
                    .attachment_count = @intCast(attachments.len),
                    .p_attachments = &attachments,
                    .width = self.swapchain.extent.width,
                    .height = self.swapchain.extent.height,
                    .layers = 1,
                },
                null,
            ),
        );
    }

    try self.framebuffers.resize(0);
    for (self.swapchain.images.slice()) |image| {
        const attachments = [_]vk.ImageView{
            image.view,
        };

        try self.framebuffers.append(
            try self.device_api.createFramebuffer(
                self.device,
                &vk.FramebufferCreateInfo{
                    .render_pass = self.ui_render_pass.handle,
                    .attachment_count = @intCast(attachments.len),
                    .p_attachments = &attachments,
                    .width = self.swapchain.extent.width,
                    .height = self.swapchain.extent.height,
                    .layers = 1,
                },
                null,
            ),
        );
    }
}

fn deinitFramebuffers(self: *Context) void {
    for (self.framebuffers.slice()) |framebuffer| {
        if (framebuffer != .null_handle) {
            self.device_api.destroyFramebuffer(self.device, framebuffer, null);
        }
    }
    self.framebuffers.len = 0;

    for (self.world_framebuffers.slice()) |framebuffer| {
        if (framebuffer != .null_handle) {
            self.device_api.destroyFramebuffer(self.device, framebuffer, null);
        }
    }
    self.world_framebuffers.len = 0;
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
