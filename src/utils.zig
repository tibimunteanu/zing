const std = @import("std");
const math = @import("zmath");

pub const ID = enum(u32) {
    const null_value = std.math.maxInt(u32);

    null_handle = null_value,
    _,

    pub fn value(self: ID) u32 {
        std.debug.assert(self != .null_handle);
        return @intFromEnum(self);
    }

    pub fn set(self: *ID, newValue: u32) void {
        self.* = @enumFromInt(newValue);
    }

    pub fn increment(self: *ID) void {
        var currentValue = @intFromEnum(self.*);
        if (currentValue == null_value - 1) {
            currentValue += 1;
        }
        self.* = @enumFromInt(currentValue +% 1);
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
