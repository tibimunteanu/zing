const std = @import("std");
const pool = @import("zpool");
const math = @import("zmath");

const zing = @import("../zing.zig");
const Renderer = @import("renderer.zig");
const Material = @import("material.zig");

const MaterialHandle = Material.MaterialHandle;

const Vertex3D = Renderer.Vertex3D;
const Vertex2D = Renderer.Vertex2D;

const Allocator = std.mem.Allocator;
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

pub const GeometryPool = pool.Pool(16, 16, Geometry, struct {
    geometry: Geometry,
    reference_count: usize,
    auto_release: bool,
});
pub const GeometryHandle = GeometryPool.Handle;

pub fn GeometryConfig(comptime Vertex: type, comptime Index: type) type {
    return struct {
        const Self = @This();

        name: []const u8,
        vertices: []const Vertex,
        indices: []const Index,
        material_name: []const u8,

        pub fn initPlane(
            options: struct {
                name: []const u8,
                material_name: []const u8,
                width: f32,
                height: f32,
                segment_count_x: u32,
                segment_count_y: u32,
                tile_x: u32,
                tile_y: u32,
            },
        ) !Self {
            if (options.width <= 0 or options.height <= 0) {
                return error.InvalidDimensions;
            }

            if (options.segment_count_x < 1 or options.segment_count_y < 1) {
                return error.InvalidSegmentCount;
            }

            if (options.tile_x == 0 or options.tile_y == 0) {
                return error.InvalidTiling;
            }

            if (options.name.len == 0) {
                return error.NameCannotBeEmpty;
            }

            var self: Self = undefined;

            const vertex_count = options.segment_count_x * options.segment_count_y * 4;
            const vertices = try allocator.alloc(Vertex, vertex_count);
            for (vertices) |*vert| {
                vert.* = std.mem.zeroes(Vertex);
            }
            errdefer allocator.free(vertices);

            const index_count = options.segment_count_x * options.segment_count_y * 6;
            const indices = try allocator.alloc(Index, index_count);
            errdefer allocator.free(indices);

            const seg_count_x_f32 = @as(f32, @floatFromInt(options.segment_count_x));
            const seg_count_y_f32 = @as(f32, @floatFromInt(options.segment_count_y));

            const seg_width = options.width / seg_count_x_f32;
            const seg_height = options.height / seg_count_y_f32;
            const half_width = options.width * 0.5;
            const half_height = options.height * 0.5;

            for (0..options.segment_count_y) |y| {
                for (0..options.segment_count_x) |x| {
                    const x_f32 = @as(f32, @floatFromInt(x));
                    const y_f32 = @as(f32, @floatFromInt(y));

                    // vertices
                    const min_x = (x_f32 * seg_width) - half_width;
                    const min_y = (y_f32 * seg_height) - half_height;
                    const max_x = min_x + seg_width;
                    const max_y = min_y + seg_height;

                    const tile_x_f32 = @as(f32, @floatFromInt(options.tile_x));
                    const tile_y_f32 = @as(f32, @floatFromInt(options.tile_y));

                    const min_uvx = (x_f32 / seg_count_x_f32) * tile_x_f32;
                    const min_uvy = (y_f32 / seg_count_y_f32) * tile_y_f32;
                    const max_uvx = ((x_f32 + 1.0) / seg_count_x_f32) * tile_x_f32;
                    const max_uvy = ((y_f32 + 1.0) / seg_count_y_f32) * tile_y_f32;

                    const vertex_offset = ((y * options.segment_count_x) + x) * 4;

                    var v0 = &vertices[vertex_offset + 0];
                    var v1 = &vertices[vertex_offset + 1];
                    var v2 = &vertices[vertex_offset + 2];
                    var v3 = &vertices[vertex_offset + 3];

                    v0.position[0] = min_x;
                    v0.position[1] = min_y;
                    v0.texcoord = [_]f32{ min_uvx, min_uvy };

                    v1.position[0] = max_x;
                    v1.position[1] = max_y;
                    v1.texcoord = [_]f32{ max_uvx, max_uvy };

                    v2.position[0] = min_x;
                    v2.position[1] = max_y;
                    v2.texcoord = [_]f32{ min_uvx, max_uvy };

                    v3.position[0] = max_x;
                    v3.position[1] = min_y;
                    v3.texcoord = [_]f32{ max_uvx, min_uvy };

                    self.vertices = vertices;

                    // indices
                    const index_offset = ((y * options.segment_count_x) + x) * 6;

                    indices[index_offset + 0] = @truncate(vertex_offset + 0);
                    indices[index_offset + 1] = @truncate(vertex_offset + 1);
                    indices[index_offset + 2] = @truncate(vertex_offset + 2);
                    indices[index_offset + 3] = @truncate(vertex_offset + 0);
                    indices[index_offset + 4] = @truncate(vertex_offset + 3);
                    indices[index_offset + 5] = @truncate(vertex_offset + 1);

                    self.indices = indices;
                }
            }

            self.name = try allocator.dupe(u8, options.name);

            self.material_name = try allocator.dupe(u8, //
                if (options.material_name.len > 0) options.material_name else "default");

            return self;
        }

        pub fn deinit(self: *Self) void {
            allocator.free(self.material_name);
            allocator.free(self.name);
            allocator.free(self.indices);
            allocator.free(self.vertices);
        }
    };
}

pub const default_geometry_name = "default";
pub const default_geometry_2d_name = "default_2d";

var allocator: Allocator = undefined;
var geometries: GeometryPool = undefined;
var default_geometry: GeometryHandle = GeometryHandle.nil;
var default_geometry_2d: GeometryHandle = GeometryHandle.nil;

name: Array(u8, 256),
material: MaterialHandle,
generation: ?u32,
internal_id: ?u32,

pub fn initSystem(ally: Allocator) !void {
    allocator = ally;

    geometries = try GeometryPool.initMaxCapacity(allocator);
    errdefer geometries.deinit();

    try createDefault();
}

pub fn deinitSystem() void {
    removeAll();
    geometries.deinit();
}

pub fn acquireDefault() GeometryHandle {
    return default_geometry;
}

pub fn acquireDefault2D() GeometryHandle {
    return default_geometry_2d;
}

pub fn acquireByConfig(config: anytype, options: struct { auto_release: bool }) !GeometryHandle {
    const material_handle = Material.acquireByName(config.material_name) //
    catch Material.acquireDefault();

    var geometry = try create(
        config.name,
        material_handle,
        config.vertices,
        config.indices,
    );
    geometry.generation = if (geometry.generation) |g| g +% 1 else 0;
    errdefer geometry.destroy();

    const handle = try geometries.add(.{
        .geometry = geometry,
        .reference_count = 1,
        .auto_release = options.auto_release,
    });
    errdefer geometries.removeAssumeLive(handle);

    std.log.info("Geometry: Create geometry '{s}'. Ref count: 1", .{geometry.name.slice()});

    return handle;
}

pub fn acquireByHandle(handle: GeometryHandle) !GeometryHandle {
    try geometries.requireLiveHandle(handle);

    if (handle.id == default_geometry.id) {
        std.log.warn("Geometry: Cannot acquire default geometry. Use getDefaultGeometry() instead!", .{});
        return default_geometry;
    }

    const geometry = geometries.getColumnPtrAssumeLive(handle, .geometry);
    const reference_count = geometries.getColumnPtrAssumeLive(handle, .reference_count);

    reference_count.* +|= 1;

    std.log.info("Geometry: Geometry '{s}' was acquired. Ref count: {}", .{ geometry.name.slice(), reference_count.* });

    return handle;
}

pub fn releaseByHandle(handle: GeometryHandle) void {
    if (!geometries.isLiveHandle(handle)) {
        std.log.warn("Geometry: Cannot release geometry with invalid handle!", .{});
        return;
    }

    if (handle.id == default_geometry.id) {
        std.log.warn("Geometry: Cannot release default geometry!", .{});
        return;
    }

    const geometry = geometries.getColumnPtrAssumeLive(handle, .geometry);
    const reference_count = geometries.getColumnPtrAssumeLive(handle, .reference_count);
    const auto_release = geometries.getColumnAssumeLive(handle, .auto_release);

    if (reference_count.* == 0) {
        std.log.warn("Geometry: Cannot release geometry with ref count 0!", .{});
        return;
    }

    reference_count.* -|= 1;

    if (reference_count.* == 0 and auto_release) {
        remove(handle);
    } else {
        std.log.info("Geometry: Geometry '{s}' was released. Ref count: {}", .{ geometry.name.slice(), reference_count.* });
    }
}

pub inline fn exists(handle: GeometryHandle) bool {
    return geometries.isLiveHandle(handle);
}

pub inline fn get(handle: GeometryHandle) !*Geometry {
    return try geometries.getColumnPtr(handle, .geometry);
}

pub inline fn getIfExists(handle: GeometryHandle) ?*Geometry {
    return geometries.getColumnPtrIfLive(handle, .geometry);
}

// utils
fn create(
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

    for (&Renderer.geometries, 0..) |*slot, i| {
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
        data.vertex_buffer_offset = try Renderer.vertex_buffer.allocAndUpload(std.mem.sliceAsBytes(vertices));

        if (indices.len > 0) {
            data.index_count = @truncate(indices.len);
            data.index_size = @sizeOf(std.meta.Elem(@TypeOf(indices)));
            data.index_buffer_offset = try Renderer.index_buffer.allocAndUpload(std.mem.sliceAsBytes(indices));
        }

        data.generation = if (self.generation) |g| g +% 1 else 0;
    } else {
        return error.FaildToReserveInternalData;
    }

    return self;
}

fn createDefault() !void {
    const vertices_3d = [_]Vertex3D{
        .{ .position = .{ -5.0, -5.0, 0.0 }, .texcoord = .{ 0.0, 0.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
        .{ .position = .{ 5.0, -5.0, 0.0 }, .texcoord = .{ 1.0, 0.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
        .{ .position = .{ 5.0, 5.0, 0.0 }, .texcoord = .{ 1.0, 1.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },
        .{ .position = .{ -5.0, 5.0, 0.0 }, .texcoord = .{ 0.0, 1.0 }, .color = .{ 1.0, 1.0, 0.0, 1.0 } },
    };

    const indices_3d = [_]u32{ 0, 1, 2, 0, 2, 3 };

    var geometry_3d = try create(
        default_geometry_name,
        Material.acquireDefault(),
        &vertices_3d,
        &indices_3d,
    );
    geometry_3d.generation = null; // NOTE: default geometry always has null generation
    errdefer geometry_3d.destroy();

    default_geometry = try geometries.add(.{
        .geometry = geometry_3d,
        .reference_count = 1,
        .auto_release = false,
    });

    std.log.info("Geometry: Create default 3D geometry '{s}'. Ref count: 1", .{geometry_3d.name.slice()});

    const vertices_2d = [_]Vertex2D{
        .{ .position = .{ -5.0, -5.0 }, .texcoord = .{ 0.0, 0.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
        .{ .position = .{ 5.0, -5.0 }, .texcoord = .{ 1.0, 0.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
        .{ .position = .{ 5.0, 5.0 }, .texcoord = .{ 1.0, 1.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },
        .{ .position = .{ -5.0, 5.0 }, .texcoord = .{ 0.0, 1.0 }, .color = .{ 1.0, 1.0, 0.0, 1.0 } },
    };

    const indices_2d = [_]u32{ 0, 1, 2, 0, 2, 3 };

    var geometry_2d = try create(
        default_geometry_2d_name,
        Material.acquireDefault(),
        &vertices_2d,
        &indices_2d,
    );
    geometry_2d.generation = null; // NOTE: default geometry always has null generation
    errdefer geometry_2d.destroy();

    default_geometry_2d = try geometries.add(.{
        .geometry = geometry_2d,
        .reference_count = 1,
        .auto_release = false,
    });

    std.log.info("Geometry: Create default 2D geometry '{s}'. Ref count: 1", .{geometry_2d.name.slice()});
}

fn destroy(self: *Geometry) void {
    if (self.internal_id != null) {
        Renderer.device_api.deviceWaitIdle(Renderer.device) catch {
            std.log.err("Could not destroy geometry {s}", .{self.name.slice()});
        };

        const internal_data = &Renderer.geometries[self.internal_id.?];

        Renderer.vertex_buffer.free(
            internal_data.vertex_buffer_offset,
            internal_data.vertex_size,
        ) catch unreachable;

        if (internal_data.index_size > 0) {
            Renderer.index_buffer.free(
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

fn remove(handle: GeometryHandle) void {
    if (geometries.getColumnPtrIfLive(handle, .geometry)) |geometry| {
        std.log.info("Geometry: Remove '{s}'", .{geometry.name.slice()});

        Material.releaseByHandle(geometry.material);

        geometries.removeAssumeLive(handle);

        geometry.destroy();
    }
}

fn removeAll() void {
    var it = geometries.liveHandles();
    while (it.next()) |handle| {
        remove(handle);
    }
}
