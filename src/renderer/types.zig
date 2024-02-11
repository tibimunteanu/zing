const std = @import("std");
const math = @import("zmath");
const TextureHandle = @import("../systems/texture_system.zig").TextureHandle;

pub const BeginFrameResult = enum {
    render,
    resize,
};

pub const GlobalUniformData = struct {
    projection: math.Mat,
    view: math.Mat,
    _reserved_1: math.Mat = undefined,
    _reserved_2: math.Mat = undefined,
};

pub const ObjectUniformData = struct {
    diffuse_color: math.Vec,
    _reserved_0: math.Vec = undefined,
    _reserved_1: math.Vec = undefined,
    _reserved_2: math.Vec = undefined,
};

pub const GeometryRenderData = struct {
    object_id: ?u32,
    model: math.Mat,
    textures: [16]TextureHandle,
};
