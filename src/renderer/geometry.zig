const std = @import("std");
const MaterialHandle = @import("../systems/material_system.zig").MaterialHandle;

const Geometry = @This();

pub const Name = std.BoundedArray(u8, 256);

name: Name = .{},
material: MaterialHandle = MaterialHandle.nil,
generation: ?u32 = null,
internal_id: ?u32 = null,

pub fn init() Geometry {
    return .{};
}

pub fn deinit(self: *Geometry) void {
    self.* = .{};
}
