const std = @import("std");
const Engine = @import("../engine.zig").Engine;
const Texture = @import("../resources/texture.zig").Texture;
const Renderer = @import("../renderer/renderer.zig").Renderer;
const stbi = @import("zstbi");
const pool = @import("zpool");
const Allocator = std.mem.Allocator;

pub const TexturePool = pool.Pool(16, 16, Texture, Texture);
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
            var texture = Texture.init();
            texture.reference_count = 1;
            texture.auto_release = auto_release;

            try self.loadTexture(name, &texture);

            const handle = try self.textures.add(texture);
            errdefer self.textures.removeAssumeLive(handle);

            try self.lookup.put(name, handle);
            errdefer self.lookup.remove(name);

            std.log.info("TextureSystem: Texture '{s}' was loaded. Ref count: {}", .{ name, texture.reference_count });

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

        const name = self.textures.getColumnAssumeLive(handle, .name);
        const reference_count = self.textures.getColumnPtrAssumeLive(handle, .reference_count);

        reference_count.* +|= 1;

        std.log.info("TextureSystem: Texture '{s}' was acquired. Ref count: {}", .{ name, reference_count.* });

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

        const name = self.textures.getColumnAssumeLive(handle, .name);
        const reference_count = self.textures.getColumnPtrAssumeLive(handle, .reference_count);
        const auto_release = self.textures.getColumnAssumeLive(handle, .auto_release);

        if (reference_count.* == 0) {
            std.log.warn("TextureSystem: Cannot release texture with ref count 0!", .{});
            return;
        }

        reference_count.* -|= 1;

        if (reference_count.* == 0 and auto_release) {
            self.unloadTexture(handle);

            std.log.info("TextureSystem: Texture '{s}' was unloaded", .{name});
        } else {
            std.log.info("TextureSystem: Texture '{s}' was released. Ref count: {}", .{ name, reference_count.* });
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

        var temp_texture = try Engine.instance.renderer.createTexture(
            self.allocator,
            name,
            image.width,
            image.height,
            @truncate(image.num_components),
            has_transparency,
            image.data,
        );
        errdefer Engine.instance.renderer.destroyTexture(&temp_texture);

        // TODO: just use handle update instead of manual generation
        temp_texture.generation = texture.generation;
        temp_texture.generation = if (temp_texture.generation) |g| g +% 1 else 0;
        temp_texture.reference_count = texture.reference_count;
        temp_texture.auto_release = texture.auto_release;

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

        var temp_texture = try Engine.instance.renderer.createTexture(
            self.allocator,
            default_texture_name,
            tex_dimension,
            tex_dimension,
            4,
            false,
            &pixels,
        );
        errdefer Engine.instance.renderer.destroyTexture(&temp_texture);

        // default texture always has null generation
        temp_texture.generation = null;
        temp_texture.reference_count = 1;
        temp_texture.auto_release = false;

        self.default_texture = try self.textures.add(temp_texture);

        try self.lookup.put(default_texture_name, self.default_texture);
    }

    fn unloadTexture(self: *TextureSystem, handle: TextureHandle) void {
        if (self.textures.getColumnsIfLive(handle)) |texture| {
            self.textures.removeAssumeLive(handle);
            _ = self.lookup.remove(texture.name);
            Engine.instance.renderer.destroyTexture(@constCast(&texture));
        }
    }

    fn unloadAllTextures(self: *TextureSystem) void {
        var it = self.textures.liveHandles();
        while (it.next()) |handle| {
            self.unloadTexture(handle);
        }
    }
};
