const std = @import("std");
const pool = @import("zpool");
const zing = @import("../zing.zig");
const vk = @import("vk.zig");

const Image = @import("image.zig");
const Buffer = @import("buffer.zig");
const CommandBuffer = @import("command_buffer.zig");
const ImageResource = @import("../resources/image_resource.zig");

const Allocator = std.mem.Allocator;
const Array = std.BoundedArray;

const Texture = @This();

pub const TextureUse = enum(u8) {
    unknown = 0,
    map_diffuse = 1,
};

pub const TextureMap = struct {
    texture: TextureHandle = TextureHandle.nil,
    use: TextureUse = .unknown,
};

pub const TexturePool = pool.Pool(16, 16, Texture, struct {
    texture: Texture,
    reference_count: usize,
    auto_release: bool,
});
pub const TextureHandle = TexturePool.Handle;

pub const default_texture_name = "default";

var allocator: Allocator = undefined;
var textures: TexturePool = undefined;
var lookup: std.StringHashMap(TextureHandle) = undefined;
var default_texture: TextureHandle = TextureHandle.nil;

name: Array(u8, 256),
width: u32,
height: u32,
channel_count: u32,
has_transparency: bool,
generation: ?u32,
image: Image,
sampler: vk.Sampler,

pub fn initSystem(ally: Allocator) !void {
    allocator = ally;

    textures = try TexturePool.initMaxCapacity(allocator);
    errdefer textures.deinit();

    lookup = std.StringHashMap(TextureHandle).init(allocator);
    errdefer lookup.deinit();

    try lookup.ensureTotalCapacity(@truncate(textures.capacity()));

    try createDefault();
}

pub fn deinitSystem() void {
    removeAll();
    lookup.deinit();
    textures.deinit();
}

pub fn acquireDefault() TextureHandle {
    return default_texture;
}

pub fn acquireByName(name: []const u8, options: struct { auto_release: bool }) !TextureHandle {
    if (lookup.get(name)) |handle| {
        return acquireByHandle(handle);
    } else {
        var resource = try ImageResource.init(allocator, name);
        defer resource.deinit();

        var texture = try create(
            name,
            .r8g8b8a8_srgb,
            resource.image.width,
            resource.image.height,
            resource.image.num_components,
            resource.image.data,
        );
        texture.generation = if (texture.generation) |g| g +% 1 else 0;
        errdefer texture.destroy();

        const handle = try textures.add(.{
            .texture = texture,
            .reference_count = 1,
            .auto_release = options.auto_release,
        });
        errdefer textures.removeAssumeLive(handle);

        try lookup.put(texture.name.constSlice(), handle);

        std.log.info("Texture: Create texture '{s}'. Ref count: 1", .{name});

        return handle;
    }
}

pub fn acquireByHandle(handle: TextureHandle) !TextureHandle {
    try textures.requireLiveHandle(handle);

    if (handle.id == default_texture.id) {
        std.log.warn("Texture: Cannot acquire default texture. Use getDefaultTexture() instead!", .{});
        return default_texture;
    }

    const texture = textures.getColumnPtrAssumeLive(handle, .texture);
    const reference_count = textures.getColumnPtrAssumeLive(handle, .reference_count);

    reference_count.* +|= 1;

    std.log.info("Texture: Texture '{s}' was acquired. Ref count: {}", .{ texture.name.slice(), reference_count.* });

    return handle;
}

pub fn releaseByName(name: []const u8) void {
    if (lookup.get(name)) |handle| {
        releaseByHandle(handle);
    } else {
        std.log.warn("Texture: Cannot release non-existent texture!", .{});
    }
}

pub fn releaseByHandle(handle: TextureHandle) void {
    if (!textures.isLiveHandle(handle)) {
        std.log.warn("Texture: Cannot release texture with invalid handle!", .{});
        return;
    }

    if (handle.id == default_texture.id) {
        std.log.warn("Texture: Cannot release default texture!", .{});
        return;
    }

    const texture = textures.getColumnPtrAssumeLive(handle, .texture);
    const reference_count = textures.getColumnPtrAssumeLive(handle, .reference_count);
    const auto_release = textures.getColumnAssumeLive(handle, .auto_release);

    if (reference_count.* == 0) {
        std.log.warn("Texture: Cannot release texture with ref count 0!", .{});
        return;
    }

    reference_count.* -|= 1;

    if (reference_count.* == 0 and auto_release) {
        remove(handle);
    } else {
        std.log.info("Texture: Texture '{s}' was released. Ref count: {}", .{ texture.name.slice(), reference_count.* });
    }
}

pub inline fn exists(handle: TextureHandle) bool {
    return textures.isLiveHandle(handle);
}

pub inline fn get(handle: TextureHandle) !*Texture {
    return try textures.getColumnPtr(handle, .texture);
}

pub inline fn getIfExists(handle: TextureHandle) ?*Texture {
    return textures.getColumnPtrIfLive(handle, .texture);
}

// utils
fn create(
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

    // create an image on the gpu
    self.image = try Image.init(
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
        null,
        image_size,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        .{ .bind_on_create = true },
    );
    defer staging_buffer.deinit();

    try staging_buffer.loadData(0, image_size, .{}, pixels);

    var command_buffer = try CommandBuffer.initAndBeginSingleUse(zing.renderer.graphics_command_pool);

    try self.image.pipelineImageBarrier(
        &command_buffer,
        .{ .top_of_pipe_bit = true },
        .{},
        .undefined,
        .{ .transfer_bit = true },
        .{ .transfer_write_bit = true },
        .transfer_dst_optimal,
    );

    zing.renderer.device_api.cmdCopyBufferToImage(
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

    try command_buffer.endSingleUseAndDeinit(zing.renderer.graphics_queue.handle);

    // create the sampler
    self.sampler = try zing.renderer.device_api.createSampler(zing.renderer.device, &vk.SamplerCreateInfo{
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

fn createDefault() !void {
    const size: u32 = 64;
    const num_components: u32 = 4;
    const pixel_count = size * size;

    var pixels: [pixel_count * num_components]u8 = undefined;
    @memset(&pixels, 255);

    for (0..size) |row| {
        for (0..size) |col| {
            const index = (row * size) + col;
            const index_channel = index * num_components;

            if (row % 2 == col % 2) {
                pixels[index_channel + 0] = 0;
                pixels[index_channel + 1] = 0;
            }
        }
    }

    var texture = try create(
        default_texture_name,
        .r8g8b8a8_srgb,
        size,
        size,
        num_components,
        &pixels,
    );
    errdefer texture.destroy();

    default_texture = try textures.add(.{
        .texture = texture,
        .reference_count = 1,
        .auto_release = false,
    });

    try lookup.put(default_texture_name, default_texture);

    std.log.info("Texture: Create default texture '{s}'. Ref count: 1", .{texture.name.slice()});
}

fn destroy(self: *Texture) void {
    zing.renderer.device_api.deviceWaitIdle(zing.renderer.device) catch {};

    self.image.deinit();

    zing.renderer.device_api.destroySampler(zing.renderer.device, self.sampler, null);

    self.* = undefined;
}

fn remove(handle: TextureHandle) void {
    if (textures.getColumnPtrIfLive(handle, .texture)) |texture| {
        std.log.info("Texture: Remove '{s}'", .{texture.name.slice()});

        _ = lookup.remove(texture.name.slice());
        textures.removeAssumeLive(handle);

        texture.destroy();
    }
}

fn removeAll() void {
    var it = textures.liveHandles();
    while (it.next()) |handle| {
        remove(handle);
    }
}
