const std = @import("std");
const pool = @import("zpool");
const vk = @import("vk.zig");

const Renderer = @import("renderer.zig");
const Buffer = @import("buffer.zig");
const CommandBuffer = @import("command_buffer.zig");
const ImageResource = @import("../resources/image_resource.zig");

const Allocator = std.mem.Allocator;
const Array = std.BoundedArray;

const Image = @This();

pub const Config = struct {
    name: []const u8,
    format: vk.Format = .r8g8b8a8_srgb,
    usage: vk.ImageUsageFlags,
    aspect_mask: vk.ImageAspectFlags,
    auto_release: bool,
};

const ImagePool = pool.Pool(16, 16, Image, struct {
    image: Image,
    reference_count: usize,
    auto_release: bool,
});

pub const Handle = ImagePool.Handle;

pub const default_name = "default";
pub var default: Handle = Handle.nil;

var allocator: Allocator = undefined;
var images: ImagePool = undefined;
var lookup: std.StringHashMap(Handle) = undefined;

name: Array(u8, 256),
channel_count: u32,
generation: ?u32,
image: vk.Image,
memory: vk.DeviceMemory,
view: vk.ImageView,
extent: vk.Extent3D,

pub fn initSystem(ally: Allocator) !void {
    allocator = ally;

    images = try ImagePool.initMaxCapacity(allocator);
    errdefer images.deinit();

    lookup = std.StringHashMap(Handle).init(allocator);
    errdefer lookup.deinit();

    try lookup.ensureTotalCapacity(@truncate(images.capacity()));

    try createDefault();
}

pub fn deinitSystem() void {
    var it = images.liveHandles();
    while (it.next()) |handle| {
        remove(handle);
    }

    lookup.deinit();
    images.deinit();
}

pub fn acquire(config: Config) !Handle {
    if (lookup.get(config.name)) |handle| {
        return acquireExisting(handle);
    } else {
        var resource = try ImageResource.init(allocator, config.name);
        defer resource.deinit();

        var image = try create(
            config,
            resource.image.width,
            resource.image.height,
            resource.image.num_components,
            resource.image.data,
        );
        errdefer image.destroy();

        const handle = try images.add(.{
            .image = image,
            .reference_count = 1,
            .auto_release = config.auto_release,
        });
        errdefer images.removeAssumeLive(handle);

        const image_ptr = try get(handle); // NOTE: use name from ptr as key
        try lookup.put(image_ptr.name.constSlice(), handle);

        std.log.info("Image: Create '{s}' (1)", .{config.name});

        return handle;
    }
}

pub fn reload(name: []const u8) !void {
    if (lookup.get(name)) |handle| {
        if (getIfExists(handle)) |image| {
            var resource = try ImageResource.init(allocator, name);
            defer resource.deinit();

            var new_image = try create(
                name,
                .r8g8b8a8_srgb,
                resource.image.width,
                resource.image.height,
                resource.image.num_components,
                resource.image.data,
            );

            new_image.generation = if (image.generation) |g| g +% 1 else 0;

            image.destroy();
            image.* = new_image;
        }
    } else {
        return error.ImageDoesNotExist;
    }
}

// handle
pub fn acquireExisting(handle: Handle) !Handle {
    if (eql(handle, default)) {
        return default;
    }

    const image = try get(handle);
    const reference_count = images.getColumnPtrAssumeLive(handle, .reference_count);

    reference_count.* +|= 1;

    std.log.info("Image: Acquire '{s}' ({})", .{ image.name.slice(), reference_count.* });

    return handle;
}

pub fn release(handle: Handle) void {
    if (eql(handle, default)) {
        return;
    }

    if (getIfExists(handle)) |image| {
        const reference_count = images.getColumnPtrAssumeLive(handle, .reference_count);
        const auto_release = images.getColumnAssumeLive(handle, .auto_release);

        if (reference_count.* == 0) {
            std.log.warn("Image: Release with ref count 0!", .{});
            return;
        }

        reference_count.* -|= 1;

        if (auto_release and reference_count.* == 0) {
            remove(handle);
        } else {
            std.log.info("Image: Release '{s}' ({})", .{ image.name.slice(), reference_count.* });
        }
    } else {
        std.log.warn("Image: Release invalid handle!", .{});
    }
}

pub inline fn eql(left: Handle, right: Handle) bool {
    return left.id == right.id;
}

pub inline fn isNilOrDefault(handle: Handle) bool {
    return eql(handle, Handle.nil) or eql(handle, default);
}

pub inline fn exists(handle: Handle) bool {
    return images.isLiveHandle(handle);
}

pub inline fn get(handle: Handle) !*Image {
    return try images.getColumnPtr(handle, .image);
}

pub inline fn getIfExists(handle: Handle) ?*Image {
    return images.getColumnPtrIfLive(handle, .image);
}

pub inline fn getOrDefault(handle: Handle) *Image {
    return images.getColumnPtrIfLive(handle, .image) //
    orelse images.getColumnPtrAssumeLive(default, .image);
}

pub fn remove(handle: Handle) void {
    if (getIfExists(handle)) |image| {
        std.log.info("Image: Remove '{s}'", .{image.name.slice()});

        _ = lookup.remove(image.name.slice());
        images.removeAssumeLive(handle);

        image.destroy();
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

    var image = try create(
        Config{
            .name = default_name,
            .format = .r8g8b8a8_srgb,
            .usage = .{
                .transfer_src_bit = true,
                .transfer_dst_bit = true,
                .color_attachment_bit = true,
                .sampled_bit = true,
            },
            .aspect_mask = .{ .color_bit = true },
            .auto_release = false,
        },
        size,
        size,
        num_components,
        &pixels,
    );
    image.generation = null; // NOTE: default image must have null generation
    errdefer image.destroy();

    default = try images.add(.{
        .image = image,
        .reference_count = 1,
        .auto_release = false,
    });

    try lookup.put(default_name, default);

    std.log.info("Image: Create '{s}'", .{default_name});
}

// NOTE: swapchain can't use acquire and release because it's created before the image system
pub fn create(
    config: Config,
    width: u32,
    height: u32,
    num_components: u32,
    pixels: ?[]const u8,
) !Image {
    var self: Image = undefined;

    self.name = try Array(u8, 256).fromSlice(config.name);
    self.extent = vk.Extent3D{
        .width = width,
        .height = height,
        .depth = 1,
    };
    self.channel_count = num_components;
    self.generation = 0;

    self.image = .null_handle;
    self.memory = .null_handle;
    self.view = .null_handle;

    errdefer self.destroy();

    // create an image on the gpu
    self.image = try Renderer.device_api.createImage(Renderer.device, &vk.ImageCreateInfo{
        .flags = .{},
        .image_type = .@"2d",
        .format = config.format,
        .extent = self.extent,
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1_bit" = true },
        .tiling = .optimal,
        .usage = config.usage,
        .sharing_mode = .exclusive,
        .queue_family_index_count = 0,
        .p_queue_family_indices = null,
        .initial_layout = .undefined,
    }, null);

    const memory_requirements = Renderer.device_api.getImageMemoryRequirements(Renderer.device, self.image);
    self.memory = try Renderer.allocate(memory_requirements, .{ .device_local_bit = true });
    try Renderer.device_api.bindImageMemory(Renderer.device, self.image, self.memory, 0);

    self.view = try Renderer.device_api.createImageView(Renderer.device, &vk.ImageViewCreateInfo{
        .image = self.image,
        .view_type = .@"2d",
        .format = config.format,
        .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        .subresource_range = .{
            .aspect_mask = config.aspect_mask,
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }, null);

    if (pixels) |data| {
        // copy the pixels to the gpu
        const image_size: vk.DeviceSize = width * height * num_components;

        var staging_buffer = try Buffer.init(
            null,
            image_size,
            .{ .transfer_src_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
            .{ .bind_on_create = true },
        );
        defer staging_buffer.deinit();

        try staging_buffer.loadData(0, image_size, .{}, data);

        var command_buffer = try CommandBuffer.initAndBeginSingleUse(Renderer.graphics_command_pool);

        try self.pipelineImageBarrier(
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
            self.image,
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
                .image_extent = self.extent,
            }),
        );

        try self.pipelineImageBarrier(
            &command_buffer,
            .{ .transfer_bit = true },
            .{ .transfer_write_bit = true },
            .transfer_dst_optimal,
            .{ .fragment_shader_bit = true },
            .{ .shader_read_bit = true },
            .shader_read_only_optimal,
        );

        try command_buffer.endSingleUseAndDeinit(Renderer.graphics_queue.handle);
    }

    return self;
}

pub fn destroy(self: *Image) void {
    Renderer.waitIdle();

    if (self.view != .null_handle) {
        Renderer.device_api.destroyImageView(Renderer.device, self.view, null);
    }
    if (self.image != .null_handle) {
        Renderer.device_api.destroyImage(Renderer.device, self.image, null);
    }
    if (self.memory != .null_handle) {
        Renderer.device_api.freeMemory(Renderer.device, self.memory, null);
    }

    self.* = undefined;
}

fn pipelineImageBarrier(
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
        .image = self.image,
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
