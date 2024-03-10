const std = @import("std");
const math = @import("zmath");
const Texture = @import("../renderer/texture.zig");
const TextureSystem = @import("../systems/texture_system.zig");

const Material = @This();

pub const Name = std.BoundedArray(u8, 256);

pub const Type = enum {
    world,
    ui,
};

pub const Config = struct {
    name: []const u8 = "New Material",
    material_type: []const u8 = "world",
    diffuse_color: math.Vec = math.Vec{ 1.0, 1.0, 1.0, 1.0 },
    diffuse_map_name: []const u8 = TextureSystem.default_texture_name,
    auto_release: bool = false,
};

name: Name = .{},
material_type: Type = .world,
diffuse_color: math.Vec = math.Vec{ 0, 0, 0, 0 },
diffuse_map: Texture.Map = .{},
generation: ?u32 = null,
internal_id: ?u32 = null,

pub fn init() Material {
    return .{};
}

pub fn deinit(self: *Material) void {
    self.* = .{};
}
