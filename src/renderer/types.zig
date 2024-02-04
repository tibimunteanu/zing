const std = @import("std");
const zm = @import("zmath");
const Texture = @import("../resources/texture.zig").Texture;
const ID = @import("../utils.zig").ID;

pub const BeginFrameResult = enum {
    render,
    resize,
};

pub const GlobalUniformData = struct {
    projection: zm.Mat,
    view: zm.Mat,
    _reserved_1: zm.Mat = undefined,
    _reserved_2: zm.Mat = undefined,
};

pub const ObjectUniformData = struct {
    diffuse_color: zm.Vec,
    _reserved_0: zm.Vec = undefined,
    _reserved_1: zm.Vec = undefined,
    _reserved_2: zm.Vec = undefined,
};

pub const GeometryRenderData = struct {
    object_id: ID,
    model: zm.Mat,
    textures: [16]*Texture,
};
