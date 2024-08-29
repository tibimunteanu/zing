const std = @import("std");
const stbi = @import("zstbi");

const Allocator = std.mem.Allocator;

const ImageLoader = @This();

allocator: Allocator,
name: []const u8,
full_path: []const u8,
image: stbi.Image,

pub fn init(allocator: Allocator, name: []const u8) !ImageLoader {
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

pub fn deinit(self: *ImageLoader) void {
    self.allocator.free(self.name);
    self.allocator.free(self.full_path);
    self.image.deinit();
    self.* = undefined;

    stbi.deinit();
}
