const std = @import("std");
const TextureHandle = @import("../systems/texture_system.zig").TextureHandle;

const Array = std.BoundedArray;

const Texture = @This();

pub const Use = enum(u8) {
    unknown = 0,
    map_diffuse = 1,
};

pub const Map = struct {
    texture: TextureHandle = TextureHandle.nil,
    use: Use = .unknown,
};

name: Array(u8, 256) = .{},
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
