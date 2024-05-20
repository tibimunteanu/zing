const std = @import("std");
const vk = @import("vk.zig");
const Engine = @import("../engine.zig");
const Context = @import("context.zig");
const Image = @import("image.zig");
const Buffer = @import("buffer.zig");
const CommandBuffer = @import("command_buffer.zig");

const Array = std.BoundedArray;

const Texture = @This();

name: Array(u8, 256),
width: u32,
height: u32,
channel_count: u32,
has_transparency: bool,
generation: ?u32,
image: Image,
sampler: vk.Sampler,

pub fn init(
    name: []const u8,
    format: vk.Format,
    width: u32,
    height: u32,
    num_components: u32,
    pixels: []const u8,
) !Texture {
    var self: Texture = undefined;

    self.name = try Array(u8, 256).fromSlice(name);
    self.width = width;
    self.height = height;
    self.channel_count = num_components;
    self.generation = null;

    const image_size: vk.DeviceSize = width * height * num_components;

    self.has_transparency = false;
    var i: u32 = 0;
    while (i < image_size) : (i += num_components) {
        const a: u8 = pixels[i + 3];
        if (a < 255) {
            self.has_transparency = true;
            break;
        }
    }

    const ctx = Engine.instance.renderer.context;

    // create an image on the gpu
    self.image = try Image.init(
        ctx,
        vk.MemoryPropertyFlags{ .device_local_bit = true },
        &vk.ImageCreateInfo{
            .flags = .{},
            .image_type = .@"2d",
            .format = format,
            .extent = .{
                .width = width,
                .height = height,
                .depth = 1,
            },
            .mip_levels = 1,
            .array_layers = 1,
            .samples = .{ .@"1_bit" = true },
            .tiling = .optimal,
            .usage = .{
                .transfer_src_bit = true,
                .transfer_dst_bit = true,
                .color_attachment_bit = true,
                .sampled_bit = true,
            },
            .sharing_mode = .exclusive,
            .queue_family_index_count = 0,
            .p_queue_family_indices = null,
            .initial_layout = .undefined,
        },
        @constCast(&vk.ImageViewCreateInfo{
            .image = .null_handle,
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
        }),
    );
    errdefer self.image.deinit();

    // copy the pixels to the gpu
    var staging_buffer = try Buffer.init(
        ctx,
        image_size,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        .{ .bind_on_create = true },
    );
    defer staging_buffer.deinit();

    try staging_buffer.loadData(0, image_size, .{}, pixels);

    var command_buffer = try CommandBuffer.initAndBeginSingleUse(ctx, Engine.instance.renderer.graphics_command_pool);

    try self.image.pipelineImageBarrier(
        &command_buffer,
        .{ .top_of_pipe_bit = true },
        .{},
        .undefined,
        .{ .transfer_bit = true },
        .{ .transfer_write_bit = true },
        .transfer_dst_optimal,
    );

    ctx.device_api.cmdCopyBufferToImage(
        command_buffer.handle,
        staging_buffer.handle,
        self.image.handle,
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
            .image_extent = self.image.extent,
        }),
    );

    try self.image.pipelineImageBarrier(
        &command_buffer,
        .{ .transfer_bit = true },
        .{ .transfer_write_bit = true },
        .transfer_dst_optimal,
        .{ .fragment_shader_bit = true },
        .{ .shader_read_bit = true },
        .shader_read_only_optimal,
    );

    try command_buffer.endSingleUseAndDeinit(ctx.graphics_queue.handle);

    // create the sampler
    self.sampler = try ctx.device_api.createSampler(ctx.device, &vk.SamplerCreateInfo{
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

    return self;
}

pub fn deinit(self: *Texture) void {
    const ctx = Engine.instance.renderer.context;

    ctx.device_api.deviceWaitIdle(ctx.device) catch {};

    self.image.deinit();

    ctx.device_api.destroySampler(ctx.device, self.sampler, null);

    self.* = undefined;
}
