const std = @import("std");
const math = @import("zmath");

const GeometryHandle = @import("../systems/geometry_system.zig").GeometryHandle;

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

pub const MaterialUniformData = struct {
    diffuse_color: math.Vec,
    _reserved_0: math.Vec = undefined,
    _reserved_1: math.Vec = undefined,
    _reserved_2: math.Vec = undefined,
};

pub const Vertex = struct {
    position: [3]f32,
    texcoord: [2]f32,
    color: [4]f32,
};

pub const GeometryRenderData = struct {
    model: math.Mat,
    geometry: GeometryHandle,
};

pub const RenderPacket = struct {
    delta_time: f32,
    geometries: []const GeometryRenderData,
};
