const std = @import("std");
const vk = @import("vk.zig");
const zing = @import("../zing.zig");
const Renderer = @import("renderer.zig");
const CommandBuffer = @import("command_buffer.zig");

const Allocator = std.mem.Allocator;

const Image = @This();

handle: vk.Image,
memory: vk.DeviceMemory,
view: vk.ImageView,
extent: vk.Extent3D,

// public
pub fn init(
    memory_flags: vk.MemoryPropertyFlags,
    create_info: *const vk.ImageCreateInfo,
    view_create_info: ?*vk.ImageViewCreateInfo,
) !Image {
    var self: Image = undefined;
    self.extent = create_info.extent;
    self.handle = .null_handle;
    self.memory = .null_handle;
    self.view = .null_handle;

    errdefer self.deinit();

    self.handle = try Renderer.device_api.createImage(Renderer.device, create_info, null);

    const memory_requirements = Renderer.device_api.getImageMemoryRequirements(Renderer.device, self.handle);
    self.memory = try Renderer.allocate(memory_requirements, memory_flags);
    try Renderer.device_api.bindImageMemory(Renderer.device, self.handle, self.memory, 0);

    if (view_create_info) |view_info| {
        view_info.image = self.handle;
        self.view = try Renderer.device_api.createImageView(Renderer.device, view_info, null);
    }

    return self;
}

pub fn deinit(self: *Image) void {
    if (self.view != .null_handle) {
        Renderer.device_api.destroyImageView(Renderer.device, self.view, null);
    }
    if (self.handle != .null_handle) {
        Renderer.device_api.destroyImage(Renderer.device, self.handle, null);
    }
    if (self.memory != .null_handle) {
        Renderer.device_api.freeMemory(Renderer.device, self.memory, null);
    }
}

pub fn pipelineImageBarrier(
    self: *Image,
    command_buffer: *const CommandBuffer,
    src_stage_mask: vk.PipelineStageFlags,
    src_access_mask: vk.AccessFlags,
    old_layout: vk.ImageLayout,
    dst_stage_mask: vk.PipelineStageFlags,
    dst_access_mask: vk.AccessFlags,
    new_layout: vk.ImageLayout,
) !void {
    const subresource_range = vk.ImageSubresourceRange{
        .aspect_mask = .{ .color_bit = true },
        .base_array_layer = 0,
        .base_mip_level = 0,
        .level_count = vk.REMAINING_MIP_LEVELS,
        .layer_count = vk.REMAINING_ARRAY_LAYERS,
    };

    const barrier = vk.ImageMemoryBarrier{
        .src_access_mask = src_access_mask,
        .dst_access_mask = dst_access_mask,
        .old_layout = old_layout,
        .new_layout = new_layout,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = self.handle,
        .subresource_range = subresource_range,
    };

    Renderer.device_api.cmdPipelineBarrier(
        command_buffer.handle,
        src_stage_mask,
        dst_stage_mask,
        .{ .by_region_bit = true },
        0,
        null,
        0,
        null,
        1,
        @ptrCast(&barrier),
    );
}
