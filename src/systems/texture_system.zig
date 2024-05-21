const std = @import("std");
const pool = @import("zpool");

const Texture = @import("../renderer/texture.zig");
const ImageResource = @import("../resources/image_resource.zig");

const Allocator = std.mem.Allocator;
const Array = std.BoundedArray;

const TextureSystem = @This();

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

allocator: Allocator,
default_texture: TextureHandle,
textures: TexturePool,
lookup: std.StringHashMap(TextureHandle),

pub fn init(self: *TextureSystem, allocator: Allocator) !void {
    self.allocator = allocator;

    self.textures = try TexturePool.initMaxCapacity(allocator);
    errdefer self.textures.deinit();

    self.lookup = std.StringHashMap(TextureHandle).init(allocator);
    errdefer self.lookup.deinit();

    try self.lookup.ensureTotalCapacity(@truncate(self.textures.capacity()));

    try self.createDefaultTextures();
}

pub fn deinit(self: *TextureSystem) void {
    self.destroyAllTextures();
    self.lookup.deinit();
    self.textures.deinit();
}

pub fn acquireDefaultTexture(self: *const TextureSystem) TextureHandle {
    return self.default_texture;
}

pub fn acquireTextureByName(self: *TextureSystem, name: []const u8, options: struct { auto_release: bool }) !TextureHandle {
    if (self.lookup.get(name)) |handle| {
        return self.acquireTextureByHandle(handle);
    } else {
        var resource = try ImageResource.init(self.allocator, name);
        defer resource.deinit();

        var texture = try Texture.init(
            name,
            .r8g8b8a8_srgb,
            resource.image.width,
            resource.image.height,
            resource.image.num_components,
            resource.image.data,
        );
        texture.generation = if (texture.generation) |g| g +% 1 else 0;
        errdefer texture.deinit();

        const handle = try self.textures.add(.{
            .texture = texture,
            .reference_count = 1,
            .auto_release = options.auto_release,
        });
        errdefer self.textures.removeAssumeLive(handle);

        try self.lookup.put(texture.name.constSlice(), handle);

        std.log.info("TextureSystem: Create texture '{s}'. Ref count: 1", .{name});

        return handle;
    }
}

pub fn acquireTextureByHandle(self: *TextureSystem, handle: TextureHandle) !TextureHandle {
    try self.textures.requireLiveHandle(handle);

    if (handle.id == self.default_texture.id) {
        std.log.warn("TextureSystem: Cannot acquire default texture. Use getDefaultTexture() instead!", .{});
        return self.default_texture;
    }

    const texture = self.textures.getColumnPtrAssumeLive(handle, .texture);
    const reference_count = self.textures.getColumnPtrAssumeLive(handle, .reference_count);

    reference_count.* +|= 1;

    std.log.info("TextureSystem: Texture '{s}' was acquired. Ref count: {}", .{ texture.name.slice(), reference_count.* });

    return handle;
}

pub fn releaseTextureByName(self: *TextureSystem, name: []const u8) void {
    if (self.lookup.get(name)) |handle| {
        self.releaseTextureByHandle(handle);
    } else {
        std.log.warn("TextureSystem: Cannot release non-existent texture!", .{});
    }
}

pub fn releaseTextureByHandle(self: *TextureSystem, handle: TextureHandle) void {
    if (!self.textures.isLiveHandle(handle)) {
        std.log.warn("TextureSystem: Cannot release texture with invalid handle!", .{});
        return;
    }

    if (handle.id == self.default_texture.id) {
        std.log.warn("TextureSystem: Cannot release default texture!", .{});
        return;
    }

    const texture = self.textures.getColumnPtrAssumeLive(handle, .texture);
    const reference_count = self.textures.getColumnPtrAssumeLive(handle, .reference_count);
    const auto_release = self.textures.getColumnAssumeLive(handle, .auto_release);

    if (reference_count.* == 0) {
        std.log.warn("TextureSystem: Cannot release texture with ref count 0!", .{});
        return;
    }

    reference_count.* -|= 1;

    if (reference_count.* == 0 and auto_release) {
        self.destroyTexture(handle);
    } else {
        std.log.info("TextureSystem: Texture '{s}' was released. Ref count: {}", .{ texture.name.slice(), reference_count.* });
    }
}

pub inline fn exists(self: *TextureSystem, handle: TextureHandle) bool {
    return self.textures.isLiveHandle(handle);
}

pub inline fn get(self: *TextureSystem, handle: TextureHandle) !*Texture {
    return try self.textures.getColumnPtr(handle, .texture);
}

pub inline fn getIfExists(self: *TextureSystem, handle: TextureHandle) ?*Texture {
    return self.textures.getColumnPtrIfLive(handle, .texture);
}

// utils
fn createDefaultTextures(self: *TextureSystem) !void {
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

    var texture = try Texture.init(
        default_texture_name,
        .r8g8b8a8_srgb,
        size,
        size,
        num_components,
        &pixels,
    );
    errdefer texture.deinit();

    self.default_texture = try self.textures.add(.{
        .texture = texture,
        .reference_count = 1,
        .auto_release = false,
    });

    try self.lookup.put(default_texture_name, self.default_texture);

    std.log.info("TextureSystem: Create default texture '{s}'. Ref count: 1", .{texture.name.slice()});
}

fn destroyTexture(self: *TextureSystem, handle: TextureHandle) void {
    if (self.textures.getColumnPtrIfLive(handle, .texture)) |texture| {
        std.log.info("TextureSystem: Destroy texture '{s}'", .{texture.name.slice()});

        _ = self.lookup.remove(texture.name.slice());
        self.textures.removeAssumeLive(handle); // NOTE: this calls texture.deinit()
    }
}

fn destroyAllTextures(self: *TextureSystem) void {
    var it = self.textures.liveHandles();
    while (it.next()) |handle| {
        self.destroyTexture(handle);
    }
}
