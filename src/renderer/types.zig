const std = @import("std");
const math = @import("zmath");
const Texture = @import("../resources/texture.zig").Texture;
const ID = @import("../utils.zig").ID;

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
    object_id: ID,
    model: math.Mat,
    textures: [16]?*Texture,
};
