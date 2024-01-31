const zm = @import("zmath");

pub const BeginFrameResult = enum {
    render,
    resize,
};

pub const GlobalUniformData = struct {
    projection: zm.Mat,
    view: zm.Mat,
    _reserved1: zm.Mat,
    _reserved2: zm.Mat,
};
