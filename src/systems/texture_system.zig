const std = @import("std");
const Texture = @import("../resources/texture.zig").Texture;
const Renderer = @import("../renderer/renderer.zig").Renderer;
const stbi = @import("zstbi");
const pool = @import("zpool");
const Allocator = std.mem.Allocator;

pub const TextureRef = struct {
    handle: TextureHandle,
    reference_count: usize,
    auto_release: bool,

    pub fn init(handle: TextureHandle, auto_release: bool) TextureRef {
        var self: TextureRef = undefined;

        self.handle = handle;
        self.reference_count = 1;
        self.auto_release = auto_release;

        return self;
    }

    pub fn deinit(self: *TextureRef) void {
        self.handle.deinit();
        self.reference_count = 0;
        self.auto_release = false;
    }
};

pub const TexturePool = pool.Pool(16, 16, Texture, Texture);
pub const TextureHandle = TexturePool.Handle;

pub const TextureSystem = struct {
    pub const default_texture_name = "default";

    pub const Config = struct {
        max_texture_count: u32,
    };

    allocator: Allocator,
    config: Config,
    renderer: *Renderer,
    default_texture: TextureHandle,
    textures: TexturePool,
    lookup: std.StringHashMap(TextureRef),

    pub fn init(self: *TextureSystem, allocator: Allocator, config: Config, renderer: *Renderer) !void {
        self.allocator = allocator;
        self.renderer = renderer;
        self.config = config;

        self.textures = try TexturePool.initMaxCapacity(allocator);
        errdefer self.textures.deinit();

        self.lookup = std.StringHashMap(TextureRef).init(allocator);
        errdefer self.lookup.deinit();

        try self.lookup.ensureTotalCapacity(@truncate(self.textures.capacity()));

        try self.createDefaultTextures();
    }

    pub fn deinit(self: *TextureSystem) void {
        self.destroyAcquiredTextures();
        self.destroyDefaultTextures();
        self.lookup.deinit();
        self.textures.deinit();
    }

    pub fn acquireTexture(self: *TextureSystem, name: []const u8, auto_release: bool) !?TextureHandle {
        if (std.mem.eql(u8, name, default_texture_name)) {
            std.log.warn("TextureSystem.acquireTexture() called for default texture. Use getDefaultTexture() instead!", .{});
            return self.default_texture;
        }

        const result = try self.lookup.getOrPut(name);
        if (result.found_existing) {
            const ref = result.value_ptr;

            try self.textures.requireLiveHandle(ref.handle);

            ref.reference_count +|= 1;

            std.log.info(
                "TextureSystem.acquireTexture(): texture '{s}' was acquired. ref count is {}",
                .{ name, ref.reference_count },
            );

            return ref.handle;
        } else {
            var texture = Texture.init();
            try self.loadTexture(name, &texture);

            const handle = try self.textures.add(texture);

            // NOTE: also set the handle id to texture.id
            const id = try self.textures.getColumnPtr(handle, .id);
            id.* = handle.id;

            const ref = TextureRef.init(handle, auto_release);
            try self.lookup.put(name, ref);

            std.log.info(
                "TextureSystem.acquireTexture(): texture '{s}' was loaded. ref count is {}",
                .{ name, ref.reference_count },
            );

            return ref.handle;
        }

        std.log.err("TextureSystem.acquireTexture() failed!");
        return null;
    }

    pub fn releaseTexture(self: *TextureSystem, name: []const u8) void {
        if (std.mem.eql(u8, name, default_texture_name)) {
            // NOTE: ignore calls to release the default texture
            return;
        }

        if (self.lookup.getPtr(name)) |ref| {
            if (ref.reference_count == 0) {
                std.log.warn("TextureSystem.releaseTexture() called for texture with ref count 0!", .{});
                return;
            }

            ref.reference_count -|= 1;

            if (ref.reference_count == 0 and ref.auto_release) {
                var texture = self.textures.getColumnsAssumeLive(ref.handle);

                self.textures.removeAssumeLive(ref.handle);
                _ = self.lookup.remove(name);

                self.renderer.destroyTexture(&texture);
                texture.deinit();

                std.log.info("TextureSystem.releaseTexture(): texture '{s}' was unloaded", .{name});
            } else {
                std.log.info(
                    "TextureSystem.releaseTexture(): texture '{s}' was released. ref count is {}",
                    .{ name, ref.reference_count },
                );
            }
        } else {
            std.log.warn("TextureSystem.releaseTexture() called for non-existent texture!", .{});
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

        var temp_texture = try self.renderer.createTexture(
            self.allocator,
            name,
            image.width,
            image.height,
            @truncate(image.num_components),
            has_transparency,
            image.data,
        );

        temp_texture.generation = texture.generation;
        temp_texture.generation = if (temp_texture.generation) |g| g +% 1 else 0;

        self.renderer.destroyTexture(texture);
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

        var default_texture = try self.renderer.createTexture(
            self.allocator,
            "default",
            tex_dimension,
            tex_dimension,
            4,
            false,
            &pixels,
        );
        errdefer self.renderer.destroyTexture(&default_texture);

        default_texture.generation = null;

        self.default_texture = try self.textures.add(default_texture);

        try self.lookup.put(default_texture_name, TextureRef.init(self.default_texture, false));
    }

    fn destroyAcquiredTextures(self: *TextureSystem) void {
        var it = self.textures.liveHandles();
        while (it.next()) |h| {
            if (h.id != self.default_texture.id) {
                const t = @constCast(&self.textures.getColumnsAssumeLive(h));
                self.renderer.destroyTexture(t);
            }
        }
    }

    fn destroyDefaultTextures(self: *TextureSystem) void {
        if (self.textures.getColumnsIfLive(self.default_texture)) |texture| {
            self.renderer.destroyTexture(@constCast(&texture));
            self.textures.removeAssumeLive(self.default_texture);
        }
    }
};
