const std = @import("std");
const vk = @import("vk.zig");
const Context = @import("context.zig").Context;
const Allocator = std.mem.Allocator;

pub const Swapchain = struct {
    pub const PresentState = enum {
        optimal,
        suboptimal,
    };

    const Self = @This();

    context: *const Context,
    allocator: Allocator,

    handle: vk.SwapchainKHR,
    capabilities: vk.SurfaceCapabilitiesKHR,
    extent: vk.Extent2D,
    surface_format: vk.SurfaceFormatKHR,
    present_mode: vk.PresentModeKHR,

    images: []SwapchainImage,
    image_index: u32,
    next_image_acquired_semaphore: vk.Semaphore,

    pub fn init(allocator: Allocator, context: *const Context, extent: vk.Extent2D) !Self {
        return try initRecycle(allocator, context, extent, .null_handle);
    }

    pub fn initRecycle(allocator: Allocator, context: *const Context, extent: vk.Extent2D, old_handle: vk.SwapchainKHR) !Self {
        var self: Self = undefined;
        self.context = context;
        self.allocator = allocator;

        self.capabilities = try context.instance_api.getPhysicalDeviceSurfaceCapabilitiesKHR(
            context.physical_device.handle,
            context.surface,
        );

        try self.initExtent(extent);
        try self.initSurfaceFormat();
        try self.initPresentMode();

        var image_count = self.capabilities.min_image_count + 1;
        if (self.capabilities.max_image_count > 0) {
            image_count = @min(image_count, self.capabilities.max_image_count);
        }

        const queue_family_indices = [_]u32{ context.graphics_queue.family_index, context.present_queue.family_index };
        const queue_family_indices_shared = context.graphics_queue.family_index != context.present_queue.family_index;

        self.handle = try context.device_api.createSwapchainKHR(context.device, &.{
            .flags = .{},
            .surface = context.surface,
            .min_image_count = image_count,
            .image_format = self.surface_format.format,
            .image_color_space = self.surface_format.color_space,
            .image_extent = self.extent,
            .image_array_layers = 1,
            .image_usage = .{ .color_attachment_bit = true, .transfer_dst_bit = true },
            .image_sharing_mode = if (queue_family_indices_shared) .concurrent else .exclusive,
            .queue_family_index_count = queue_family_indices.len,
            .p_queue_family_indices = &queue_family_indices,
            .pre_transform = self.capabilities.current_transform,
            .composite_alpha = .{ .opaque_bit_khr = true },
            .present_mode = self.present_mode,
            .clipped = vk.TRUE,
            .old_swapchain = old_handle,
        }, null);
        errdefer context.device_api.destroySwapchainKHR(context.device, self.handle, null);

        if (old_handle != .null_handle) {
            // the old swapchain handle still needs to be destroyed
            context.device_api.destroySwapchainKHR(context.device, old_handle, null);
        }

        try self.initImages();
        errdefer for (self.images) |image| image.deinit(context);
        errdefer allocator.free(self.images);

        self.next_image_acquired_semaphore = try context.device_api.createSemaphore(context.device, &.{}, null);
        errdefer context.device_api.destroySemaphore(context.device, self.next_image_acquired_semaphore, null);

        _ = try self.acquireNextImage();

        return self;
    }

    pub fn deinit(self: Self, options: struct { destroy_swapchain: bool = true }) void {
        for (self.images) |image| image.deinit(self.context);
        self.allocator.free(self.images);

        self.context.device_api.destroySemaphore(self.context.device, self.next_image_acquired_semaphore, null);

        if (options.destroy_swapchain) {
            self.context.device_api.destroySwapchainKHR(self.context.device, self.handle, null);
        }
    }

    pub fn recreate(self: *Self, new_extent: vk.Extent2D) !void {
        const allocator = self.allocator;
        const context = self.context;
        const old_handle = self.handle;

        self.deinit(.{ .destroy_swapchain = false });
        self.* = try initRecycle(allocator, context, new_extent, old_handle);
    }

    pub fn getCurrentImage(self: Self) vk.Image {
        return self.images[self.image_index].image;
    }

    pub fn getCurrentSwapImage(self: Self) *const SwapchainImage {
        return &self.images[self.image_index];
    }

    pub fn waitForAllFences(self: Self) !void {
        for (self.images) |image| image.waitForFence(self.context) catch {};
    }

    pub fn present(self: *Self, cmd_buffer: vk.CommandBuffer) !PresentState {
        // make sure the current frame has finished rendering
        const current = self.getCurrentSwapImage();
        try current.waitForFence(self.context);
        try self.context.device_api.resetFences(self.context.device, 1, @ptrCast(&current.frame_fence));

        // submit the command buffer
        try self.context.device_api.queueSubmit(self.context.graphics_queue.handle, 1, &[_]vk.SubmitInfo{.{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&current.image_acquired_semaphore),
            .p_wait_dst_stage_mask = &[_]vk.PipelineStageFlags{.{ .top_of_pipe_bit = true }},
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&cmd_buffer),
            .signal_semaphore_count = 1,
            .p_signal_semaphores = @ptrCast(&current.render_finished_semaphore),
        }}, current.frame_fence);

        // present the current frame
        _ = try self.context.device_api.queuePresentKHR(self.context.present_queue.handle, &vk.PresentInfoKHR{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&current.render_finished_semaphore),
            .swapchain_count = 1,
            .p_swapchains = @ptrCast(&self.handle),
            .p_image_indices = @ptrCast(&self.image_index),
            .p_results = null,
        });

        // acquire next frame
        return self.acquireNextImage();
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

    fn initSurfaceFormat(self: *Self) !void {
        var count: u32 = undefined;
        _ = try self.context.instance_api.getPhysicalDeviceSurfaceFormatsKHR(self.context.physical_device.handle, self.context.surface, &count, null);

        const surface_formats = try self.allocator.alloc(vk.SurfaceFormatKHR, count);
        defer self.allocator.free(surface_formats);
        _ = try self.context.instance_api.getPhysicalDeviceSurfaceFormatsKHR(self.context.physical_device.handle, self.context.surface, &count, surface_formats.ptr);

        const preferred_format = vk.SurfaceFormatKHR{
            .format = .b8g8r8a8_srgb,
            .color_space = .srgb_nonlinear_khr,
        };

        for (surface_formats) |surface_format| {
            if (std.meta.eql(surface_format, preferred_format)) {
                self.surface_format = preferred_format;
                return;
            }
        }

        self.surface_format = surface_formats[0]; // there must always be at least one
    }

    fn initPresentMode(self: *Self) !void {
        var count: u32 = undefined;
        _ = try self.context.instance_api.getPhysicalDeviceSurfacePresentModesKHR(self.context.physical_device.handle, self.context.surface, &count, null);

        const present_modes = try self.allocator.alloc(vk.PresentModeKHR, count);
        defer self.allocator.free(present_modes);
        _ = try self.context.instance_api.getPhysicalDeviceSurfacePresentModesKHR(self.context.physical_device.handle, self.context.surface, &count, present_modes.ptr);

        const preferred_modes = [_]vk.PresentModeKHR{
            .mailbox_khr,
            .immediate_khr,
        };

        for (preferred_modes) |preferred_mode| {
            if (std.mem.indexOfScalar(vk.PresentModeKHR, present_modes, preferred_mode) != null) {
                self.present_mode = preferred_mode;
            }
        }

        self.present_mode = .fifo_khr;
    }

    fn initImages(self: *Self) !void {
        // get the image handles
        var count: u32 = undefined;
        _ = try self.context.device_api.getSwapchainImagesKHR(self.context.device, self.handle, &count, null);

        const images = try self.allocator.alloc(vk.Image, count);
        defer self.allocator.free(images);
        _ = try self.context.device_api.getSwapchainImagesKHR(self.context.device, self.handle, &count, images.ptr);

        // allocate swapchain images
        const swapchain_images = try self.allocator.alloc(SwapchainImage, count);
        errdefer self.allocator.free(swapchain_images);

        for (images, 0..) |image, i| {
            swapchain_images[i] = try SwapchainImage.init(self.context, image, self.surface_format.format);
            errdefer swapchain_images[i].deinit(self.context);
        }

        self.images = swapchain_images;
    }

    fn acquireNextImage(self: *Self) !PresentState {
        const acquired = try self.context.device_api.acquireNextImageKHR(
            self.context.device,
            self.handle,
            std.math.maxInt(u64),
            self.next_image_acquired_semaphore,
            .null_handle,
        );

        // in order to reference the current image while rendering, we acquire next image as the last step.
        // since we can't know beforehand which semaphore to signal,
        // we keep an extra auxilery semaphore that is swapped around
        std.mem.swap(
            vk.Semaphore,
            &self.images[acquired.image_index].image_acquired_semaphore,
            &self.next_image_acquired_semaphore,
        );

        self.image_index = acquired.image_index;

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

    fn init(context: *const Context, image: vk.Image, format: vk.Format) !SwapchainImage {
        const view = try context.device_api.createImageView(context.device, &.{
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
        errdefer context.device_api.destroyImageView(context.device, view, null);

        const image_acquired_semaphore = try context.device_api.createSemaphore(context.device, &.{}, null);
        errdefer context.device_api.destroySemaphore(context.device, image_acquired_semaphore, null);

        const render_finished_semaphore = try context.device_api.createSemaphore(context.device, &.{}, null);
        errdefer context.device_api.destroySemaphore(context.device, render_finished_semaphore, null);

        const frame_fence = try context.device_api.createFence(context.device, &.{ .flags = .{ .signaled_bit = true } }, null);
        errdefer context.device_api.destroyFence(context.device, frame_fence, null);

        return .{
            .image = image,
            .view = view,
            .image_acquired_semaphore = image_acquired_semaphore,
            .render_finished_semaphore = render_finished_semaphore,
            .frame_fence = frame_fence,
        };
    }

    fn deinit(self: SwapchainImage, context: *const Context) void {
        self.waitForFence(context) catch return;

        context.device_api.destroyFence(context.device, self.frame_fence, null);
        context.device_api.destroySemaphore(context.device, self.render_finished_semaphore, null);
        context.device_api.destroySemaphore(context.device, self.image_acquired_semaphore, null);
        context.device_api.destroyImageView(context.device, self.view, null);
    }

    fn waitForFence(self: SwapchainImage, context: *const Context) !void {
        _ = try context.device_api.waitForFences(
            context.device,
            1,
            @ptrCast(&self.frame_fence),
            vk.TRUE,
            std.math.maxInt(u64),
        );
    }
};
