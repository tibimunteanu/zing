const std = @import("std");
const vk = @import("vk.zig");
const Context = @import("context.zig").Context;
const Allocator = std.mem.Allocator;
const maxInt = std.math.maxInt;

pub const Swapchain = struct {
    pub const PresentState = enum {
        optimal,
        suboptimal,
    };

    const Self = @This();

    context: *const Context,
    allocator: Allocator,

    capabilities: vk.SurfaceCapabilitiesKHR,
    extent: vk.Extent2D,
    surface_format: vk.SurfaceFormatKHR,
    present_mode: vk.PresentModeKHR,

    handle: vk.SwapchainKHR,
    images: []SwapchainImage,
    image_index: u32,
    next_image_acquired_semaphore: vk.Semaphore,

    // public init
    pub fn init(
        allocator: Allocator,
        context: *const Context,
        options: struct {
            desired_extent: vk.Extent2D,
            desired_surface_format: vk.SurfaceFormatKHR = vk.SurfaceFormatKHR{
                .format = .b8g8r8a8_srgb,
                .color_space = .srgb_nonlinear_khr,
            },
            desired_present_modes: []const vk.PresentModeKHR = &[_]vk.PresentModeKHR{
                .mailbox_khr,
                .immediate_khr,
            },
            old_handle: vk.SwapchainKHR = .null_handle,
        },
    ) !Self {
        var self: Self = undefined;
        self.context = context;
        self.allocator = allocator;

        try self.initCapabilities();
        try self.initExtent(options.desired_extent);
        try self.initSurfaceFormat(options.desired_surface_format);
        try self.initPresentMode(options.desired_present_modes);

        const image_count = self.getImageCount();
        const attached_queue_families = self.getAttachedQueueFamilies();

        const device = context.device;
        const device_api = context.device_api;

        self.handle = try device_api.createSwapchainKHR(device, &.{
            .flags = .{},
            .surface = context.surface,
            .min_image_count = image_count,
            .image_format = self.surface_format.format,
            .image_color_space = self.surface_format.color_space,
            .image_extent = self.extent,
            .image_array_layers = 1,
            .image_usage = .{ .color_attachment_bit = true, .transfer_dst_bit = true },
            .image_sharing_mode = if (attached_queue_families.len == 1) .concurrent else .exclusive,
            .queue_family_index_count = @intCast(attached_queue_families.len),
            .p_queue_family_indices = attached_queue_families.ptr,
            .pre_transform = self.capabilities.current_transform,
            .composite_alpha = .{ .opaque_bit_khr = true },
            .present_mode = self.present_mode,
            .clipped = vk.TRUE,
            .old_swapchain = options.old_handle,
        }, null);
        errdefer device_api.destroySwapchainKHR(device, self.handle, null);

        if (options.old_handle != .null_handle) {
            // the old swapchain handle still needs to be destroyed
            device_api.destroySwapchainKHR(device, options.old_handle, null);
        }

        try self.initImages();
        errdefer self.deinitImages();

        self.next_image_acquired_semaphore = try device_api.createSemaphore(device, &.{}, null);
        errdefer device_api.destroySemaphore(device, self.next_image_acquired_semaphore, null);

        // if the first just created swapchain fails to acquire it's first image, let it crash.
        // when this gets called in present, the caller handles .suboptimal and error.out_of_date
        // by triggering a recreate, which ends up acquiring next image again from here.
        // so if this fails again after recreate, it's up to the caller of present if it wants to retry or crash.
        _ = try self.acquireNextImage();

        return self;
    }

    pub fn deinit(self: *Self, options: struct { destroy_swapchain: bool = true }) void {
        self.deinitImages();

        self.context.device_api.destroySemaphore(self.context.device, self.next_image_acquired_semaphore, null);

        if (options.destroy_swapchain) {
            self.context.device_api.destroySwapchainKHR(self.context.device, self.handle, null);
        }
    }

    // public
    pub fn recreate(self: *Self, new_extent: vk.Extent2D) !void {
        const allocator = self.allocator;
        const context = self.context;
        const old_handle = self.handle;
        const old_surface_format = self.surface_format;
        const old_present_mode = self.present_mode;

        self.deinit(.{ .destroy_swapchain = false });

        self.* = try init(allocator, context, .{
            .desired_extent = new_extent,
            .desired_surface_format = old_surface_format,
            .desired_present_modes = &[1]vk.PresentModeKHR{old_present_mode},
            .old_handle = old_handle,
        });
    }

    pub fn getCurrentImage(self: Self) vk.Image {
        return self.images[self.image_index].image;
    }

    pub fn getCurrentSwapImage(self: Self) *const SwapchainImage {
        return &self.images[self.image_index];
    }

    pub fn waitForAllFences(self: Self) !void {
        for (self.images) |image| {
            image.waitForFrameFence(self.context) catch {};
        }
    }

    pub fn present(self: *Self, cmd_buffer: vk.CommandBuffer) !PresentState {
        const current_image = self.getCurrentSwapImage();

        // make sure the current frame has finished rendering.
        // NOTE: the fences start signaled so the first frame can get past them.
        try current_image.waitForFrameFence(self.context, .{ .reset = true });

        // submit the command buffer
        try self.context.device_api.queueSubmit(self.context.graphics_queue.handle, 1, &[_]vk.SubmitInfo{.{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&current_image.image_acquired_semaphore),
            .p_wait_dst_stage_mask = &[_]vk.PipelineStageFlags{.{ .top_of_pipe_bit = true }},
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&cmd_buffer),
            .signal_semaphore_count = 1,
            .p_signal_semaphores = @ptrCast(&current_image.render_finished_semaphore),
        }}, current_image.frame_fence);

        // present the current frame
        // NOTE: we ignore .suboptimal result here, but the next call to acquire next image catch and return it
        _ = try self.context.device_api.queuePresentKHR(self.context.present_queue.handle, &vk.PresentInfoKHR{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&current_image.render_finished_semaphore),
            .swapchain_count = 1,
            .p_swapchains = @ptrCast(&self.handle),
            .p_image_indices = @ptrCast(&self.image_index),
            .p_results = null,
        });

        // acquire next frame
        // NOTE: call acquire next image as the last step so we can reference the current image while rendering.
        return try self.acquireNextImage();
    }

    // internal
    fn initCapabilities(self: *Self) !void {
        self.capabilities = try self.context.instance_api.getPhysicalDeviceSurfaceCapabilitiesKHR(
            self.context.physical_device.handle,
            self.context.surface,
        );
    }

    fn initExtent(self: *Self, extent: vk.Extent2D) !void {
        self.extent = self.capabilities.current_extent;

        if (self.capabilities.current_extent.width == 0xFFFF_FFFF) {
            self.extent = .{
                .width = std.math.clamp(
                    extent.width,
                    self.capabilities.min_image_extent.width,
                    self.capabilities.max_image_extent.width,
                ),
                .height = std.math.clamp(
                    extent.height,
                    self.capabilities.min_image_extent.height,
                    self.capabilities.max_image_extent.height,
                ),
            };
        }

        if (self.extent.width == 0 or self.extent.height == 0) {
            return error.invalidSurfaceDimensions;
        }
    }

    fn initSurfaceFormat(self: *Self, desired_surface_format: vk.SurfaceFormatKHR) !void {
        const instance_api = self.context.instance_api;
        const physical_device = self.context.physical_device.handle;
        const surface = self.context.surface;

        var count: u32 = undefined;
        _ = try instance_api.getPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &count, null);

        const surface_formats = try self.allocator.alloc(vk.SurfaceFormatKHR, count);
        defer self.allocator.free(surface_formats);
        _ = try instance_api.getPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &count, surface_formats.ptr);

        for (surface_formats) |surface_format| {
            if (std.meta.eql(surface_format, desired_surface_format)) {
                self.surface_format = desired_surface_format;
                return;
            }
        }

        self.surface_format = surface_formats[0]; // there must always be at least one
    }

    fn initPresentMode(self: *Self, desired_present_modes: []const vk.PresentModeKHR) !void {
        const instance_api = self.context.instance_api;
        const physical_device = self.context.physical_device.handle;
        const surface = self.context.surface;

        var count: u32 = undefined;
        _ = try instance_api.getPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &count, null);

        const present_modes = try self.allocator.alloc(vk.PresentModeKHR, count);
        defer self.allocator.free(present_modes);
        _ = try instance_api.getPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &count, present_modes.ptr);

        for (desired_present_modes) |desired_mode| {
            if (std.mem.indexOfScalar(vk.PresentModeKHR, present_modes, desired_mode) != null) {
                self.present_mode = desired_mode;
            }
        }

        self.present_mode = .fifo_khr; // guaranteed to be available
    }

    fn getImageCount(self: Self) u32 {
        var image_count = self.capabilities.min_image_count + 1;
        if (self.capabilities.max_image_count > 0) {
            image_count = @min(image_count, self.capabilities.max_image_count);
        }
        return image_count;
    }

    fn getAttachedQueueFamilies(self: Self) []u32 {
        var queue_family_indices = [2]u32{
            self.context.graphics_queue.family_index,
            self.context.present_queue.family_index,
        };

        var count: u32 = if (self.context.graphics_queue.family_index != self.context.present_queue.family_index) 1 else 2;

        return queue_family_indices[0..count];
    }

    fn initImages(self: *Self) !void {
        const device = self.context.device;
        const device_api = self.context.device_api;

        // get the image handles
        var count: u32 = undefined;
        _ = try device_api.getSwapchainImagesKHR(device, self.handle, &count, null);

        const images = try self.allocator.alloc(vk.Image, count);
        defer self.allocator.free(images);
        _ = try device_api.getSwapchainImagesKHR(device, self.handle, &count, images.ptr);

        // allocate swapchain images
        const swapchain_images = try self.allocator.alloc(SwapchainImage, count);
        errdefer self.allocator.free(swapchain_images);

        for (images, 0..) |image, i| {
            swapchain_images[i] = try SwapchainImage.init(self.context, image, self.surface_format.format);
            errdefer swapchain_images[i].deinit(self.context);
        }

        self.images = swapchain_images;
    }

    fn deinitImages(self: *Self) void {
        for (self.images) |image| {
            image.deinit(self.context);
        }
        self.allocator.free(self.images);
    }

    fn acquireNextImage(self: *Self) !PresentState {
        // NOTE: in order to reference the current image while rendering,
        // call acquire next image as the last step.
        // and use an aux semaphore since we can't know beforehand which image attached semaphore to signal.
        const acquired = try self.context.device_api.acquireNextImageKHR(
            self.context.device,
            self.handle,
            maxInt(u64),
            self.next_image_acquired_semaphore,
            .null_handle,
        );

        // after getting the next image, we swap it's image acquired semaphore with the aux semaphore.
        std.mem.swap(
            vk.Semaphore,
            &self.images[acquired.image_index].image_acquired_semaphore,
            &self.next_image_acquired_semaphore,
        );

        self.image_index = acquired.image_index;

        // NOTE: we don't consider suboptimal an error because it's not required to handle it.
        // for example, while resizing, this could return suboptimal for many frames and the
        // caller should have the option to wait for the resize to finish and then recreate the swapchain.
        return switch (acquired.result) {
            .success => .optimal,
            .suboptimal_khr => .suboptimal,
            else => error.imageAcquireFailed,
        };
    }
};

const SwapchainImage = struct {
    image: vk.Image,
    view: vk.ImageView,
    image_acquired_semaphore: vk.Semaphore,
    render_finished_semaphore: vk.Semaphore,
    frame_fence: vk.Fence,

    // internal init
    fn init(context: *const Context, image: vk.Image, format: vk.Format) !SwapchainImage {
        const device = context.device;
        const device_api = context.device_api;

        const view = try device_api.createImageView(device, &.{
            .flags = .{},
            .image = image,
            .view_type = .@"2d",
            .format = format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null);
        errdefer device_api.destroyImageView(device, view, null);

        const image_acquired_semaphore = try device_api.createSemaphore(device, &.{}, null);
        errdefer device_api.destroySemaphore(device, image_acquired_semaphore, null);

        const render_finished_semaphore = try device_api.createSemaphore(device, &.{}, null);
        errdefer device_api.destroySemaphore(device, render_finished_semaphore, null);

        // NOTE: start signaled so the first frame can get past it.
        const frame_fence = try device_api.createFence(device, &.{ .flags = .{ .signaled_bit = true } }, null);
        errdefer device_api.destroyFence(device, frame_fence, null);

        return .{
            .image = image,
            .view = view,
            .image_acquired_semaphore = image_acquired_semaphore,
            .render_finished_semaphore = render_finished_semaphore,
            .frame_fence = frame_fence,
        };
    }

    fn deinit(self: SwapchainImage, context: *const Context) void {
        self.waitForFrameFence(context, .{ .reset = false }) catch return;

        context.device_api.destroyFence(context.device, self.frame_fence, null);
        context.device_api.destroySemaphore(context.device, self.render_finished_semaphore, null);
        context.device_api.destroySemaphore(context.device, self.image_acquired_semaphore, null);
        context.device_api.destroyImageView(context.device, self.view, null);
    }

    // internal
    fn waitForFrameFence(self: SwapchainImage, context: *const Context, options: struct { reset: bool = false }) !void {
        _ = try context.device_api.waitForFences(context.device, 1, @ptrCast(&self.frame_fence), vk.TRUE, maxInt(u64));

        if (options.reset) {
            try context.device_api.resetFences(context.device, 1, @ptrCast(&self.frame_fence));
        }
    }
};