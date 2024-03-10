const std = @import("std");
const vk = @import("vk.zig");
const Context = @import("context.zig");
const CommandBuffer = @import("command_buffer.zig");
const Allocator = std.mem.Allocator;

const Image = @This();

context: *const Context,

handle: vk.Image,
memory: vk.DeviceMemory,
view: vk.ImageView = .null_handle,
width: u32,
height: u32,
depth: u32,

// public
pub fn init(
    context: *const Context,
    options: struct {
        width: u32,
        height: u32,
        depth: u32 = 1,
        image_type: vk.ImageType = .@"2d",
        flags: vk.ImageCreateFlags = .{},
        mip_levels: u32 = 1,
        array_layers: u32 = 1,
        samples: vk.SampleCountFlags = .{ .@"1_bit" = true },
        format: vk.Format,
        tiling: vk.ImageTiling = .optimal,
        usage: vk.ImageUsageFlags = .{ .color_attachment_bit = true },
        sharing_mode: vk.SharingMode = .exclusive,
        queue_family_index_count: u32 = 0,
        p_queue_family_indices: ?[*]const u32 = null,
        initial_layout: vk.ImageLayout = .undefined,
        memory_flags: vk.MemoryPropertyFlags,
        init_view: bool = false,
        view_type: vk.ImageViewType = .@"2d",
        view_aspect_flags: vk.ImageAspectFlags = .{ .color_bit = true },
    },
) !Image {
    var self: Image = undefined;
    self.context = context;

    self.width = options.width;
    self.height = options.height;
    self.depth = options.depth;

    const device_api = context.device_api;
    const device = context.device;

    self.handle = try device_api.createImage(device, &vk.ImageCreateInfo{
        .flags = options.flags,
        .image_type = options.image_type,
        .format = options.format,
        .extent = .{
            .width = options.width,
            .height = options.height,
            .depth = options.depth,
        },
        .mip_levels = options.mip_levels,
        .array_layers = options.array_layers,
        .samples = options.samples,
        .tiling = options.tiling,
        .usage = options.usage,
        .sharing_mode = options.sharing_mode,
        .queue_family_index_count = options.queue_family_index_count,
        .p_queue_family_indices = options.p_queue_family_indices,
        .initial_layout = options.initial_layout,
    }, null);
    errdefer device_api.destroyImage(device, self.handle, null);

    const memory_requirements = device_api.getImageMemoryRequirements(device, self.handle);

    self.memory = try context.allocate(memory_requirements, options.memory_flags);
    errdefer device_api.freeMemory(device, self.memory, null);

    try device_api.bindImageMemory(device, self.handle, self.memory, 0);

    if (options.init_view) {
        try self.initView(options.view_type, options.format, options.view_aspect_flags);
    }
    errdefer self.deinitView(context);

    return self;
}

pub fn deinit(self: *Image) void {
    const device_api = self.context.device_api;
    const device = self.context.device;

    self.deinitView();

    device_api.destroyImage(device, self.handle, null);
    device_api.freeMemory(device, self.memory, null);
}

pub fn transitionLayout(
    self: *Image,
    command_buffer: CommandBuffer,
    format: vk.Format,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
) !void {
    _ = format;

    var barrier = vk.ImageMemoryBarrier{
        .old_layout = old_layout,
        .new_layout = new_layout,
        .src_queue_family_index = self.context.physical_device.graphics_family_index,
        .dst_queue_family_index = self.context.physical_device.graphics_family_index,
        .src_access_mask = undefined,
        .dst_access_mask = undefined,
        .image = self.handle,
        .subresource_range = vk.ImageSubresourceRange{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    };

    var src_stage: vk.PipelineStageFlags = undefined;
    var dst_stage: vk.PipelineStageFlags = undefined;

    if (old_layout == .undefined and new_layout == .transfer_dst_optimal) {
        barrier.src_access_mask = .{};
        barrier.dst_access_mask = .{ .transfer_write_bit = true };

        src_stage = .{ .top_of_pipe_bit = true };
        dst_stage = .{ .transfer_bit = true };
    } else if (old_layout == .transfer_dst_optimal and new_layout == .shader_read_only_optimal) {
        barrier.src_access_mask = .{ .transfer_write_bit = true };
        barrier.dst_access_mask = .{ .shader_read_bit = true };

        src_stage = .{ .transfer_bit = true };
        dst_stage = .{ .fragment_shader_bit = true };
    } else {
        return error.UnsupportedLayoutTransition;
    }

    self.context.device_api.cmdPipelineBarrier(
        command_buffer.handle,
        src_stage,
        dst_stage,
        .{},
        0,
        null,
        0,
        null,
        1,
        @ptrCast(&barrier),
    );
}

pub fn copyFromBuffer(self: *Image, command_buffer: CommandBuffer, buffer: vk.Buffer) void {
    self.context.device_api.cmdCopyBufferToImage(
        command_buffer.handle,
        buffer,
        self.handle,
        .transfer_dst_optimal,
        1,
        @ptrCast(&vk.BufferImageCopy{
            .buffer_offset = 0,
            .buffer_row_length = 0,
            .buffer_image_height = 0,
            .image_subresource = vk.ImageSubresourceLayers{
                .aspect_mask = .{ .color_bit = true },
                .mip_level = 0,
                .base_array_layer = 0,
                .layer_count = 1,
            },
            .image_offset = vk.Offset3D{
                .x = 0,
                .y = 0,
                .z = 0,
            },
            .image_extent = vk.Extent3D{
                .width = self.width,
                .height = self.height,
                .depth = 1,
            },
        }),
    );
}

// utils
fn initView(
    self: *Image,
    view_type: vk.ImageViewType,
    format: vk.Format,
    aspect_flags: vk.ImageAspectFlags,
) !void {
    self.view = try self.context.device_api.createImageView(self.context.device, &vk.ImageViewCreateInfo{
        .image = self.handle,
        .view_type = view_type,
        .format = format,
        .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        .subresource_range = .{
            .aspect_mask = aspect_flags,
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }, null);
}

fn deinitView(self: *Image) void {
    if (self.view != .null_handle) {
        self.context.device_api.destroyImageView(self.context.device, self.view, null);
        self.view = .null_handle;
    }
}
