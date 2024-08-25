const std = @import("std");
const pool = @import("zpool");
const math = @import("zmath");

const Renderer = @import("renderer.zig");
const Material = @import("material.zig");

const Vertex3D = Renderer.Vertex3D;
const Vertex2D = Renderer.Vertex2D;

const Allocator = std.mem.Allocator;
const Array = std.BoundedArray;

// TODO: load obj and gltf
const Geometry = @This();

// TODO: why don't we just store these in the actual geometry?
pub const Data = struct {
    id: ?u32,
    generation: ?u32,
    vertex_count: u32,
    vertex_size: u64,
    vertex_buffer_offset: u64,
    index_count: u32,
    index_size: u64,
    index_buffer_offset: u64,
};

const GeometryPool = pool.Pool(16, 16, Geometry, struct {
    geometry: Geometry,
    reference_count: usize,
    auto_release: bool,
});

pub const Handle = GeometryPool.Handle;

pub fn Config(comptime Vertex: type, comptime Index: type) type {
    return struct {
        const Self = @This();

        name: []const u8,
        vertices: []const Vertex,
        indices: []const Index,
        material_name: []const u8,
        auto_release: bool,

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
                auto_release: bool,
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

pub const default_name = "default";
pub const default_name_2d = "default_2d";
pub var default: Handle = Handle.nil;
pub var default_2d: Handle = Handle.nil;

var allocator: Allocator = undefined;
var geometries: GeometryPool = undefined;

name: Array(u8, 256),
material: Material.Handle,
generation: ?u32,
internal_id: ?u32,

pub fn initSystem(ally: Allocator) !void {
    allocator = ally;

    geometries = try GeometryPool.initMaxCapacity(allocator);
    errdefer geometries.deinit();

    try createDefault();
}

pub fn deinitSystem() void {
    var it = geometries.liveHandles();
    while (it.next()) |handle| {
        remove(handle);
    }

    geometries.deinit();
}

pub fn acquire(config: anytype) !Handle {
    var geometry = try create(config);
    errdefer geometry.destroy();

    const handle = try geometries.add(.{
        .geometry = geometry,
        .reference_count = 1,
        .auto_release = config.auto_release,
    });
    errdefer geometries.removeAssumeLive(handle);

    std.log.info("Geometry: Create '{s}' (1)", .{config.name});

    return handle;
}

// handle
pub fn acquireExisting(handle: Handle) !Handle {
    if (eql(handle, default)) {
        return default;
    }

    const geometry = try get(handle);
    const reference_count = geometries.getColumnPtrAssumeLive(handle, .reference_count);

    reference_count.* +|= 1;

    std.log.info("Geometry: Acquire '{s}' ({})", .{ geometry.name.slice(), reference_count.* });

    return handle;
}

pub fn release(handle: Handle) void {
    if (eql(handle, default)) {
        return;
    }

    if (getIfExists(handle)) |geometry| {
        const reference_count = geometries.getColumnPtrAssumeLive(handle, .reference_count);
        const auto_release = geometries.getColumnAssumeLive(handle, .auto_release);

        if (reference_count.* == 0) {
            std.log.warn("Geometry: Release with ref count 0!", .{});
            return;
        }

        reference_count.* -|= 1;

        if (auto_release and reference_count.* == 0) {
            remove(handle);
        } else {
            std.log.info("Geometry: Release '{s}' ({})", .{ geometry.name.slice(), reference_count.* });
        }
    } else {
        std.log.warn("Geometry: Release invalid handle!", .{});
    }
}

pub inline fn eql(left: Handle, right: Handle) bool {
    return left.id == right.id;
}

pub inline fn exists(handle: Handle) bool {
    return geometries.isLiveHandle(handle);
}

pub inline fn isNilOrDefault(handle: Handle) bool {
    return eql(handle, Handle.nil) || eql(handle, default) || eql(handle, default_name_2d);
}

pub inline fn get(handle: Handle) !*Geometry {
    return try geometries.getColumnPtr(handle, .geometry);
}

pub inline fn getIfExists(handle: Handle) ?*Geometry {
    return geometries.getColumnPtrIfLive(handle, .geometry);
}

pub inline fn getOrDefault(handle: Handle) *Geometry {
    return geometries.getColumnPtrIfLive(handle, .geometry) //
    orelse geometries.getColumnPtrAssumeLive(default, .geometry);
}

pub inline fn getOrDefault2D(handle: Handle) *Geometry {
    return geometries.getColumnPtrIfLive(handle, .geometry) //
    orelse geometries.getColumnPtrAssumeLive(default_2d, .geometry);
}

pub fn remove(handle: Handle) void {
    if (getIfExists(handle)) |geometry| {
        std.log.info("Geometry: Remove '{s}'", .{geometry.name.slice()});

        geometries.removeAssumeLive(handle);

        geometry.destroy();
    }
}

// utils
fn createDefault() !void {
    const vertices_3d = [_]Vertex3D{
        .{ .position = .{ -5.0, -5.0, 0.0 }, .texcoord = .{ 0.0, 0.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
        .{ .position = .{ 5.0, -5.0, 0.0 }, .texcoord = .{ 1.0, 0.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
        .{ .position = .{ 5.0, 5.0, 0.0 }, .texcoord = .{ 1.0, 1.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },
        .{ .position = .{ -5.0, 5.0, 0.0 }, .texcoord = .{ 0.0, 1.0 }, .color = .{ 1.0, 1.0, 0.0, 1.0 } },
    };

    const indices_3d = [_]u32{ 0, 1, 2, 0, 2, 3 };

    var geometry_3d = try create(Config(Vertex3D, u32){
        .name = default_name,
        .material_name = Material.default_name,
        .vertices = &vertices_3d,
        .indices = &indices_3d,
        .auto_release = false,
    });
    geometry_3d.generation = null; // NOTE: default geometry must have null generation
    errdefer geometry_3d.destroy();

    default = try geometries.add(.{
        .geometry = geometry_3d,
        .reference_count = 1,
        .auto_release = false,
    });

    std.log.info("Geometry: Create '{s}'", .{default_name});

    const vertices_2d = [_]Vertex2D{
        .{ .position = .{ -5.0, -5.0 }, .texcoord = .{ 0.0, 0.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
        .{ .position = .{ 5.0, -5.0 }, .texcoord = .{ 1.0, 0.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
        .{ .position = .{ 5.0, 5.0 }, .texcoord = .{ 1.0, 1.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },
        .{ .position = .{ -5.0, 5.0 }, .texcoord = .{ 0.0, 1.0 }, .color = .{ 1.0, 1.0, 0.0, 1.0 } },
    };

    const indices_2d = [_]u32{ 0, 1, 2, 0, 2, 3 };

    var geometry_2d = try create(Config(Vertex2D, u32){
        .name = default_name_2d,
        .material_name = Material.default_name,
        .vertices = &vertices_2d,
        .indices = &indices_2d,
        .auto_release = false,
    });
    geometry_2d.generation = null; // NOTE: default geometry must have null generation
    errdefer geometry_2d.destroy();

    default_2d = try geometries.add(.{
        .geometry = geometry_2d,
        .reference_count = 1,
        .auto_release = false,
    });

    std.log.info("Geometry: Create '{s}'", .{default_name_2d});
}

fn create(config: anytype) !Geometry {
    var self: Geometry = undefined;
    self.name = try Array(u8, 256).fromSlice(config.name);
    self.generation = 0;
    self.internal_id = null;

    if (config.vertices.len == 0) {
        return error.VerticesCannotBeEmpty;
    }

    self.material = Material.acquire(config.material_name) catch Material.default;

    var internal_data: ?*Data = null;

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
        data.vertex_count = @truncate(config.vertices.len);
        data.vertex_size = @sizeOf(std.meta.Elem(@TypeOf(config.vertices)));
        data.vertex_buffer_offset = try Renderer.vertex_buffer.allocAndUpload(std.mem.sliceAsBytes(config.vertices));

        if (config.indices.len > 0) {
            data.index_count = @truncate(config.indices.len);
            data.index_size = @sizeOf(std.meta.Elem(@TypeOf(config.indices)));
            data.index_buffer_offset = try Renderer.index_buffer.allocAndUpload(std.mem.sliceAsBytes(config.indices));
        }

        data.generation = if (self.generation) |g| g +% 1 else 0;
    } else {
        return error.FaildToReserveInternalData;
    }

    return self;
}

fn destroy(self: *Geometry) void {
    if (!Material.isNilOrDefault(self.material)) {
        Material.release(self.material);
    }

    if (self.internal_id != null) {
        Renderer.device_api.deviceWaitIdle(Renderer.device) catch {};

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
