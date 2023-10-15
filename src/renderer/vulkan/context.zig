const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("mach-glfw");
const vk = @import("vk.zig");
const Swapchain = @import("swapchain.zig").Swapchain;
const RenderPass = @import("renderpass.zig").RenderPass;
const CommandBuffer = @import("command_buffer.zig").CommandBuffer;
const Framebuffer = @import("framebuffer.zig").Framebuffer;
const Allocator = std.mem.Allocator;

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
    .destroyImageView = true,
    .destroySemaphore = true,
    .destroyFence = true,
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
    .cmdDraw = true,
    .cmdSetViewport = true,
    .cmdSetScissor = true,
    .cmdBindVertexBuffers = true,
    .cmdCopyBuffer = true,
});

const desired_depth_formats: []const vk.Format = &[_]vk.Format{
    .d32_sfloat,
    .d32_sfloat_s8_uint,
    .d24_unorm_s8_uint,
};

pub const Context = struct {
    const Self = @This();

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
    main_render_pass: RenderPass,
    graphics_command_pool: vk.CommandPool,
    graphics_command_buffers: std.ArrayList(CommandBuffer),

    desired_extent: glfw.Window.Size,
    desired_extent_generation: u32,

    pub fn init(allocator: Allocator, app_name: [*:0]const u8, window: glfw.Window) !Self {
        var self: Self = undefined;

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
        self.graphics_queue = Queue.init(self.device, self.device_api, self.physical_device.graphics_family_index);
        self.present_queue = Queue.init(self.device, self.device_api, self.physical_device.present_family_index);
        self.compute_queue = Queue.init(self.device, self.device_api, self.physical_device.compute_family_index);
        self.transfer_queue = Queue.init(self.device, self.device_api, self.physical_device.transfer_family_index);

        self.swapchain = try Swapchain.init(allocator, &self, .{});

        self.main_render_pass = try RenderPass.init(
            &self,
            .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = self.swapchain.extent,
            },
            .{
                .color = [_]f32{ 0.0, 0.0, 0.2, 1.0 },
                .depth = 1.0,
                .stencil = 0,
            },
        );

        // swapchain framebuffers
        self.swapchain.framebuffers = try std.ArrayList(Framebuffer).initCapacity(allocator, self.swapchain.images.len);
        try self.regenerateFramebuffers(&self.main_render_pass);

        self.graphics_command_pool = try self.device_api.createCommandPool(self.device, &vk.CommandPoolCreateInfo{
            .queue_family_index = self.graphics_queue.family_index,
            .flags = .{ .reset_command_buffer_bit = true },
        }, null);
        errdefer self.device_api.destroyCommandPool(self.device, self.graphics_command_pool, null);

        try self.initCommandBuffers(.{ .allocate = true, .allocator = allocator });
        errdefer self.deinitCommandbuffers(.{ .deallocate = true });

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.device_api.deviceWaitIdle(self.device) catch {};

        self.deinitCommandbuffers(.{ .deallocate = true });
        self.device_api.destroyCommandPool(self.device, self.graphics_command_pool, null);
        for (self.swapchain.framebuffers.items) |*framebuffer| {
            framebuffer.deinit(self);
        }
        self.swapchain.framebuffers.deinit();
        self.main_render_pass.deinit(self);
        self.swapchain.deinit(.{});
        self.device_api.destroyDevice(self.device, null);
        self.instance_api.destroySurfaceKHR(self.instance, self.surface, null);
        self.instance_api.destroyInstance(self.instance, null);
    }

    pub fn onResized(self: *Self, new_desired_extent: glfw.Window.Size) void {
        self.desired_extent = new_desired_extent;
        self.desired_extent_generation += 1;

        std.log.info("Context onResized with new desired extent {} x {}", .{
            new_desired_extent.width,
            new_desired_extent.height,
        });
    }

    pub fn getMemoryIndex(self: Self, type_bits: u32, flags: vk.MemoryPropertyFlags) !u32 {
        const memory_properties = self.instance_api.getPhysicalDeviceMemoryProperties(self.physical_device.handle);

        for (0..memory_properties.memory_type_count) |i| {
            if ((type_bits & std.math.shl(u32, 1, i) != 0) and memory_properties.memory_types[i].property_flags.contains(flags)) {
                return @as(u32, @intCast(i));
            }
        }

        return error.getMemoryIndexFailed;
    }

    fn createInstance(allocator: Allocator, base_api: BaseAPI, app_name: [*:0]const u8) !vk.Instance {
        const required_instance_extensions = glfw.getRequiredInstanceExtensions() orelse return blk: {
            const err = glfw.mustGetError();
            std.log.err("Failed to get required instance extensions because {s}", .{err.description});
            break :blk error.getRequiredInstanceExtensionsFailed;
        };

        // list of extensions to be requested when creating the instance
        // includes all required extensions and optional extensions that the driver supports
        var instance_extensions = try std.ArrayList([*:0]const u8).initCapacity(
            allocator,
            required_instance_extensions.len + 1,
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
                const len = std.mem.indexOfScalar(u8, &existing_inst_ext.extension_name, 0) orelse existing_inst_ext.extension_name.len;

                if (std.mem.eql(u8, existing_inst_ext.extension_name[0..len], std.mem.span(optional_inst_ext))) {
                    try instance_extensions.append(@ptrCast(optional_inst_ext));
                    break;
                }
            }
        }

        const instance = try base_api.createInstance(&.{
            .flags = if (builtin.os.tag == .macos) .{
                .enumerate_portability_bit_khr = true,
            } else .{},
            .p_application_info = &.{
                .p_application_name = app_name,
                .application_version = vk.makeApiVersion(0, 0, 0, 1),
                .p_engine_name = "Zing engine",
                .engine_version = vk.makeApiVersion(0, 0, 0, 1),
                .api_version = vk.API_VERSION_1_3,
            },
            .enabled_layer_count = 0,
            .pp_enabled_layer_names = undefined,
            .enabled_extension_count = @intCast(instance_extensions.items.len),
            .pp_enabled_extension_names = @ptrCast(instance_extensions.items),
        }, null);

        return instance;
    }

    fn createSurface(instance: vk.Instance, window: glfw.Window) !vk.SurfaceKHR {
        var surface: vk.SurfaceKHR = undefined;
        if (glfw.createWindowSurface(instance, window, null, &surface) != @intFromEnum(vk.Result.success)) {
            return error.surfaceCreationFailed;
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
        var maybe_physical_device: ?PhysicalDevice = null;

        for (physical_devices) |handle| {
            const physical_device = try PhysicalDevice.init(allocator, handle, instance_api, surface);

            if (physical_device.score > max_score) {
                max_score = physical_device.score;
                maybe_physical_device = physical_device;
            }
        }

        return maybe_physical_device orelse error.noSuitablePhysicalDeviceFound;
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

        var device_extensions = try std.ArrayList([*:0]const u8).initCapacity(allocator, required_device_extensions.len);
        defer device_extensions.deinit();

        // list of extensions to be requested when creating the device
        // includes all required extensions and optional extensions that the device supports
        try device_extensions.appendSlice(required_device_extensions[0..]);

        var count: u32 = undefined;
        _ = try instance_api.enumerateDeviceExtensionProperties(physical_device.handle, null, &count, null);

        const existing_extensions = try allocator.alloc(vk.ExtensionProperties, count);
        defer allocator.free(existing_extensions);

        _ = try instance_api.enumerateDeviceExtensionProperties(
            physical_device.handle,
            null,
            &count,
            existing_extensions.ptr,
        );

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
            .pp_enabled_layer_names = undefined,
            .enabled_extension_count = @intCast(device_extensions.items.len),
            .pp_enabled_extension_names = @ptrCast(device_extensions.items),
            .p_enabled_features = null,
        }, null);

        return device;
    }

    fn initCommandBuffers(self: *Self, options: struct { allocate: bool = false, allocator: ?Allocator }) !void {
        if (options.allocate) {
            self.graphics_command_buffers = try std.ArrayList(CommandBuffer).initCapacity(options.allocator.?, self.swapchain.images.len);
            self.graphics_command_buffers.items.len = self.swapchain.images.len;

            for (self.graphics_command_buffers.items) |*buffer| {
                buffer.handle = .null_handle;
                buffer.state = .not_allocated;
            }
        }
        errdefer if (options.allocate) self.graphics_command_buffers.deinit();

        for (self.graphics_command_buffers.items) |*buffer| {
            if (buffer.handle != .null_handle) {
                buffer.deinit(self, self.graphics_command_pool);
            }

            buffer.* = try CommandBuffer.init(self, self.graphics_command_pool, true);
        }
    }

    fn deinitCommandbuffers(self: *Self, options: struct { deallocate: bool = false }) void {
        for (self.graphics_command_buffers.items) |*buffer| {
            buffer.deinit(self, self.graphics_command_pool);
        }

        if (options.deallocate) {
            self.graphics_command_buffers.deinit();
        }
    }

    fn regenerateFramebuffers(self: *Self, render_pass: *const RenderPass) !void {
        self.swapchain.framebuffers.items.len = self.swapchain.images.len;

        for (self.swapchain.images, 0..) |image, i| {
            const attachments = [_]vk.ImageView{
                image.view,
                self.swapchain.depth_image.view.?,
            };

            self.swapchain.framebuffers.items[i] = try Framebuffer.init(
                self,
                self.allocator,
                render_pass,
                self.swapchain.extent.width,
                self.swapchain.extent.height,
                &attachments,
            );
        }
    }
};

pub const PhysicalDevice = struct {
    const Self = @This();

    handle: vk.PhysicalDevice,
    features: vk.PhysicalDeviceFeatures,
    properties: vk.PhysicalDeviceProperties,
    memory_properties: vk.PhysicalDeviceMemoryProperties,
    depth_format: vk.Format,
    graphics_family_index: u32,
    present_family_index: u32,
    compute_family_index: u32,
    transfer_family_index: u32,
    score: u32,

    pub fn init(allocator: Allocator, handle: vk.PhysicalDevice, instance_api: InstanceAPI, surface: vk.SurfaceKHR) !Self {
        var self: Self = undefined;
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

    fn initFeatureSupport(self: *Self, instance_api: InstanceAPI) !void {
        const features = instance_api.getPhysicalDeviceFeatures(self.handle);
        const properties = instance_api.getPhysicalDeviceProperties(self.handle);

        if (features.sampler_anisotropy != vk.TRUE) {
            return error.samplerAnisotropyNotSupported;
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

    fn initMemorySupport(self: *Self, instance_api: InstanceAPI) !void {
        const memory_properties = instance_api.getPhysicalDeviceMemoryProperties(self.handle);

        var supports_device_local_host_visible: bool = false;
        for (0..memory_properties.memory_type_count) |i| {
            const flags = memory_properties.memory_types[i].property_flags;

            if (flags.device_local_bit and flags.host_visible_bit) {
                supports_device_local_host_visible = true;
                break;
            }
        }

        if (supports_device_local_host_visible) {
            self.score += 500;
        }

        self.memory_properties = memory_properties;
    }

    fn initDepthFormat(self: *Self, instance_api: InstanceAPI) !void {
        for (desired_depth_formats) |desired_format| {
            const format_properties = instance_api.getPhysicalDeviceFormatProperties(self.handle, desired_format);

            if (format_properties.linear_tiling_features.depth_stencil_attachment_bit or format_properties.optimal_tiling_features.depth_stencil_attachment_bit) {
                self.depth_format = desired_format;
                return;
            }
        }

        return error.couldNotFindDepthFormat;
    }

    fn initSurfaceSupport(self: *Self, instance_api: InstanceAPI, surface: vk.SurfaceKHR) !void {
        var format_count: u32 = undefined;
        _ = try instance_api.getPhysicalDeviceSurfaceFormatsKHR(self.handle, surface, &format_count, null);

        if (format_count == 0) {
            return error.noDeviceSurfaceFormatsFound;
        }

        var present_mode_count: u32 = undefined;
        _ = try instance_api.getPhysicalDeviceSurfacePresentModesKHR(self.handle, surface, &present_mode_count, null);

        if (present_mode_count == 0) {
            return error.noDevicePresentModesFound;
        }
    }

    fn initExtensionSupport(self: Self, allocator: Allocator, instance_api: InstanceAPI) !void {
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
                return error.extensionNotSupported;
            }
        }
    }

    fn initQueueSupport(self: *Self, allocator: Allocator, instance_api: InstanceAPI, surface: vk.SurfaceKHR) !void {
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
            const queue_family_index = @as(u32, @intCast(i));

            if (queue_family.queue_flags.graphics_bit) {
                if (try instance_api.getPhysicalDeviceSurfaceSupportKHR(self.handle, queue_family_index, surface) == vk.TRUE) {
                    graphics_family_index = queue_family_index;
                    present_family_index = queue_family_index;
                }
            }
        }

        var min_transfer_score: u8 = std.math.maxInt(u8);
        for (queue_families, 0..) |queue_family, i| {
            const queue_family_index = @as(u32, @intCast(i));

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
            return error.queueFamilyTypeNotSupported;
        }

        self.graphics_family_index = graphics_family_index.?;
        self.present_family_index = present_family_index.?;
        self.compute_family_index = compute_family_index.?;
        self.transfer_family_index = transfer_family_index.?;
    }
};

pub const Queue = struct {
    const Self = @This();

    handle: vk.Queue,
    family_index: u32,

    fn init(device: vk.Device, device_api: DeviceAPI, family_index: u32) Self {
        return .{
            .handle = device_api.getDeviceQueue(device, family_index, 0),
            .family_index = family_index,
        };
    }
};
