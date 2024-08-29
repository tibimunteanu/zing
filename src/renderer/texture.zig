const std = @import("std");
const pool = @import("zpool");
const vk = @import("vk.zig");

const Renderer = @import("renderer.zig");
const Image = @import("image.zig");
const TextureLoader = @import("../loaders/texture_loader.zig");

const Allocator = std.mem.Allocator;
const Array = std.BoundedArray;

const Texture = @This();

// TODO: extract more configs
pub const Config = struct {
    name: []const u8,
    image_name: []const u8,
    filter_mode: []const u8,
    auto_release: bool,
};

const TexturePool = pool.Pool(16, 16, Texture, struct {
    texture: Texture,
    reference_count: usize,
    auto_release: bool,
});

pub const Handle = TexturePool.Handle;

pub const default_name = "default";
pub var default: Handle = Handle.nil;

var allocator: Allocator = undefined;
var textures: TexturePool = undefined;
var lookup: std.StringHashMap(Handle) = undefined;

name: Array(u8, 256),
image: Image.Handle,
sampler: vk.Sampler,
generation: ?u32,

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
        remove(handle);
    }

    lookup.deinit();
    textures.deinit();
}

pub fn acquire(name: []const u8) !Handle {
    if (lookup.get(name)) |handle| {
        return acquireExisting(handle);
    } else {
        var resource = try TextureLoader.init(allocator, name);
        defer resource.deinit();

        var texture = try create(resource.config.value);
        errdefer texture.destroy();

        const handle = try textures.add(.{
            .texture = texture,
            .reference_count = 1,
            .auto_release = resource.config.value.auto_release,
        });
        errdefer textures.removeAssumeLive(handle);

        const texture_ptr = try get(handle); // NOTE: use name from ptr as key
        try lookup.put(texture_ptr.name.constSlice(), handle);

        std.log.info("Texture: Create '{s}' (1)", .{name});

        return handle;
    }
}

pub fn reload(name: []const u8) !void {
    if (lookup.get(name)) |handle| {
        if (handle.getIfExists()) |texture| {
            var resource = try TextureLoader.init(allocator, name);
            defer resource.deinit();

            var new_texture = try create(resource.config.value);

            new_texture.generation = if (texture.generation) |g| g +% 1 else 0;

            texture.destroy();
            texture.* = new_texture;
        }
    } else {
        return error.TextureDoesNotExist;
    }
}

// handle
pub fn acquireExisting(handle: Handle) !Handle {
    if (eql(handle, default)) {
        return default;
    }

    const texture = try get(handle);
    const reference_count = textures.getColumnPtrAssumeLive(handle, .reference_count);

    reference_count.* +|= 1;

    std.log.info("Texture: Acquire '{s}' ({})", .{ texture.name.slice(), reference_count.* });

    return handle;
}

pub fn release(handle: Handle) void {
    if (eql(handle, default)) {
        return;
    }

    if (getIfExists(handle)) |texture| {
        const reference_count = textures.getColumnPtrAssumeLive(handle, .reference_count);
        const auto_release = textures.getColumnAssumeLive(handle, .auto_release);

        if (reference_count.* == 0) {
            std.log.warn("Texture: Release with ref count 0!", .{});
            return;
        }

        reference_count.* -|= 1;

        if (auto_release and reference_count.* == 0) {
            remove(handle);
        } else {
            std.log.info("Texture: Release '{s}' ({})", .{ texture.name.slice(), reference_count.* });
        }
    } else {
        std.log.warn("Texture: Release invalid handle!", .{});
    }
}

pub inline fn eql(left: Handle, right: Handle) bool {
    return left.id == right.id;
}

pub inline fn isNilOrDefault(handle: Handle) bool {
    return eql(handle, Handle.nil) or eql(handle, default);
}

pub inline fn exists(handle: Handle) bool {
    return textures.isLiveHandle(handle);
}

pub inline fn get(handle: Handle) !*Texture {
    return try textures.getColumnPtr(handle, .texture);
}

pub inline fn getIfExists(handle: Handle) ?*Texture {
    return textures.getColumnPtrIfLive(handle, .texture);
}

pub inline fn getOrDefault(handle: Handle) *Texture {
    return textures.getColumnPtrIfLive(handle, .texture) //
    orelse textures.getColumnPtrAssumeLive(default, .texture);
}

pub fn remove(handle: Handle) void {
    if (getIfExists(handle)) |texture| {
        std.log.info("Texture: Remove '{s}'", .{texture.name.slice()});

        _ = lookup.remove(texture.name.slice());
        textures.removeAssumeLive(handle);

        texture.destroy();
    }
}

// utils
fn createDefault() !void {
    var texture = try create(Config{
        .name = default_name,
        .image_name = Image.default_name,
        .filter_mode = "linear",
        .auto_release = false,
    });
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

fn create(config: Config) !Texture {
    var self: Texture = undefined;

    self.name = try Array(u8, 256).fromSlice(config.name);

    self.image = Image.acquire(.{
        .name = config.image_name,
        .format = .r8g8b8a8_srgb,
        .usage = .{
            .transfer_src_bit = true,
            .transfer_dst_bit = true,
            .color_attachment_bit = true,
            .sampled_bit = true,
        },
        .aspect_mask = .{ .color_bit = true },
        .auto_release = config.auto_release,
    }) catch Image.default;

    const filter_mode = try parseFilterMode(config.filter_mode);

    self.sampler = try Renderer.device_api.createSampler(Renderer.device, &vk.SamplerCreateInfo{
        .mag_filter = filter_mode,
        .min_filter = filter_mode,
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
    Renderer.waitIdle();

    Renderer.device_api.destroySampler(Renderer.device, self.sampler, null);

    if (!Image.isNilOrDefault(self.image)) {
        Image.release(self.image);
    }

    self.* = undefined;
}

// parse from config
inline fn parseFilterMode(filter_mode: []const u8) !vk.Filter {
    return std.meta.stringToEnum(vk.Filter, filter_mode) orelse error.UnknownFilterMode;
}
