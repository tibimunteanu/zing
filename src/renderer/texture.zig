const std = @import("std");
const pool = @import("zpool");
const vk = @import("vk.zig");

const Renderer = @import("renderer.zig");
const Image = @import("image.zig");
const Buffer = @import("buffer.zig");
const CommandBuffer = @import("command_buffer.zig");
const ImageResource = @import("../resources/image_resource.zig");

const Allocator = std.mem.Allocator;
const Array = std.BoundedArray;

const Texture = @This();

pub const Use = enum(u8) {
    unknown = 0,
    map_diffuse = 1,
};

pub const Map = struct {
    texture: Handle = Handle.nil,
    use: Use = .unknown,
};

const TexturePool = pool.Pool(16, 16, Texture, struct {
    texture: Texture,
    reference_count: usize,
    auto_release: bool,
}, struct {
    pub fn acquire(self: Handle) !Handle {
        if (self.eql(default)) {
            return default;
        }

        const texture = try self.get();
        const reference_count = textures.getColumnPtrAssumeLive(self, .reference_count);

        reference_count.* +|= 1;

        std.log.info("Texture: Acquire '{s}' ({})", .{ texture.name.slice(), reference_count.* });

        return self;
    }

    pub fn release(self: Handle) void {
        if (self.eql(default)) {
            return;
        }

        if (self.getIfExists()) |texture| {
            const reference_count = textures.getColumnPtrAssumeLive(self, .reference_count);
            const auto_release = textures.getColumnAssumeLive(self, .auto_release);

            if (reference_count.* == 0) {
                std.log.warn("Texture: Release with ref count 0!", .{});
                return;
            }

            reference_count.* -|= 1;

            if (reference_count.* == 0 and auto_release) {
                self.remove();
            } else {
                std.log.info("Texture: Release '{s}' ({})", .{ texture.name.slice(), reference_count.* });
            }
        } else {
            std.log.warn("Texture: Release invalid handle!", .{});
        }
    }

    pub inline fn eql(self: Handle, other: Handle) bool {
        return self.id == other.id;
    }

    pub inline fn isNilOrDefault(self: Handle) bool {
        return self.eql(Handle.nil) or self.eql(default);
    }

    pub inline fn exists(self: Handle) bool {
        return textures.isLiveHandle(self);
    }

    pub inline fn get(self: Handle) !*Texture {
        return try textures.getColumnPtr(self, .texture);
    }

    pub inline fn getIfExists(self: Handle) ?*Texture {
        return textures.getColumnPtrIfLive(self, .texture);
    }

    pub inline fn getOrDefault(self: Handle) *Texture {
        return textures.getColumnPtrIfLive(self, .texture) //
        orelse textures.getColumnPtrAssumeLive(default, .texture);
    }

    pub fn remove(self: Handle) void {
        if (self.getIfExists()) |texture| {
            std.log.info("Texture: Remove '{s}'", .{texture.name.slice()});

            _ = lookup.remove(texture.name.slice());
            textures.removeAssumeLive(self);

            texture.destroy();
        }
    }
});

pub const Handle = TexturePool.Handle;

pub const default_name = "default";
pub var default: Handle = Handle.nil;

var allocator: Allocator = undefined;
var textures: TexturePool = undefined;
var lookup: std.StringHashMap(Handle) = undefined;

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

    lookup = std.StringHashMap(Handle).init(allocator);
    errdefer lookup.deinit();

    try lookup.ensureTotalCapacity(@truncate(textures.capacity()));

    try createDefault();
}

pub fn deinitSystem() void {
    var it = textures.liveHandles();
    while (it.next()) |handle| {
        handle.remove();
    }

    lookup.deinit();
    textures.deinit();
}

pub fn acquire(name: []const u8, options: struct { auto_release: bool }) !Handle {
    if (lookup.get(name)) |handle| {
        return handle.acquire();
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
        errdefer texture.destroy();

        const handle = try textures.add(.{
            .texture = texture,
            .reference_count = 1,
            .auto_release = options.auto_release,
        });
        errdefer textures.removeAssumeLive(handle);

        const texture_ptr = try handle.get(); // NOTE: use name from ptr as key
        try lookup.put(texture_ptr.name.constSlice(), handle);

        std.log.info("Texture: Create '{s}' (1)", .{name});

        return handle;
    }
}

pub fn reload(name: []const u8) !void {
    if (lookup.get(name)) |handle| {
        if (handle.getIfExists()) |texture| {
            var resource = try ImageResource.init(allocator, name);
            defer resource.deinit();

            var new_texture = try create(
                name,
                .r8g8b8a8_srgb,
                resource.image.width,
                resource.image.height,
                resource.image.num_components,
                resource.image.data,
            );

            new_texture.generation = if (texture.generation) |g| g +% 1 else 0;

            texture.destroy();
            texture.* = new_texture;
        }
    } else {
        return error.TextureDoesNotExist;
    }
}

// utils
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
        default_name,
        .r8g8b8a8_srgb,
        size,
        size,
        num_components,
        &pixels,
    );
    texture.generation = null; // NOTE: default texture must have null generation
    errdefer texture.destroy();

    default = try textures.add(.{
        .texture = texture,
        .reference_count = 1,
        .auto_release = false,
    });

    try lookup.put(default_name, default);

    std.log.info("Texture: Create '{s}'", .{default_name});
}

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
    self.generation = 0;

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

    var command_buffer = try CommandBuffer.initAndBeginSingleUse(Renderer.graphics_command_pool);

    try self.image.pipelineImageBarrier(
        &command_buffer,
        .{ .top_of_pipe_bit = true },
        .{},
        .undefined,
        .{ .transfer_bit = true },
        .{ .transfer_write_bit = true },
        .transfer_dst_optimal,
    );

    Renderer.device_api.cmdCopyBufferToImage(
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

    try command_buffer.endSingleUseAndDeinit(Renderer.graphics_queue.handle);

    // create the sampler
    self.sampler = try Renderer.device_api.createSampler(Renderer.device, &vk.SamplerCreateInfo{
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

fn destroy(self: *Texture) void {
    Renderer.device_api.deviceWaitIdle(Renderer.device) catch {};

    self.image.deinit();
    Renderer.device_api.destroySampler(Renderer.device, self.sampler, null);

    self.* = undefined;
}
