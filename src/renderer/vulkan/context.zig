const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("mach-glfw");
const vk = @import("vk.zig");
const Allocator = std.mem.Allocator;

const required_device_extensions = [_][*:0]const u8{
    vk.extension_info.khr_swapchain.name,
};

const optional_device_extensions = [_][*:0]const u8{};

const optional_instance_extensions = [_][*:0]const u8{
    vk.extension_info.khr_get_physical_device_properties_2.name,
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

    pub fn init(allocator: Allocator, app_name: [*:0]const u8, window: glfw.Window) !Self {
        var self: Self = undefined;

        self.allocator = allocator;

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

        return self;
    }

    pub fn deinit(self: Self) void {
        if (self.physical_device.surface_formats) |surface_formats| self.allocator.free(surface_formats);
        if (self.physical_device.present_modes) |present_modes| self.allocator.free(present_modes);

        self.device_api.destroyDevice(self.device, null);
        self.instance_api.destroySurfaceKHR(self.instance, self.surface, null);
        self.instance_api.destroyInstance(self.instance, null);
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
        var scratchAllocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        var scratch = scratchAllocator.allocator();
        defer scratchAllocator.deinit();

        var count: u32 = undefined;
        _ = try instance_api.enumeratePhysicalDevices(instance, &count, null);

        const physical_devices = try scratch.alloc(vk.PhysicalDevice, count);
        errdefer scratch.free(physical_devices);
        _ = try instance_api.enumeratePhysicalDevices(instance, &count, physical_devices.ptr);

        var max_score: u32 = 0;
        var maybe_physical_device: ?PhysicalDevice = null;
        for (physical_devices) |physical_device| {
            if (try PhysicalDevice.init(scratch, physical_device, instance_api, surface)) |info| {
                if (info.score > max_score) {
                    max_score = info.score;
                    maybe_physical_device = info;
                }
            }
        }

        if (maybe_physical_device) |*physical_device| {
            // persist allocations made with the scratch
            physical_device.surface_formats = try allocator.dupe(vk.SurfaceFormatKHR, physical_device.surface_formats.?);
            physical_device.present_modes = try allocator.dupe(vk.PresentModeKHR, physical_device.present_modes.?);

            return physical_device.*;
        }

        return error.noSuitablePhysicalDeviceFound;
    }

    fn createDevice(allocator: Allocator, physical_device: PhysicalDevice, instance_api: InstanceAPI) !vk.Device {
        const priority = [_]f32{1};

        var queue_count: u32 = 0;
        var queue_family_indices: [4]u32 = undefined;
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
};

pub const PhysicalDevice = struct {
    handle: vk.PhysicalDevice,
    features: vk.PhysicalDeviceFeatures,
    properties: vk.PhysicalDeviceProperties,
    memory_properties: vk.PhysicalDeviceMemoryProperties,
    surface_capabilities: vk.SurfaceCapabilitiesKHR,
    surface_formats: ?[]vk.SurfaceFormatKHR,
    present_modes: ?[]vk.PresentModeKHR,
    graphics_family_index: u32,
    present_family_index: u32,
    compute_family_index: u32,
    transfer_family_index: u32,
    score: u32,

    pub fn init(allocator: Allocator, physical_device: vk.PhysicalDevice, instance_api: InstanceAPI, surface: vk.SurfaceKHR) !?PhysicalDevice {
        var info: PhysicalDevice = undefined;
        info.handle = physical_device;
        info.score = 1;

        if (!info.initFeatureSupport(instance_api)) {
            return null;
        }

        if (!info.initMemorySupport(instance_api)) {
            return null;
        }

        if (!try info.initExtensionSupport(allocator, instance_api)) {
            return null;
        }

        if (!try info.initSurfaceSupport(allocator, instance_api, surface)) {
            return null;
        }

        if (!try info.initQueueSupport(allocator, instance_api, surface)) {
            return null;
        }

        return info;
    }

    fn initFeatureSupport(self: *PhysicalDevice, instance_api: InstanceAPI) bool {
        const features = instance_api.getPhysicalDeviceFeatures(self.handle);
        const properties = instance_api.getPhysicalDeviceProperties(self.handle);

        if (features.sampler_anisotropy != vk.TRUE) {
            return false;
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

        return true;
    }

    fn initMemorySupport(self: *PhysicalDevice, instance_api: InstanceAPI) bool {
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

        return true;
    }

    fn initExtensionSupport(self: PhysicalDevice, allocator: Allocator, instance_api: InstanceAPI) !bool {
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
                return false;
            }
        }

        // TODO: make the optional extensions list into a map of pairs of extensions and weights
        //       which can then be used to increment the device score.
        return true;
    }

    fn initSurfaceSupport(self: *PhysicalDevice, allocator: Allocator, instance_api: InstanceAPI, surface: vk.SurfaceKHR) !bool {
        self.surface_formats = null;
        self.present_modes = null;

        var format_count: u32 = undefined;
        _ = try instance_api.getPhysicalDeviceSurfaceFormatsKHR(self.handle, surface, &format_count, null);

        var present_mode_count: u32 = undefined;
        _ = try instance_api.getPhysicalDeviceSurfacePresentModesKHR(self.handle, surface, &present_mode_count, null);

        if (format_count > 0 and present_mode_count > 0) {
            const surface_capabilities = try instance_api.getPhysicalDeviceSurfaceCapabilitiesKHR(self.handle, surface);

            const surface_formats = try allocator.alloc(vk.SurfaceFormatKHR, format_count);
            errdefer allocator.free(surface_formats);
            _ = try instance_api.getPhysicalDeviceSurfaceFormatsKHR(self.handle, surface, &format_count, surface_formats.ptr);

            const present_modes = try allocator.alloc(vk.PresentModeKHR, present_mode_count);
            errdefer allocator.free(present_modes);
            _ = try instance_api.getPhysicalDeviceSurfacePresentModesKHR(self.handle, surface, &present_mode_count, present_modes.ptr);

            self.surface_capabilities = surface_capabilities;
            self.surface_formats = surface_formats;
            self.present_modes = present_modes;

            return true;
        }

        return false;
    }

    fn initQueueSupport(self: *PhysicalDevice, allocator: Allocator, instance_api: InstanceAPI, surface: vk.SurfaceKHR) !bool {
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
            return false;
        }

        self.graphics_family_index = graphics_family_index.?;
        self.present_family_index = present_family_index.?;
        self.compute_family_index = compute_family_index.?;
        self.transfer_family_index = transfer_family_index.?;

        return true;
    }
};

pub const Queue = struct {
    handle: vk.Queue,
    family_index: u32,

    fn init(device: vk.Device, device_api: DeviceAPI, family_index: u32) Queue {
        return .{
            .handle = device_api.getDeviceQueue(device, family_index, 0),
            .family_index = family_index,
        };
    }
};
