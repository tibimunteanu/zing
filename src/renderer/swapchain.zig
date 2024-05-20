const std = @import("std");
const glfw = @import("glfw");
const vk = @import("vk.zig");
const config = @import("../config.zig");
const zing = @import("../zing.zig");
const Context = @import("context.zig");
const Image = @import("image.zig");

const Allocator = std.mem.Allocator;
const Array = std.BoundedArray;

const maxInt = std.math.maxInt;

const Swapchain = @This();

pub const PresentState = enum {
    optimal,
    suboptimal,
};

allocator: Allocator,

capabilities: vk.SurfaceCapabilitiesKHR,
extent: vk.Extent2D,
extent_generation: u32,
surface_format: vk.SurfaceFormatKHR,
present_mode: vk.PresentModeKHR,

handle: vk.SwapchainKHR,
images: Array(SwapchainImage, config.swapchain_max_images),
depth_image: Image,
image_index: u32,
next_image_acquired_semaphore: vk.Semaphore,

// public
pub fn init(
    allocator: Allocator, // only needed for interogating surface formats and presentation modes
    options: struct {
        desired_surface_format: vk.SurfaceFormatKHR = .{
            .format = .b8g8r8a8_srgb,
            .color_space = .srgb_nonlinear_khr,
        },
        desired_present_modes: []const vk.PresentModeKHR = &[_]vk.PresentModeKHR{
            .mailbox_khr,
            .fifo_relaxed_khr,
            .fifo_khr,
            .immediate_khr,
        },
        old_handle: vk.SwapchainKHR = .null_handle,
    },
) !Swapchain {
    var self: Swapchain = undefined;
    self.allocator = allocator;

    try self.initCapabilities();
    try self.initExtent();
    try self.initSurfaceFormat(options.desired_surface_format);
    try self.initPresentMode(options.desired_present_modes);

    const image_sharing = self.getImageSharingInfo();

    const ctx = zing.renderer.context;

    const device = ctx.device;
    const device_api = ctx.device_api;

    self.handle = try device_api.createSwapchainKHR(device, &.{
        .flags = .{},
        .surface = ctx.surface,
        .min_image_count = 3, // NOTE: at least triple buffering
        .image_format = self.surface_format.format,
        .image_color_space = self.surface_format.color_space,
        .image_extent = self.extent,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true, .transfer_dst_bit = true },
        .image_sharing_mode = if (image_sharing != null) .concurrent else .exclusive,
        .queue_family_index_count = if (image_sharing) |s| @intCast(s.len) else 0,
        .p_queue_family_indices = if (image_sharing) |s| s.ptr else undefined,
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

    // create an aux semaphore because we call acquireNextImage as the last step
    // in order to reference the current image while rendering.
    // since we can't know beforehand which image semaphore to signal, we swap in this aux.
    self.next_image_acquired_semaphore = try device_api.createSemaphore(device, &.{}, null);
    errdefer device_api.destroySemaphore(device, self.next_image_acquired_semaphore, null);

    // if the first just created swapchain fails to acquire it's first image, let it crash.
    // when this gets called in present(), the caller handles .suboptimal and error.OutOfDateKHR
    // by triggering a recreate, which ends up acquiring next image again from here.
    // so if this fails again after recreate, it's up to the caller of present if it wants to retry or crash.
    _ = try self.acquireNextImage();

    return self;
}

pub fn deinit(self: *Swapchain) void {
    const ctx = zing.renderer.context;

    self.deinitImages();
    ctx.device_api.destroySemaphore(ctx.device, self.next_image_acquired_semaphore, null);
    ctx.device_api.destroySwapchainKHR(ctx.device, self.handle, null);
}

pub fn reinit(self: *Swapchain) !void {
    const ctx = zing.renderer.context;

    var old = self.*;
    old.deinitImages();
    ctx.device_api.destroySemaphore(ctx.device, old.next_image_acquired_semaphore, null);

    self.* = try init(old.allocator, .{
        .desired_surface_format = old.surface_format,
        .desired_present_modes = &[1]vk.PresentModeKHR{old.present_mode},
        .old_handle = old.handle,
    });
}

pub fn getCurrentImage(self: *const Swapchain) *const SwapchainImage {
    return &self.images.constSlice()[self.image_index];
}

pub fn waitForAllFences(self: *const Swapchain) !void {
    for (self.images.constSlice()) |image| {
        image.waitForFrameFence(.{}) catch {};
    }
}

pub fn present(self: *Swapchain) !PresentState {
    const current_image = self.getCurrentImage();

    const ctx = zing.renderer.context;

    // present the current frame
    // NOTE: it's ok to ignore .suboptimal_khr result here. the following acquireNextImage() returns it.
    _ = try ctx.device_api.queuePresentKHR(
        ctx.present_queue.handle,
        &vk.PresentInfoKHR{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&current_image.render_finished_semaphore),
            .swapchain_count = 1,
            .p_swapchains = @ptrCast(&self.handle),
            .p_image_indices = @ptrCast(&self.image_index),
            .p_results = null,
        },
    );

    // acquire next frame
    // NOTE: call acquire next image as the last step so we can reference the current image while rendering.
    return try self.acquireNextImage();
}

// utils
fn initCapabilities(self: *Swapchain) !void {
    const ctx = zing.renderer.context;

    self.capabilities = try ctx.instance_api.getPhysicalDeviceSurfaceCapabilitiesKHR(
        ctx.physical_device.handle,
        ctx.surface,
    );
}

fn initExtent(self: *Swapchain) !void {
    const ctx = zing.renderer.context;

    self.extent = self.capabilities.current_extent;

    if (self.capabilities.current_extent.width == 0xFFFF_FFFF) {
        self.extent = .{
            .width = std.math.clamp(
                ctx.desired_extent.width,
                self.capabilities.min_image_extent.width,
                self.capabilities.max_image_extent.width,
            ),
            .height = std.math.clamp(
                ctx.desired_extent.height,
                self.capabilities.min_image_extent.height,
                self.capabilities.max_image_extent.height,
            ),
        };
    }

    self.extent_generation = ctx.desired_extent_generation;

    if (self.extent.width == 0 or self.extent.height == 0) {
        return error.InvalidSurfaceDimensions;
    }
}

// TODO: check supportedTransforms, supportedCompsiteAlpha and supportedUsageFlags from caps
fn initSurfaceFormat(self: *Swapchain, desired_surface_format: vk.SurfaceFormatKHR) !void {
    const ctx = zing.renderer.context;
    const physical_device = ctx.physical_device.handle;

    var count: u32 = undefined;
    _ = try ctx.instance_api.getPhysicalDeviceSurfaceFormatsKHR(physical_device, ctx.surface, &count, null);

    const surface_formats = try self.allocator.alloc(vk.SurfaceFormatKHR, count);
    defer self.allocator.free(surface_formats);
    _ = try ctx.instance_api.getPhysicalDeviceSurfaceFormatsKHR(physical_device, ctx.surface, &count, surface_formats.ptr);

    if (surface_formats.len == 1 and surface_formats[0].format == .undefined) {
        // NOTE: the spec says that if this is the case, then any format is available
        self.surface_format = desired_surface_format;
        return;
    }

    for (surface_formats) |surface_format| {
        if (std.meta.eql(surface_format, desired_surface_format)) {
            self.surface_format = desired_surface_format;
            return;
        }
    }

    std.log.info(
        "Desired surface format not available! Falling back to {s}",
        .{@tagName(surface_formats[0].format)},
    );
    self.surface_format = surface_formats[0]; // there must always be at least one
}

fn initPresentMode(self: *Swapchain, desired_present_modes: []const vk.PresentModeKHR) !void {
    const ctx = zing.renderer.context;
    const physical_device = ctx.physical_device.handle;

    var count: u32 = undefined;
    _ = try ctx.instance_api.getPhysicalDeviceSurfacePresentModesKHR(physical_device, ctx.surface, &count, null);

    const present_modes = try self.allocator.alloc(vk.PresentModeKHR, count);
    defer self.allocator.free(present_modes);
    _ = try ctx.instance_api.getPhysicalDeviceSurfacePresentModesKHR(physical_device, ctx.surface, &count, present_modes.ptr);

    for (desired_present_modes) |desired_mode| {
        if (std.mem.indexOfScalar(vk.PresentModeKHR, present_modes, desired_mode) != null) {
            self.present_mode = desired_mode;
            return;
        }
    }

    std.log.info("Desired present mode not available! Falling back to fifo_khr", .{});
    self.present_mode = .fifo_khr; // guaranteed to be available
}

fn getImageSharingInfo(self: *const Swapchain) ?[]const u32 {
    _ = self;

    const ctx = zing.renderer.context;

    if (ctx.graphics_queue.family_index == ctx.present_queue.family_index) {
        return null;
    }

    return &[_]u32{
        ctx.graphics_queue.family_index,
        ctx.present_queue.family_index,
    };
}

fn initImages(self: *Swapchain) !void {
    const ctx = zing.renderer.context;

    // get the image handles
    var count: u32 = undefined;
    _ = try ctx.device_api.getSwapchainImagesKHR(ctx.device, self.handle, &count, null);

    if (count > config.swapchain_max_images) {
        return error.MaxSwapchainImageCountExceeded;
    }

    var imageHandles: [config.swapchain_max_images]vk.Image = undefined;
    _ = try ctx.device_api.getSwapchainImagesKHR(ctx.device, self.handle, &count, &imageHandles);

    // init swapchain images
    try self.images.resize(0);
    for (0..count) |i| {
        try self.images.append(try SwapchainImage.init(imageHandles[i], self.surface_format.format));
    }
    errdefer {
        for (self.images.slice()) |*image| {
            image.deinit();
        }
        self.images.len = 0;
    }

    // create the depth image
    self.depth_image = try Image.init(
        vk.MemoryPropertyFlags{ .device_local_bit = true },
        &vk.ImageCreateInfo{
            .flags = .{},
            .image_type = .@"2d",
            .format = ctx.physical_device.depth_format,
            .extent = .{
                .width = self.extent.width,
                .height = self.extent.height,
                .depth = 1,
            },
            .mip_levels = 1,
            .array_layers = 1,
            .samples = .{ .@"1_bit" = true },
            .tiling = .optimal,
            .usage = .{ .depth_stencil_attachment_bit = true },
            .sharing_mode = .exclusive,
            .queue_family_index_count = 0,
            .p_queue_family_indices = null,
            .initial_layout = .undefined,
        },
        @constCast(&vk.ImageViewCreateInfo{
            .image = .null_handle,
            .view_type = .@"2d",
            .format = ctx.physical_device.depth_format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = .{ .depth_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }),
    );
}

fn deinitImages(self: *Swapchain) void {
    self.depth_image.deinit();

    for (self.images.slice()) |*image| {
        image.deinit();
    }
    self.images.len = 0;
}

fn acquireNextImage(self: *Swapchain) !PresentState {
    const ctx = zing.renderer.context;

    // NOTE: in order to reference the current image while rendering,
    // call acquire next image as the last step.
    // and use an aux semaphore since we can't know beforehand which image semaphore to signal.
    const acquired = try ctx.device_api.acquireNextImageKHR(
        ctx.device,
        self.handle,
        maxInt(u64),
        self.next_image_acquired_semaphore,
        .null_handle,
    );

    // after getting the next image, we swap it's image acquired semaphore with the aux semaphore.
    std.mem.swap(
        vk.Semaphore,
        &self.images.slice()[acquired.image_index].image_acquired_semaphore,
        &self.next_image_acquired_semaphore,
    );

    self.image_index = acquired.image_index;

    // NOTE: we don't consider .suboptimal an error because it's not required to handle it.
    return switch (acquired.result) {
        .success => .optimal,
        .suboptimal_khr => .suboptimal,
        else => error.AcquireNextImageFailed,
    };
}

const SwapchainImage = struct {
    handle: vk.Image,
    view: vk.ImageView,
    image_acquired_semaphore: vk.Semaphore,
    render_finished_semaphore: vk.Semaphore,
    frame_fence: vk.Fence,

    // utils
    fn init(handle: vk.Image, format: vk.Format) !SwapchainImage {
        const ctx = zing.renderer.context;

        const view = try ctx.device_api.createImageView(ctx.device, &.{
            .flags = .{},
            .image = handle,
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
        errdefer ctx.device_api.destroyImageView(ctx.device, view, null);

        const image_acquired_semaphore = try ctx.device_api.createSemaphore(ctx.device, &.{}, null);
        errdefer ctx.device_api.destroySemaphore(ctx.device, image_acquired_semaphore, null);

        const render_finished_semaphore = try ctx.device_api.createSemaphore(ctx.device, &.{}, null);
        errdefer ctx.device_api.destroySemaphore(ctx.device, render_finished_semaphore, null);

        // NOTE: start signaled so the first frame can get past it.
        const frame_fence = try ctx.device_api.createFence(ctx.device, &.{ .flags = .{ .signaled_bit = true } }, null);
        errdefer ctx.device_api.destroyFence(ctx.device, frame_fence, null);

        return .{
            .handle = handle,
            .view = view,
            .image_acquired_semaphore = image_acquired_semaphore,
            .render_finished_semaphore = render_finished_semaphore,
            .frame_fence = frame_fence,
        };
    }

    fn deinit(self: *SwapchainImage) void {
        self.waitForFrameFence(.{ .reset = false }) catch return;

        const ctx = zing.renderer.context;

        ctx.device_api.destroyFence(ctx.device, self.frame_fence, null);
        ctx.device_api.destroySemaphore(ctx.device, self.render_finished_semaphore, null);
        ctx.device_api.destroySemaphore(ctx.device, self.image_acquired_semaphore, null);
        ctx.device_api.destroyImageView(ctx.device, self.view, null);

        self.handle = .null_handle;
        self.view = .null_handle;
        self.image_acquired_semaphore = .null_handle;
        self.render_finished_semaphore = .null_handle;
        self.frame_fence = .null_handle;
    }

    // public
    pub fn waitForFrameFence(self: *const SwapchainImage, options: struct { reset: bool = false }) !void {
        const ctx = zing.renderer.context;

        _ = try ctx.device_api.waitForFences(ctx.device, 1, @ptrCast(&self.frame_fence), vk.TRUE, maxInt(u64));

        if (options.reset) {
            try ctx.device_api.resetFences(ctx.device, 1, @ptrCast(&self.frame_fence));
        }
    }
};
