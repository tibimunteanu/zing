const std = @import("std");
const math = @import("zmath");

const GeometryHandle = @import("../systems/geometry_system.zig").GeometryHandle;

pub const BeginFrameResult = enum {
    render,
    resize,
};

pub const RenderPassTypes = enum {
    world,
    ui,
};

pub const Vertex3D = struct {
    position: [3]f32,
    texcoord: [2]f32,
    color: [4]f32,
};

pub const Vertex2D = struct {
    position: [2]f32,
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
    ui_geometries: []const GeometryRenderData,
};
