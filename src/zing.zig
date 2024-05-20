const Engine = @import("engine.zig");
const Renderer = @import("renderer/renderer.zig");
const TextureSystem = @import("systems/texture_system.zig");
const MaterialSystem = @import("systems/material_system.zig");
const GeometrySystem = @import("systems/geometry_system.zig");

pub var engine: Engine = undefined;
pub var renderer: Renderer = undefined;
pub var sys: struct {
    texture: TextureSystem,
    material: MaterialSystem,
    geometry: GeometrySystem,
} = undefined;
