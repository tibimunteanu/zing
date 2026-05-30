const std = @import("std");

const c = @cImport({
    @cInclude("stb_image.h");
});

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
