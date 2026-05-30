const std = @import("std");

pub const Vec = @Vector(4, f32);
pub const Mat = [4]Vec;

pub fn splat(comptime T: type, value: f32) T {
    return @splat(value);
}

pub fn identity() Mat {
    return .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn translation(x: f32, y: f32, z: f32) Mat {
    return .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ x, y, z, 1 },
    };
}

pub fn translationV(v: Vec) Mat {
    return translation(v[0], v[1], v[2]);
}

pub fn rotationY(angle: f32) Mat {
    const s = @sin(angle);
    const c = @cos(angle);
    return .{
        .{ c, 0, -s, 0 },
        .{ 0, 1, 0, 0 },
        .{ s, 0, c, 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn matFromRollPitchYawV(v: Vec) Mat {
    const pitch = v[0];
    const yaw = v[1];
    const roll = v[2];

    const sx = @sin(pitch);
    const cx = @cos(pitch);
    const sy = @sin(yaw);
    const cy = @cos(yaw);
    const sz = @sin(roll);
    const cz = @cos(roll);

    const rx = Mat{
        .{ 1, 0, 0, 0 },
        .{ 0, cx, sx, 0 },
        .{ 0, -sx, cx, 0 },
        .{ 0, 0, 0, 1 },
    };
    const ry = Mat{
        .{ cy, 0, -sy, 0 },
        .{ 0, 1, 0, 0 },
        .{ sy, 0, cy, 0 },
        .{ 0, 0, 0, 1 },
    };
    const rz = Mat{
        .{ cz, sz, 0, 0 },
        .{ -sz, cz, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    };

    return mul(mul(rz, rx), ry);
}

pub fn mul(a: Mat, b: Mat) Mat {
    var out: Mat = undefined;
    for (0..4) |column| {
        out[column] =
            a[0] * @as(Vec, @splat(b[column][0])) +
            a[1] * @as(Vec, @splat(b[column][1])) +
            a[2] * @as(Vec, @splat(b[column][2])) +
            a[3] * @as(Vec, @splat(b[column][3]));
    }
    return out;
}

pub fn inverse(m: Mat) Mat {
    const tx = m[3][0];
    const ty = m[3][1];
    const tz = m[3][2];

    var out = identity();
    out[0] = .{ m[0][0], m[1][0], m[2][0], 0 };
    out[1] = .{ m[0][1], m[1][1], m[2][1], 0 };
    out[2] = .{ m[0][2], m[1][2], m[2][2], 0 };
    out[3] = .{
        -(tx * out[0][0] + ty * out[1][0] + tz * out[2][0]),
        -(tx * out[0][1] + ty * out[1][1] + tz * out[2][1]),
        -(tx * out[0][2] + ty * out[1][2] + tz * out[2][2]),
        1,
    };
    return out;
}

pub fn perspectiveFovLh(fov_y: f32, aspect: f32, near_z: f32, far_z: f32) Mat {
    const h = 1.0 / @tan(fov_y * 0.5);
    const w = h / aspect;
    const range = far_z / (far_z - near_z);

    return .{
        .{ w, 0, 0, 0 },
        .{ 0, h, 0, 0 },
        .{ 0, 0, range, 1 },
        .{ 0, 0, -near_z * range, 0 },
    };
}

pub fn orthographicOffCenterLh(left: f32, right: f32, bottom: f32, top: f32, near_z: f32, far_z: f32) Mat {
    return .{
        .{ 2.0 / (right - left), 0, 0, 0 },
        .{ 0, 2.0 / (top - bottom), 0, 0 },
        .{ 0, 0, 1.0 / (far_z - near_z), 0 },
        .{
            (left + right) / (left - right),
            (top + bottom) / (bottom - top),
            near_z / (near_z - far_z),
            1,
        },
    };
}

pub fn matFromArr(values: [16]f32) Mat {
    return .{
        .{ values[0], values[1], values[2], values[3] },
        .{ values[4], values[5], values[6], values[7] },
        .{ values[8], values[9], values[10], values[11] },
        .{ values[12], values[13], values[14], values[15] },
    };
}

pub fn isNearEqual(a: Vec, b: Vec, epsilon: Vec) @Vector(4, bool) {
    const diff = @abs(a - b);
    return diff <= epsilon;
}

pub fn all(values: @Vector(4, bool), comptime count: usize) bool {
    inline for (0..count) |index| {
        if (!values[index]) return false;
    }
    return true;
}

pub fn normalize3(v: Vec) Vec {
    const length_squared = v[0] * v[0] + v[1] * v[1] + v[2] * v[2];
    if (length_squared == 0) return .{ 0, 0, 0, v[3] };

    const inv_length = 1.0 / @sqrt(length_squared);
    return .{ v[0] * inv_length, v[1] * inv_length, v[2] * inv_length, v[3] };
}
