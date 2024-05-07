const std = @import("std");
const MaterialHandle = @import("../systems/material_system.zig").MaterialHandle;

const Array = std.BoundedArray;

const Geometry = @This();

name: Array(u8, 256) = .{},
material: MaterialHandle = MaterialHandle.nil,
generation: ?u32 = null,
internal_id: ?u32 = null,

pub fn init() Geometry {
    return .{};
}

pub fn deinit(self: *Geometry) void {
    self.* = .{};
}
