const std = @import("std");
const math = @import("zmath");

pub const ID = enum(u32) {
    null_handle = std.math.maxInt(u32),
    _,

    pub fn increment(self: *ID) void {
        if (self.* == .null_handle or self.* == @as(ID, @enumFromInt(std.math.maxInt(u32) - 1))) {
            self.* = @enumFromInt(0);
        } else {
            self.* = @enumFromInt(@intFromEnum(self.*) + 1);
        }
    }
};

pub fn getForwardVec(mat: math.Mat) math.Vec {
    return math.normalize3(math.Vec{ -mat[0][2], -mat[1][2], -mat[2][2], 0.0 });
}

pub fn getBackwardVec(mat: math.Mat) math.Vec {
    return math.normalize3(math.Vec{ mat[0][2], mat[1][2], mat[2][2], 0.0 });
}

pub fn getLeftVec(mat: math.Mat) math.Vec {
    return math.normalize3(math.Vec{ -mat[0][0], -mat[1][0], -mat[2][0], 0.0 });
}

pub fn getRightVec(mat: math.Mat) math.Vec {
    return math.normalize3(math.Vec{ mat[0][0], mat[1][0], mat[2][0], 0.0 });
}
