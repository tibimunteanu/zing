const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("stb_image.h");
});

const ImageAsset = @This();

allocator: Allocator,
name: []const u8,
full_path: []const u8,
image: Image,

pub fn init(allocator: Allocator, name: []const u8) !ImageAsset {
    const path_format = "assets/textures/{s}{s}";

    const texture_path = try std.fmt.allocPrintSentinel(allocator, path_format, .{ name, ".png" }, 0);
    defer allocator.free(texture_path);

    setFlipVerticallyOnLoad(true);

    var image = try Image.loadFromFile(texture_path, 4);
    errdefer image.deinit();

    return .{
        .allocator = allocator,
        .name = try allocator.dupe(u8, name),
        .full_path = try allocator.dupe(u8, texture_path),
        .image = image,
    };
}

pub fn deinit(self: *ImageAsset) void {
    self.allocator.free(self.name);
    self.allocator.free(self.full_path);
    self.image.deinit();
    self.* = undefined;
}

pub fn setFlipVerticallyOnLoad(enabled: bool) void {
    c.stbi_set_flip_vertically_on_load(if (enabled) 1 else 0);
}

pub const Image = struct {
    data: []u8,
    width: u32,
    height: u32,
    num_components: u32,

    pub fn loadFromFile(pathname: [:0]const u8, forced_num_components: u32) !Image {
        var width: c_int = 0;
        var height: c_int = 0;
        var components: c_int = 0;

        const data = c.stbi_load(
            pathname.ptr,
            &width,
            &height,
            &components,
            @intCast(forced_num_components),
        ) orelse return error.ImageLoadFailed;

        const actual_components = if (forced_num_components == 0)
            @as(u32, @intCast(components))
        else
            forced_num_components;
        const len: usize = @as(usize, @intCast(width)) *
            @as(usize, @intCast(height)) *
            @as(usize, actual_components);

        return .{
            .data = @as([*]u8, @ptrCast(data))[0..len],
            .width = @intCast(width),
            .height = @intCast(height),
            .num_components = actual_components,
        };
    }

    pub fn deinit(self: *Image) void {
        c.stbi_image_free(self.data.ptr);
        self.* = undefined;
    }
};
