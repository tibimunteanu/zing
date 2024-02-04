const zm = @import("zmath");
const Texture = @import("../resources/texture.zig").Texture;

pub const BeginFrameResult = enum {
    render,
    resize,
};

pub const GlobalUniformData = struct {
    projection: zm.Mat,
    view: zm.Mat,
    _reserved_1: zm.Mat,
    _reserved_2: zm.Mat,
};

pub const ObjectUniformData = struct {
    diffuse_color: zm.Vec,
    _reserved_0: zm.Vec,
    _reserved_1: zm.Vec,
    _reserved_2: zm.Vec,
};

pub const GeometryRenderData = struct {
    object_id: u32,
    model: zm.Mat,
    textures: [16]*Texture,
};
