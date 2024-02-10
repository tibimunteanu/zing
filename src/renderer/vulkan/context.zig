const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("mach-glfw");
const vk = @import("vk.zig");
const Swapchain = @import("swapchain.zig").Swapchain;
const RenderPass = @import("renderpass.zig").RenderPass;
const CommandBuffer = @import("command_buffer.zig").CommandBuffer;
const Framebuffer = @import("framebuffer.zig").Framebuffer;
const MaterialShader = @import("material_shader.zig").MaterialShader;
const Buffer = @import("buffer.zig").Buffer;
const BeginFrameResult = @import("../types.zig").BeginFrameResult;
const GeometryRenderData = @import("../types.zig").GeometryRenderData;
const Image = @import("image.zig").Image;
const Texture = @import("../../resources/texture.zig").Texture;
const TextureData = @import("vulkan_types.zig").TextureData;
const Allocator = std.mem.Allocator;
const math = @import("zmath");

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

pub const Vertex = struct {
    pub const binding_description = vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(Vertex),
        .input_rate = .vertex,
    };

    pub const attribute_description = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(Vertex, "position"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Vertex, "texcoord"),
        },
        .{
            .binding = 0,
            .location = 2,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(Vertex, "color"),
        },
    };

    position: [3]f32,
    texcoord: [2]f32,
    color: [4]f32,
};

pub const vertices = [_]Vertex{
    .{ .position = .{ -5.0, -5.0, 0.0 }, .texcoord = .{ 0.0, 0.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
    .{ .position = .{ 5.0, -5.0, 0.0 }, .texcoord = .{ 1.0, 0.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
    .{ .position = .{ 5.0, 5.0, 0.0 }, .texcoord = .{ 1.0, 1.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },
    .{ .position = .{ -5.0, 5.0, 0.0 }, .texcoord = .{ 0.0, 1.0 }, .color = .{ 1.0, 1.0, 0.0, 1.0 } },
};

pub const indices = [_]u32{ 0, 1, 2, 0, 2, 3 };

pub const Context = struct {
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
    framebuffers: std.ArrayList(Framebuffer),

    main_render_pass: RenderPass,

    graphics_command_pool: vk.CommandPool,
    graphics_command_buffers: std.ArrayList(CommandBuffer),

    material_shader: MaterialShader,

    vertex_buffer: Buffer,
    vertex_offset: usize,

    index_buffer: Buffer,
    index_offset: usize,

    desired_extent: glfw.Window.Size,
    desired_extent_generation: u32,

    default_diffuse: *Texture,

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

        self.swapchain = try Swapchain.init(self.allocator, self, .{});
        errdefer self.swapchain.deinit(.{});

        self.main_render_pass = try RenderPass.init(
            self,
            .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = self.swapchain.extent,
            },
            .{
                .color = [_]f32{ 0.1, 0.2, 0.6, 1.0 },
                .depth = 1.0,
                .stencil = 0,
            },
        );
        errdefer self.main_render_pass.deinit();

        // framebuffers
        self.framebuffers = try std.ArrayList(Framebuffer).initCapacity(self.allocator, self.swapchain.images.len);
        self.framebuffers.items.len = self.swapchain.images.len;

        for (self.framebuffers.items) |*framebuffer| {
            framebuffer.handle = .null_handle;
        }

        try self.recreateFramebuffers(&self.main_render_pass);
        errdefer {
            for (self.framebuffers.items) |*framebuffer| {
                if (framebuffer.handle != .null_handle) {
                    framebuffer.deinit();
                }
            }
            self.framebuffers.deinit();
        }

        // create command pool
        self.graphics_command_pool = try self.device_api.createCommandPool(self.device, &vk.CommandPoolCreateInfo{
            .queue_family_index = self.graphics_queue.family_index,
            .flags = .{ .reset_command_buffer_bit = true },
        }, null);
        errdefer self.device_api.destroyCommandPool(self.device, self.graphics_command_pool, null);

        // create command buffers
        try self.initCommandBuffers(.{ .allocate = true, .allocator = self.allocator });
        errdefer self.deinitCommandbuffers(.{ .deallocate = true });

        self.material_shader = try MaterialShader.init(self.allocator, self, self.default_diffuse);
        errdefer self.material_shader.deinit();

        // create buffers
        self.vertex_buffer = try Buffer.init(
            self,
            @sizeOf(@TypeOf(vertices)),
            .{ .vertex_buffer_bit = true, .transfer_dst_bit = true, .transfer_src_bit = true },
            .{ .device_local_bit = true },
            .{ .bind_on_create = true },
        );
        self.vertex_offset = 0;
        errdefer self.vertex_buffer.deinit();

        self.index_buffer = try Buffer.init(
            self,
            @sizeOf(@TypeOf(indices)),
            .{ .index_buffer_bit = true, .transfer_dst_bit = true, .transfer_src_bit = true },
            .{ .device_local_bit = true },
            .{ .bind_on_create = true },
        );
        self.index_offset = 0;
        errdefer self.index_buffer.deinit();

        // upload data to buffers
        try self.uploadDataRegion(&self.vertex_buffer, vk.BufferCopy{
            .src_offset = 0,
            .dst_offset = 0,
            .size = @sizeOf(@TypeOf(vertices)),
        }, &std.mem.toBytes(vertices));

        try self.uploadDataRegion(&self.index_buffer, vk.BufferCopy{
            .src_offset = 0,
            .dst_offset = 0,
            .size = @sizeOf(@TypeOf(indices)),
        }, &std.mem.toBytes(indices));

        _ = try self.material_shader.acquireResources();
    }

    pub fn deinit(self: *Context) void {
        self.device_api.deviceWaitIdle(self.device) catch {};

        self.vertex_buffer.deinit();
        self.index_buffer.deinit();
        self.material_shader.deinit();
        self.deinitCommandbuffers(.{ .deallocate = true });
        self.device_api.destroyCommandPool(self.device, self.graphics_command_pool, null);
        for (self.framebuffers.items) |*framebuffer| {
            framebuffer.deinit();
        }
        self.framebuffers.deinit();
        self.main_render_pass.deinit();
        self.swapchain.deinit(.{});
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

    pub fn beginFrame(self: *Context, delta_time: f32) !BeginFrameResult {
        self.delta_time = delta_time;

        if (self.desired_extent_generation != self.swapchain.extent_generation) {
            // NOTE: we could skip this and let the frame render and present will throw error.OutOfDateKHR
            // which is handled by endFrame() by recreating resources, but this way we avoid a best practices warning
            try self.recreateSwapchainFramebuffersAndCmdBuffers();
            return .resize;
        }

        const current_image = self.swapchain.getCurrentImage();
        var command_buffer = self.getCurrentCommandBuffer();
        const current_framebuffer = self.getCurrentFramebuffer();

        // make sure the current frame has finished rendering.
        // NOTE: the fences start signaled so the first frame can get past them.
        try current_image.waitForFrameFence(.{ .reset = true });

        command_buffer.state = .initial;
        self.main_render_pass.state = .initial;

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

        // TODO: maybe we should decouple rendering from the swapchain and instead render into a texture
        // which would then be copied to the swapchain framebuffers if it's not out of date
        self.main_render_pass.begin(command_buffer, current_framebuffer.handle);

        return .render;
    }

    pub fn endFrame(self: *Context) !void {
        const current_image = self.swapchain.getCurrentImage();
        var command_buffer = self.getCurrentCommandBuffer();

        // end the render pass and the command buffer
        self.main_render_pass.end(command_buffer);
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

        command_buffer.state = .pending;
        self.main_render_pass.state = .pending;

        const state = self.swapchain.present() catch |err| switch (err) {
            error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
            else => |narrow| return narrow,
        };

        // NOTE: we should always recreate resources when error.OutOfDateKHR, but here,
        // we decided to also always recreate resources when the result is .suboptimal.
        // this should be configurable, so that you can choose if you only want to recreate on error.
        if (state == .suboptimal) {
            std.log.info("endFrame() Present was suboptimal. Recreating resources.", .{});
            try self.recreateSwapchainFramebuffersAndCmdBuffers();
        }
    }

    pub fn getCurrentCommandBuffer(self: Context) *CommandBuffer {
        return &self.graphics_command_buffers.items[self.swapchain.image_index];
    }

    pub fn getCurrentFramebuffer(self: Context) *Framebuffer {
        return &self.framebuffers.items[self.swapchain.image_index];
    }

    pub fn updateGlobalState(self: *Context, projection: math.Mat, view: math.Mat) !void {
        const command_buffer = self.getCurrentCommandBuffer();
        self.material_shader.bind(command_buffer);

        self.material_shader.global_uniform_data.projection = projection;
        self.material_shader.global_uniform_data.view = view;

        try self.material_shader.updateGlobalUniformData();
    }

    pub fn updateObjectState(self: *Context, data: GeometryRenderData) !void {
        // const command_buffer = self.getCurrentCommandBuffer();
        // self.shader.bind(command_buffer);

        try self.material_shader.updateObjectUniformData(data);
    }

    pub fn drawFrame(self: Context) void {
        const command_buffer = self.getCurrentCommandBuffer();

        self.device_api.cmdBindVertexBuffers(
            command_buffer.handle,
            0,
            1,
            @ptrCast(&self.vertex_buffer.handle),
            @ptrCast(&[_]u64{0}),
        );

        self.device_api.cmdBindIndexBuffer(
            command_buffer.handle,
            self.index_buffer.handle,
            0,
            .uint32,
        );

        self.device_api.cmdDrawIndexed(command_buffer.handle, 6, 1, 0, 0, 0);
    }

    pub fn createTexture(
        self: *Context,
        allocator: Allocator,
        name: []const u8,
        width: u32,
        height: u32,
        channel_count: u8,
        has_transparency: bool,
        auto_release: bool,
        pixels: []const u8,
    ) !Texture {
        _ = name;
        _ = auto_release;

        var texture: Texture = undefined;
        texture.width = width;
        texture.height = height;
        texture.channel_count = channel_count;
        texture.generation = .null_handle;

        const internal_data = try allocator.create(TextureData);
        errdefer allocator.destroy(internal_data);

        texture.internal_data = internal_data;

        const image_size: vk.DeviceSize = width * height * channel_count;
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
            .width = width,
            .height = height,
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

        texture.has_transparency = has_transparency;
        texture.generation = @enumFromInt(0);

        return texture;
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
            .pp_enabled_layer_names = null,
            .enabled_extension_count = @intCast(device_extensions.items.len),
            .pp_enabled_extension_names = @ptrCast(device_extensions.items),
            .p_enabled_features = null,
        }, null);

        return device;
    }

    fn initCommandBuffers(self: *Context, options: struct { allocate: bool = false, allocator: ?Allocator = null }) !void {
        if (options.allocate) {
            self.graphics_command_buffers = try std.ArrayList(CommandBuffer).initCapacity(options.allocator.?, self.swapchain.images.len);
            self.graphics_command_buffers.items.len = self.swapchain.images.len;

            for (self.graphics_command_buffers.items) |*buffer| {
                buffer.handle = .null_handle;
                buffer.state = .invalid;
            }
        }
        errdefer if (options.allocate) self.graphics_command_buffers.deinit();

        for (self.graphics_command_buffers.items) |*buffer| {
            if (buffer.handle != .null_handle) {
                buffer.deinit();
            }

            buffer.* = try CommandBuffer.init(self, self.graphics_command_pool, true);
        }
    }

    fn deinitCommandbuffers(self: *Context, options: struct { deallocate: bool = false }) void {
        for (self.graphics_command_buffers.items) |*buffer| {
            buffer.deinit();
        }

        if (options.deallocate) {
            self.graphics_command_buffers.deinit();
        }
    }

    fn recreateSwapchainFramebuffersAndCmdBuffers(self: *Context) !void {
        try self.device_api.deviceWaitIdle(self.device);

        if (self.desired_extent.width == 0 or self.desired_extent.height == 0) {
            // NOTE: don't bother recreating resources if width or height are 0
            return;
        }

        const old_allocator = self.swapchain.allocator;
        const old_handle = self.swapchain.handle;
        const old_surface_format = self.swapchain.surface_format;
        const old_present_mode = self.swapchain.present_mode;

        self.swapchain.deinit(.{ .recycle_handle = true });

        self.swapchain = try Swapchain.init(old_allocator, self, .{
            .desired_surface_format = old_surface_format,
            .desired_present_modes = &[1]vk.PresentModeKHR{old_present_mode},
            .old_handle = old_handle,
        });

        self.main_render_pass.render_area.extent = self.swapchain.extent;

        try self.recreateFramebuffers(&self.main_render_pass);
        errdefer {
            for (self.framebuffers.items) |*framebuffer| {
                if (framebuffer.handle != .null_handle) {
                    framebuffer.deinit();
                }
            }
        }

        try self.initCommandBuffers(.{});
        errdefer self.deinitCommandbuffers(.{});

        self.swapchain.extent_generation = self.desired_extent_generation;
    }

    fn recreateFramebuffers(self: *Context, render_pass: *const RenderPass) !void {
        for (self.swapchain.images, self.framebuffers.items) |image, *framebuffer| {
            if (framebuffer.handle != .null_handle) {
                framebuffer.deinit();
            }

            const attachments = [_]vk.ImageView{
                image.view,
                self.swapchain.depth_image.view,
            };

            framebuffer.* = try Framebuffer.init(
                self,
                self.allocator,
                render_pass,
                self.swapchain.extent.width,
                self.swapchain.extent.height,
                &attachments,
            );
        }
    }

    fn uploadDataRegion(self: *Context, dst: *Buffer, region: vk.BufferCopy, data: []const u8) !void {
        var staging_buffer = try Buffer.init(
            self,
            dst.total_size,
            .{ .transfer_src_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
            .{ .bind_on_create = true },
        );
        defer staging_buffer.deinit();

        try staging_buffer.loadData(0, dst.total_size, .{}, data);

        try staging_buffer.copyTo(dst, self.graphics_command_pool, self.graphics_queue.handle, region);
    }
};

pub const PhysicalDevice = struct {
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

pub const Queue = struct {
    handle: vk.Queue,
    family_index: u32,

    fn init(context: *const Context, family_index: u32) Queue {
        return .{
            .handle = context.device_api.getDeviceQueue(context.device, family_index, 0),
            .family_index = family_index,
        };
    }
};
