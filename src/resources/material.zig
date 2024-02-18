const std = @import("std");
const math = @import("zmath");

const TextureMap = @import("texture.zig").TextureMap;

pub const MaterialName = std.BoundedArray(u8, 256);

pub const Material = struct {
    name: MaterialName = .{},
    diffuse_color: math.Vec = math.Vec{ 0, 0, 0, 0 },
    diffuse_map: TextureMap = .{},
    generation: ?u32 = null,
    internal_id: ?u32 = null,

    pub fn init() Material {
        return .{};
    }

    pub fn deinit(self: *Material) void {
        self.* = .{};
    }
};
