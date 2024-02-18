const std = @import("std");
const math = @import("zmath");
const MaterialHandle = @import("../systems/material_system.zig").MaterialHandle;

pub const GeometryName = std.BoundedArray(u8, 256);

pub const Geometry = struct {
    name: GeometryName = .{},
    material: MaterialHandle = MaterialHandle.nil,
    generation: ?u32 = null,
    internal_id: ?u32 = null,

    pub fn init() Geometry {
        return .{};
    }

    pub fn deinit(self: *Geometry) void {
        self.* = .{};
    }
};
