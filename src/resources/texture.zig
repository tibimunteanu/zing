const std = @import("std");
const math = @import("zmath");
const TextureHandle = @import("../systems/texture_system.zig").TextureHandle;

pub const TextureName = std.BoundedArray(u8, 256);

pub const Texture = struct {
    name: TextureName = .{},
    width: u32 = 0,
    height: u32 = 0,
    channel_count: u8 = 0,
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
