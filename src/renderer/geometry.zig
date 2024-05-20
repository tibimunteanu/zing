const std = @import("std");
const zing = @import("../zing.zig");
const MaterialHandle = @import("../systems/material_system.zig").MaterialHandle;

const Array = std.BoundedArray;

const Geometry = @This();

pub const GeometryData = struct {
    id: ?u32,
    generation: ?u32,
    vertex_count: u32,
    vertex_size: u64,
    vertex_buffer_offset: u64,
    index_count: u32,
    index_size: u64,
    index_buffer_offset: u64,
};

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

pub fn createGeometry(self: *Geometry, vertices: anytype, indices: anytype) !void {
    if (vertices.len == 0) {
        return error.VerticesCannotBeEmpty;
    }

    var prev_internal_data: GeometryData = undefined;
    var internal_data: ?*GeometryData = null;

    const is_reupload = self.internal_id != null;
    if (is_reupload) {
        internal_data = &zing.renderer.geometries[self.internal_id.?];

        // take a copy of the old region
        prev_internal_data = internal_data.?.*;
    } else {
        for (&zing.renderer.geometries, 0..) |*slot, i| {
            if (slot.id == null) {
                const id: u32 = @truncate(i);
                self.internal_id = id;
                slot.*.id = id;
                internal_data = slot;
                break;
            }
        }
    }

    if (internal_data) |data| {
        data.vertex_count = @truncate(vertices.len);
        data.vertex_size = @sizeOf(std.meta.Elem(@TypeOf(vertices)));
        data.vertex_buffer_offset = try zing.renderer.vertex_buffer.allocAndUpload(std.mem.sliceAsBytes(vertices));

        if (indices.len > 0) {
            data.index_count = @truncate(indices.len);
            data.index_size = @sizeOf(std.meta.Elem(@TypeOf(indices)));
            data.index_buffer_offset = try zing.renderer.index_buffer.allocAndUpload(std.mem.sliceAsBytes(indices));
        }

        data.generation = if (self.generation) |g| g +% 1 else 0;

        if (is_reupload) {
            try zing.renderer.vertex_buffer.free(
                prev_internal_data.vertex_buffer_offset,
                prev_internal_data.vertex_count * prev_internal_data.vertex_size,
            );

            if (prev_internal_data.index_count > 0) {
                try zing.renderer.index_buffer.free(
                    prev_internal_data.index_buffer_offset,
                    prev_internal_data.index_count * prev_internal_data.index_size,
                );
            }
        }
    } else {
        return error.FaildToReserveInternalData;
    }
}

pub fn destroyGeometry(self: *Geometry) void {
    if (self.internal_id != null) {
        zing.renderer.device_api.deviceWaitIdle(zing.renderer.device) catch {
            std.log.err("Could not destroy geometry {s}", .{self.name.slice()});
        };

        const internal_data = &zing.renderer.geometries[self.internal_id.?];

        zing.renderer.vertex_buffer.free(
            internal_data.vertex_buffer_offset,
            internal_data.vertex_size,
        ) catch unreachable;

        if (internal_data.index_size > 0) {
            zing.renderer.index_buffer.free(
                internal_data.index_buffer_offset,
                internal_data.index_size,
            ) catch unreachable;
        }

        internal_data.* = undefined;
        internal_data.id = null;
        internal_data.generation = null;
    }
}
