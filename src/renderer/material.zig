const std = @import("std");
const math = @import("zmath");
const zing = @import("../zing.zig");
const Shader = @import("shader.zig");
const TextureSystem = @import("../systems/texture_system.zig");

const Array = std.BoundedArray;
const TextureMap = TextureSystem.TextureMap;
const TextureHandle = TextureSystem.TextureHandle;

const Material = @This();

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

name: Array(u8, 256) = .{},
material_type: Type = .world,
diffuse_color: math.Vec = math.Vec{ 0, 0, 0, 0 },
diffuse_map: TextureMap = .{},
generation: ?u32 = null,
instance_handle: ?Shader.InstanceHandle = null,

pub fn init(
    name: []const u8,
    material_type: Type,
    diffuse_color: math.Vec,
    diffuse_texture: TextureHandle,
) !Material {
    var self: Material = undefined;

    self.name = try Array(u8, 256).fromSlice(name);
    self.material_type = material_type;
    self.diffuse_color = diffuse_color;

    self.diffuse_map = TextureMap{
        .use = .map_diffuse,
        .texture = diffuse_texture,
    };

    self.generation = null;

    switch (self.material_type) {
        .world => self.instance_handle = try zing.renderer.phong_shader.initInstance(),
        .ui => self.instance_handle = try zing.renderer.ui_shader.initInstance(),
    }

    return self;
}

pub fn deinit(self: *Material) void {
    if (self.diffuse_map.texture.id != TextureHandle.nil.id) {
        zing.sys.texture.releaseTextureByHandle(self.diffuse_map.texture);
    }

    if (self.instance_handle) |instance_handle| {
        switch (self.material_type) {
            .world => zing.renderer.phong_shader.deinitInstance(instance_handle),
            .ui => zing.renderer.ui_shader.deinitInstance(instance_handle),
        }
    }

    self.* = undefined;
}
