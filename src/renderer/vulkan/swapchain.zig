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
    surface_format: vk.SurfaceFormatKHR,
    present_mode: vk.PresentModeKHR,
    extent: vk.Extent2D,

    swap_images: []SwapImage,
    image_index: u32,
    next_image_acquired: vk.Semaphore,

    pub fn init(allocator: Allocator, context: *const Context, extent: vk.Extent2D) !Self {
        return try initRecycle(allocator, context, extent, .null_handle);
    }

    pub fn initRecycle(allocator: Allocator, context: *const Context, extent: vk.Extent2D, old_handle: vk.SwapchainKHR) !Self {
        const capabilities = try context.instance_api.getPhysicalDeviceSurfaceCapabilitiesKHR(
            context.physical_device.handle,
            context.surface,
        );

        const actual_extent = try findActualExtent(capabilities, extent);
        const surface_format = try findSurfaceFormat(allocator, context);
        const present_mode = try findPresentMode(allocator, context);
        const image_count = findImageCount(capabilities);

        const queue_family_indices = [_]u32{ context.graphics_queue.family_index, context.present_queue.family_index };
        const queue_family_indices_shared = context.graphics_queue.family_index != context.present_queue.family_index;

        const handle = try context.device_api.createSwapchainKHR(context.device, &.{
            .flags = .{},
            .surface = context.surface,
            .min_image_count = image_count,
            .image_format = surface_format.format,
            .image_color_space = surface_format.color_space,
            .image_extent = actual_extent,
            .image_array_layers = 1,
            .image_usage = .{ .color_attachment_bit = true, .transfer_dst_bit = true },
            .image_sharing_mode = if (queue_family_indices_shared) .concurrent else .exclusive,
            .queue_family_index_count = queue_family_indices.len,
            .p_queue_family_indices = &queue_family_indices,
            .pre_transform = capabilities.current_transform,
            .composite_alpha = .{ .opaque_bit_khr = true },
            .present_mode = present_mode,
            .clipped = vk.TRUE,
            .old_swapchain = old_handle,
        }, null);
        errdefer context.device_api.destroySwapchainKHR(context.device, handle, null);

        if (old_handle != .null_handle) {
            // the old swapchain handle still needs to be destroyed
            context.device_api.destroySwapchainKHR(context.device, old_handle, null);
        }

        const swap_images = try initSwapchainImages(allocator, context, handle, surface_format.format);
        errdefer for (swap_images) |swap_image| swap_image.deinit(context);
        errdefer allocator.free(swap_images);

        var next_image_acquired = try context.device_api.createSemaphore(context.device, &.{}, null);
        errdefer context.device_api.destroySemaphore(context.device, next_image_acquired, null);

        const result = try context.device_api.acquireNextImageKHR(
            context.device,
            handle,
            std.math.maxInt(u64),
            next_image_acquired,
            .null_handle,
        );

        if (result.result != .success) {
            return error.imageAcquireFailed;
        }

        std.mem.swap(vk.Semaphore, &swap_images[result.image_index].image_acquired, &next_image_acquired);

        return .{
            .context = context,
            .allocator = allocator,
            .handle = handle,
            .surface_format = surface_format,
            .present_mode = present_mode,
            .extent = actual_extent,
            .swap_images = swap_images,
            .image_index = result.image_index,
            .next_image_acquired = next_image_acquired,
        };
    }

    pub fn deinit(self: Self) void {
        self.reset();
        self.context.device_api.destroySwapchainKHR(self.context.device, self.handle, null);
    }

    pub fn waitForAllFences(self: Self) !void {
        for (self.swap_images) |swap_image| swap_image.waitForFence(self.context) catch {};
    }

    pub fn recreate(self: *Self, new_extent: vk.Extent2D) !void {
        const allocator = self.allocator;
        const context = self.context;
        const old_handle = self.handle;

        self.reset();
        self.* = try initRecycle(allocator, context, new_extent, old_handle);
    }

    pub fn getCurrentImage(self: Self) vk.Image {
        return self.swap_images[self.image_index].image;
    }

    pub fn getCurrentSwapImage(self: Self) *const SwapImage {
        return &self.swap_images[self.image_index];
    }

    pub fn present(self: *Self, cmd_buffer: vk.CommandBuffer) !PresentState {
        // SIMPLE METHOD:
        // 1) Acquire next image
        // 2) Wait for and reset fence of the acquired image
        // 3) Submit command buffer with fence of acquired image, dependendent on the semaphore signalled by the first step.
        // 4) Present current frame, dependent on semaphore signalled by previous step
        // PROBLEM:
        // This way we can't reference the current image while rendering.
        // BETTER METHOD:
        // Shuffle the steps around so that acquire next image is the last step.
        // 1) Wait for and reset fence of current image
        // 2) Submit command buffer, signalling fence of current image and dependent on the semaphore signalled by step 4.
        // 3) Present current frame, dependent on semaphore signalled by the submit
        // 4) Acquire next image, signalling its semaphore
        // One problem that arises is that we can't know beforehand which semaphore to signal,
        // so we keep an extra auxilery semaphore that is swapped around

        // Step 1: Make sure the current frame has finished rendering
        const current = self.getCurrentSwapImage();
        try current.waitForFence(self.context);
        try self.context.device_api.resetFences(self.context.device, 1, @ptrCast(&current.frame_fence));

        // Step 2: Submit the command buffer
        const wait_stage = [_]vk.PipelineStageFlags{.{ .top_of_pipe_bit = true }};
        try self.context.device_api.queueSubmit(self.context.graphics_queue.handle, 1, &[_]vk.SubmitInfo{.{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&current.image_acquired),
            .p_wait_dst_stage_mask = &wait_stage,
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&cmd_buffer),
            .signal_semaphore_count = 1,
            .p_signal_semaphores = @ptrCast(&current.render_finished),
        }}, current.frame_fence);

        // Step 3: Present the current frame
        _ = try self.context.device_api.queuePresentKHR(self.context.present_queue.handle, &vk.PresentInfoKHR{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&current.render_finished),
            .swapchain_count = 1,
            .p_swapchains = @ptrCast(&self.handle),
            .p_image_indices = @ptrCast(&self.image_index),
            .p_results = null,
        });

        // Step 4: Acquire next frame
        const result = try self.context.device_api.acquireNextImageKHR(
            self.context.device,
            self.handle,
            std.math.maxInt(u64),
            self.next_image_acquired,
            .null_handle,
        );

        std.mem.swap(vk.Semaphore, &self.swap_images[result.image_index].image_acquired, &self.next_image_acquired);
        self.image_index = result.image_index;

        return switch (result.result) {
            .success => .optimal,
            .suboptimal_khr => .suboptimal,
            else => error.imageAcquireFailed,
        };
    }

    fn reset(self: Self) void {
        for (self.swap_images) |swap_image| swap_image.deinit(self.context);
        self.allocator.free(self.swap_images);
        self.context.device_api.destroySemaphore(self.context.device, self.next_image_acquired, null);
    }

    fn findImageCount(capabilities: vk.SurfaceCapabilitiesKHR) u32 {
        var image_count = capabilities.min_image_count + 1;
        if (capabilities.max_image_count > 0) {
            image_count = @min(image_count, capabilities.max_image_count);
        }
        return image_count;
    }

    fn findActualExtent(capabilities: vk.SurfaceCapabilitiesKHR, extent: vk.Extent2D) !vk.Extent2D {
        var actual_extent: vk.Extent2D = capabilities.current_extent;

        if (capabilities.current_extent.width == 0xFFFF_FFFF) {
            actual_extent = .{
                .width = std.math.clamp(
                    extent.width,
                    capabilities.min_image_extent.width,
                    capabilities.max_image_extent.width,
                ),
                .height = std.math.clamp(
                    extent.height,
                    capabilities.min_image_extent.height,
                    capabilities.max_image_extent.height,
                ),
            };
        }

        if (actual_extent.width == 0 or actual_extent.height == 0) {
            return error.invalidSurfaceDimensions;
        }

        return actual_extent;
    }

    fn findSurfaceFormat(allocator: Allocator, context: *const Context) !vk.SurfaceFormatKHR {
        var count: u32 = undefined;
        _ = try context.instance_api.getPhysicalDeviceSurfaceFormatsKHR(context.physical_device.handle, context.surface, &count, null);

        const surface_formats = try allocator.alloc(vk.SurfaceFormatKHR, count);
        defer allocator.free(surface_formats);
        _ = try context.instance_api.getPhysicalDeviceSurfaceFormatsKHR(context.physical_device.handle, context.surface, &count, surface_formats.ptr);

        const preferred_format = vk.SurfaceFormatKHR{
            .format = .b8g8r8a8_srgb,
            .color_space = .srgb_nonlinear_khr,
        };

        for (surface_formats) |surface_format| {
            if (std.meta.eql(surface_format, preferred_format)) {
                return preferred_format;
            }
        }

        return surface_formats[0]; // there must always be at least one
    }

    fn findPresentMode(allocator: Allocator, context: *const Context) !vk.PresentModeKHR {
        var count: u32 = undefined;
        _ = try context.instance_api.getPhysicalDeviceSurfacePresentModesKHR(context.physical_device.handle, context.surface, &count, null);

        const present_modes = try allocator.alloc(vk.PresentModeKHR, count);
        defer allocator.free(present_modes);
        _ = try context.instance_api.getPhysicalDeviceSurfacePresentModesKHR(context.physical_device.handle, context.surface, &count, present_modes.ptr);

        const preferred_modes = [_]vk.PresentModeKHR{
            .mailbox_khr,
            .immediate_khr,
        };

        for (preferred_modes) |preferred_mode| {
            if (std.mem.indexOfScalar(vk.PresentModeKHR, present_modes, preferred_mode) != null) {
                return preferred_mode;
            }
        }

        return .fifo_khr;
    }

    fn initSwapchainImages(allocator: Allocator, context: *const Context, swapchain: vk.SwapchainKHR, format: vk.Format) ![]SwapImage {
        // get the images
        var count: u32 = undefined;
        _ = try context.device_api.getSwapchainImagesKHR(context.device, swapchain, &count, null);

        const images = try allocator.alloc(vk.Image, count);
        defer allocator.free(images);
        _ = try context.device_api.getSwapchainImagesKHR(context.device, swapchain, &count, images.ptr);

        // allocate swap images
        const swap_images = try allocator.alloc(SwapImage, count);
        errdefer allocator.free(swap_images);

        var i: usize = 0;
        errdefer for (swap_images[0..i]) |swap_image| swap_image.deinit(context);

        for (images) |image| {
            swap_images[i] = try SwapImage.init(context, image, format);
            i += 1;
        }

        return swap_images;
    }
};

const SwapImage = struct {
    image: vk.Image,
    view: vk.ImageView,
    image_acquired: vk.Semaphore,
    render_finished: vk.Semaphore,
    frame_fence: vk.Fence,

    fn init(context: *const Context, image: vk.Image, format: vk.Format) !SwapImage {
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

        const image_acquired = try context.device_api.createSemaphore(context.device, &.{}, null);
        errdefer context.device_api.destroySemaphore(context.device, image_acquired, null);

        const render_finished = try context.device_api.createSemaphore(context.device, &.{}, null);
        errdefer context.device_api.destroySemaphore(context.device, render_finished, null);

        const frame_fence = try context.device_api.createFence(context.device, &.{ .flags = .{ .signaled_bit = true } }, null);
        errdefer context.device_api.destroyFence(context.device, frame_fence, null);

        return .{
            .image = image,
            .view = view,
            .image_acquired = image_acquired,
            .render_finished = render_finished,
            .frame_fence = frame_fence,
        };
    }

    fn deinit(self: SwapImage, context: *const Context) void {
        self.waitForFence(context) catch return;
        context.device_api.destroyImageView(context.device, self.view, null);
        context.device_api.destroySemaphore(context.device, self.image_acquired, null);
        context.device_api.destroySemaphore(context.device, self.render_finished, null);
        context.device_api.destroyFence(context.device, self.frame_fence, null);
    }

    fn waitForFence(self: SwapImage, context: *const Context) !void {
        _ = try context.device_api.waitForFences(
            context.device,
            1,
            @ptrCast(&self.frame_fence),
            vk.TRUE,
            std.math.maxInt(u64),
        );
    }
};
