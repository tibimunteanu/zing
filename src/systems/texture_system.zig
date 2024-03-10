const std = @import("std");
const pool = @import("zpool");

const Engine = @import("../engine.zig");
const Renderer = @import("../renderer/renderer.zig");
const Texture = @import("../renderer/texture.zig");
const ImageResource = @import("../resources/image_resource.zig");

const Allocator = std.mem.Allocator;

const TextureSystem = @This();

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
    self.unloadAllTextures();
    self.lookup.deinit();
    self.textures.deinit();
}

pub fn acquireTextureByName(self: *TextureSystem, name: []const u8, options: struct { auto_release: bool }) !TextureHandle {
    if (self.lookup.get(name)) |handle| {
        return self.acquireTextureByHandle(handle);
    } else {
        var texture = Texture.init();
        try self.loadTexture(name, &texture);

        const handle = try self.textures.add(.{
            .texture = texture,
            .reference_count = 1,
            .auto_release = options.auto_release,
        });
        errdefer self.textures.removeAssumeLive(handle);

        try self.lookup.put(name, handle);
        errdefer self.lookup.remove(name);

        std.log.info("TextureSystem: Texture '{s}' was loaded. Ref count: 1", .{name});

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
        self.unloadTexture(handle);
    } else {
        std.log.info("TextureSystem: Texture '{s}' was released. Ref count: {}", .{ texture.name.slice(), reference_count.* });
    }
}

pub fn getDefaultTexture(self: TextureSystem) TextureHandle {
    return self.default_texture;
}

// utils
fn createDefaultTextures(self: *TextureSystem) !void {
    const tex_dimension: u32 = 64;
    const channels: u32 = 4;
    const pixel_count = tex_dimension * tex_dimension;

    var pixels: [pixel_count * channels]u8 = undefined;
    @memset(&pixels, 255);

    for (0..tex_dimension) |row| {
        for (0..tex_dimension) |col| {
            const index = (row * tex_dimension) + col;
            const index_channel = index * channels;

            if (row % 2 == col % 2) {
                pixels[index_channel + 0] = 0;
                pixels[index_channel + 1] = 0;
            }
        }
    }

    var texture = Texture.init();
    texture.name = try Texture.Name.fromSlice(default_texture_name);
    texture.width = tex_dimension;
    texture.height = tex_dimension;
    texture.channel_count = 4;
    texture.has_transparency = false;
    texture.generation = null; // NOTE: default texture always has null generation

    try Engine.instance.renderer.createTexture(&texture, &pixels);
    errdefer Engine.instance.renderer.destroyTexture(&texture);

    self.default_texture = try self.textures.add(.{
        .texture = texture,
        .reference_count = 1,
        .auto_release = false,
    });

    try self.lookup.put(default_texture_name, self.default_texture);
}

fn loadTexture(self: *TextureSystem, name: []const u8, texture: *Texture) !void {
    var resource = try ImageResource.init(self.allocator, name);
    defer resource.deinit();

    var has_transparency = false;
    var i: u32 = 0;
    const total_size: usize = resource.image.width * resource.image.height * resource.image.num_components;
    while (i < total_size) : (i += resource.image.num_components) {
        const a: u8 = resource.image.data[i + 3];
        if (a < 255) {
            has_transparency = true;
            break;
        }
    }

    var temp_texture = Texture.init();
    temp_texture.name = try Texture.Name.fromSlice(name);
    temp_texture.width = resource.image.width;
    temp_texture.height = resource.image.height;
    temp_texture.channel_count = resource.image.num_components;
    temp_texture.has_transparency = has_transparency;
    temp_texture.generation = if (texture.generation) |g| g +% 1 else 0;

    try Engine.instance.renderer.createTexture(&temp_texture, resource.image.data);
    errdefer Engine.instance.renderer.destroyTexture(&temp_texture);

    Engine.instance.renderer.destroyTexture(texture);
    texture.* = temp_texture;
}

fn unloadTexture(self: *TextureSystem, handle: TextureHandle) void {
    if (self.textures.getColumnPtrIfLive(handle, .texture)) |texture| {
        const texture_name = texture.name; // NOTE: take a copy of the name

        Engine.instance.renderer.destroyTexture(texture);

        self.textures.removeAssumeLive(handle); // NOTE: this calls texture.deinit()
        _ = self.lookup.remove(texture_name.slice());

        std.log.info("TextureSystem: Texture '{s}' was unloaded", .{texture_name.slice()});
    }
}

fn unloadAllTextures(self: *TextureSystem) void {
    var it = self.textures.liveHandles();
    while (it.next()) |handle| {
        self.unloadTexture(handle);
    }
}
