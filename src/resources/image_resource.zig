const std = @import("std");
const stbi = @import("zstbi");
const math = @import("zmath");

const TextureHandle = @import("../systems/texture_system.zig").TextureHandle;

const Allocator = std.mem.Allocator;

pub const ImageResource = struct {
    allocator: Allocator,
    name: []const u8,
    full_path: []const u8,
    image: stbi.Image,

    pub fn init(allocator: Allocator, name: []const u8) !ImageResource {
        stbi.init(allocator);

        const path_format = "assets/textures/{s}{s}";

        const texture_path = try std.fmt.allocPrintZ(allocator, path_format, .{ name, ".png" });
        defer allocator.free(texture_path);

        stbi.setFlipVerticallyOnLoad(true);

        var image = try stbi.Image.loadFromFile(texture_path, 4);
        errdefer image.deinit();

        return .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .full_path = try allocator.dupe(u8, texture_path),
            .image = image,
        };
    }

    pub fn deinit(self: *ImageResource) void {
        self.allocator.free(self.name);
        self.allocator.free(self.full_path);
        self.image.deinit();
        self.* = undefined;

        stbi.deinit();
    }
};

pub const TextureName = std.BoundedArray(u8, 256);

pub const Texture = struct {
    name: TextureName = .{},
    width: u32 = 0,
    height: u32 = 0,
    channel_count: u32 = 0,
    has_transparency: bool = false,
    generation: ?u32 = null,
    internal_data: ?*anyopaque = null,

    pub fn init() Texture {
        return .{};
    }

    pub fn deinit(self: *Texture) void {
        self.* = .{};
    }
};

pub const TextureUse = enum(u8) {
    unknown = 0,
    map_diffuse = 1,
};

pub const TextureMap = struct {
    texture: TextureHandle = TextureHandle.nil,
    use: TextureUse = .unknown,
};
