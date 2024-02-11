const std = @import("std");
const Engine = @import("../engine.zig").Engine;
const Texture = @import("../resources/texture.zig").Texture;
const Renderer = @import("../renderer/renderer.zig").Renderer;
const stbi = @import("zstbi");
const pool = @import("zpool");
const Allocator = std.mem.Allocator;

pub const TextureRef = struct {
    handle: TextureHandle,
    reference_count: usize,
    auto_release: bool,
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
    default_texture: TextureHandle,
    textures: TexturePool,
    lookup: std.StringHashMap(TextureRef),

    pub fn init(self: *TextureSystem, allocator: Allocator, config: Config) !void {
        self.allocator = allocator;
        self.config = config;

        self.textures = try TexturePool.initMaxCapacity(allocator);
        errdefer self.textures.deinit();

        self.lookup = std.StringHashMap(TextureRef).init(allocator);
        errdefer self.lookup.deinit();

        try self.lookup.ensureTotalCapacity(@truncate(self.textures.capacity()));

        try self.createDefaultTextures();
    }

    pub fn deinit(self: *TextureSystem) void {
        self.releaseAllTextures();
        self.lookup.deinit();
        self.textures.deinit();
    }

    pub fn acquireTexture(self: *TextureSystem, name: []const u8, auto_release: bool) !TextureHandle {
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

            try self.lookup.put(name, TextureRef{
                .handle = handle,
                .reference_count = 1,
                .auto_release = auto_release,
            });

            std.log.info("TextureSystem.acquireTexture(): texture '{s}' was loaded. ref count is 1", .{name});

            return handle;
        }
    }

    // TODO: move reference_count and auto_release to pool and use the lookup only to get handle by name
    // TODO: add functions that work directly with the handle instead of the name
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

                Engine.instance.renderer.destroyTexture(&texture);

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

        var temp_texture = try Engine.instance.renderer.createTexture(
            self.allocator,
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
            tex_dimension,
            tex_dimension,
            4,
            false,
            &pixels,
        );
        errdefer Engine.instance.renderer.destroyTexture(&temp_texture);

        // default texture always has null generation
        temp_texture.generation = null;

        self.default_texture = try self.textures.add(temp_texture);

        try self.lookup.put(default_texture_name, TextureRef{
            .handle = self.default_texture,
            .reference_count = 1,
            .auto_release = false,
        });
    }

    fn releaseAllTextures(self: *TextureSystem) void {
        var it = self.textures.liveHandles();
        while (it.next()) |h| {
            const texture = @constCast(&self.textures.getColumnsAssumeLive(h));
            self.textures.removeAssumeLive(h);
            Engine.instance.renderer.destroyTexture(texture);
        }
    }
};
