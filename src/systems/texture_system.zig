const std = @import("std");
const Engine = @import("../engine.zig").Engine;
const Texture = @import("../resources/texture.zig").Texture;
const TextureName = @import("../resources/texture.zig").TextureName;
const Renderer = @import("../renderer/renderer.zig").Renderer;
const stbi = @import("zstbi");
const pool = @import("zpool");
const Allocator = std.mem.Allocator;

pub const TexturePool = pool.Pool(16, 16, Texture, struct {
    texture: Texture,
    reference_count: usize,
    auto_release: bool,
});
pub const TextureHandle = TexturePool.Handle;

pub const TextureSystem = struct {
    pub const default_texture_name = "default";

    pub const Config = struct {
        max_texture_count: u32,
    };

    allocator: Allocator,
    config: Config,
    default_texture: TextureHandle,
    textures: TexturePool,
    lookup: std.StringHashMap(TextureHandle),

    pub fn init(self: *TextureSystem, allocator: Allocator, config: Config) !void {
        self.allocator = allocator;
        self.config = config;

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

    pub fn acquireTextureByName(self: *TextureSystem, name: []const u8, auto_release: bool) !TextureHandle {
        if (self.lookup.get(name)) |handle| {
            return self.acquireTextureByHandle(handle);
        } else {
            var texture = try Texture.init();
            try self.loadTexture(name, &texture);

            const handle = try self.textures.add(.{
                .texture = texture,
                .reference_count = 1,
                .auto_release = auto_release,
            });
            errdefer self.textures.removeAssumeLive(handle);

            try self.lookup.put(name, handle);
            errdefer self.lookup.remove(name);

            std.log.info("TextureSystem: Texture '{s}' was loaded. Ref count: 1", .{name});

            return handle;
        }
    }

    pub fn releaseTextureByName(self: *TextureSystem, name: []const u8) void {
        if (self.lookup.get(name)) |handle| {
            self.releaseTextureByHandle(handle);
        } else {
            std.log.warn("TextureSystem: Cannot release non-existent texture!", .{});
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
    fn loadTexture(self: *TextureSystem, name: []const u8, texture: *Texture) !void {
        stbi.init(self.allocator);
        defer stbi.deinit();

        const path_format = "assets/textures/{s}.{s}";

        const texture_path = try std.fmt.allocPrintZ(self.allocator, path_format, .{ name, "png" });
        defer self.allocator.free(texture_path);

        stbi.setFlipVerticallyOnLoad(true);

        var image = try stbi.Image.loadFromFile(texture_path, 4);
        defer image.deinit();

        var has_transparency = false;
        var i: u32 = 0;
        const total_size: usize = image.width * image.height * image.num_components;
        while (i < total_size) : (i += image.num_components) {
            const a: u8 = image.data[i + 3];
            if (a < 255) {
                has_transparency = true;
                break;
            }
        }

        var temp_texture = try Texture.init();
        temp_texture.name = try TextureName.fromSlice(name);
        temp_texture.width = image.width;
        temp_texture.height = image.height;
        temp_texture.channel_count = @truncate(image.num_components);
        temp_texture.has_transparency = has_transparency;
        temp_texture.generation = if (texture.generation) |g| g +% 1 else 0;

        try Engine.instance.renderer.createTexture(
            self.allocator,
            &temp_texture,
            image.data,
        );
        errdefer Engine.instance.renderer.destroyTexture(&temp_texture);

        Engine.instance.renderer.destroyTexture(texture);
        texture.* = temp_texture;
    }

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

        var texture = try Texture.init();
        texture.name = try TextureName.fromSlice(default_texture_name);
        texture.width = tex_dimension;
        texture.height = tex_dimension;
        texture.channel_count = 4;
        texture.has_transparency = false;
        texture.generation = null; // NOTE: default texture always has null generation

        try Engine.instance.renderer.createTexture(
            self.allocator,
            &texture,
            &pixels,
        );
        errdefer Engine.instance.renderer.destroyTexture(&texture);

        self.default_texture = try self.textures.add(.{
            .texture = texture,
            .reference_count = 1,
            .auto_release = false,
        });

        try self.lookup.put(default_texture_name, self.default_texture);
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
};
