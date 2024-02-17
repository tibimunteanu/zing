const std = @import("std");

pub const TextureName = std.BoundedArray(u8, 256);

pub const Texture = struct {
    name: TextureName,
    width: u32,
    height: u32,
    channel_count: u8,
    has_transparency: bool,
    generation: ?u32,
    internal_data: ?*anyopaque,

    pub fn init() !Texture {
        return Texture{
            .name = try TextureName.fromSlice("none"),
            .width = 0,
            .height = 0,
            .channel_count = 0,
            .has_transparency = false,
            .generation = null,
            .internal_data = null,
        };
    }

    pub fn deinit(self: *Texture) void {
        self.name.len = 0;
        self.width = 0;
        self.height = 0;
        self.channel_count = 0;
        self.has_transparency = false;
        self.generation = null;
        self.internal_data = null;
    }
};

pub const TextureUse = enum(u8) {
    unknown = 0,
    map_diffuse = 1,
};
