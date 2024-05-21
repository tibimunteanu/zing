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

name: Array(u8, 256),
material: MaterialHandle,
generation: ?u32,
internal_id: ?u32,

pub fn init(
    name: []const u8,
    material: MaterialHandle,
    vertices: anytype,
    indices: anytype,
) !Geometry {
    var self: Geometry = undefined;
    self.name = try Array(u8, 256).fromSlice(name);
    self.material = material;
    self.generation = null;
    self.internal_id = null;

    if (vertices.len == 0) {
        return error.VerticesCannotBeEmpty;
    }

    var internal_data: ?*GeometryData = null;

    for (&zing.renderer.geometries, 0..) |*slot, i| {
        if (slot.id == null) {
            const id: u32 = @truncate(i);
            self.internal_id = id;
            slot.*.id = id;
            internal_data = slot;
            break;
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
    } else {
        return error.FaildToReserveInternalData;
    }

    return self;
}

pub fn deinit(self: *Geometry) void {
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

    self.* = undefined;
}
