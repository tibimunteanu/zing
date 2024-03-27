const std = @import("std");
const pool = @import("zpool");
const math = @import("zmath");

const Engine = @import("../engine.zig");
const Renderer = @import("../renderer/renderer.zig");
const Material = @import("../renderer/material.zig");
const Geometry = @import("../renderer/geometry.zig");

const Vertex3D = Renderer.Vertex3D;
const Vertex2D = Renderer.Vertex2D;

const Allocator = std.mem.Allocator;

const GeometrySystem = @This();

pub const GeometryPool = pool.Pool(16, 16, Geometry, struct {
    geometry: Geometry,
    reference_count: usize,
    auto_release: bool,
});
pub const GeometryHandle = GeometryPool.Handle;

pub fn GeometryConfig(comptime Vertex: type, comptime Index: type) type {
    return struct {
        allocator: Allocator,

        name: []const u8,
        vertices: []const Vertex,
        indices: []const Index,
        material_name: []const u8,

        pub fn initPlane(
            allocator: Allocator,
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
        ) !GeometryConfig(Vertex, Index) {
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

            var self: GeometryConfig(Vertex, Index) = undefined;
            self.allocator = allocator;

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

        pub fn deinit(self: *GeometryConfig(Vertex, Index)) void {
            self.allocator.free(self.material_name);
            self.allocator.free(self.name);
            self.allocator.free(self.indices);
            self.allocator.free(self.vertices);
        }
    };
}

pub const default_geometry_name = "default";
pub const default_geometry_2d_name = "default_2d";

allocator: Allocator,
default_geometry: GeometryHandle,
default_geometry_2d: GeometryHandle,
geometries: GeometryPool,

pub fn init(self: *GeometrySystem, allocator: Allocator) !void {
    self.allocator = allocator;

    self.geometries = try GeometryPool.initMaxCapacity(allocator);
    errdefer self.geometries.deinit();

    try self.createDefaultGeometries();
}

pub fn deinit(self: *GeometrySystem) void {
    self.unloadAllGeometries();
    self.geometries.deinit();
}

pub fn acquireGeometryByConfig(
    self: *GeometrySystem,
    config: anytype,
    options: struct {
        auto_release: bool,
    },
) !GeometryHandle {
    var geometry = Geometry.init();

    try self.loadGeometry(config, &geometry);

    const handle = try self.geometries.add(.{
        .geometry = geometry,
        .reference_count = 1,
        .auto_release = options.auto_release,
    });
    errdefer self.geometries.removeAssumeLive(handle);

    std.log.info("GeometrySystem: Geometry '{s}' was loaded. Ref count: 1", .{geometry.name.slice()});

    return handle;
}

pub fn acquireGeometryByHandle(self: *GeometrySystem, handle: GeometryHandle) !GeometryHandle {
    try self.geometries.requireLiveHandle(handle);

    if (handle.id == self.default_geometry.id) {
        std.log.warn("GeometrySystem: Cannot acquire default geometry. Use getDefaultGeometry() instead!", .{});
        return self.default_geometry;
    }

    const geometry = self.geometries.getColumnPtrAssumeLive(handle, .geometry);
    const reference_count = self.geometries.getColumnPtrAssumeLive(handle, .reference_count);

    reference_count.* +|= 1;

    std.log.info("GeometrySystem: Geometry '{s}' was acquired. Ref count: {}", .{ geometry.name.slice(), reference_count.* });

    return handle;
}

pub fn releaseGeometryByHandle(self: *GeometrySystem, handle: GeometryHandle) void {
    if (!self.geometries.isLiveHandle(handle)) {
        std.log.warn("GeometrySystem: Cannot release geometry with invalid handle!", .{});
        return;
    }

    if (handle.id == self.default_geometry.id) {
        std.log.warn("GeometrySystem: Cannot release default geometry!", .{});
        return;
    }

    const geometry = self.geometries.getColumnPtrAssumeLive(handle, .geometry);
    const reference_count = self.geometries.getColumnPtrAssumeLive(handle, .reference_count);
    const auto_release = self.geometries.getColumnAssumeLive(handle, .auto_release);

    if (reference_count.* == 0) {
        std.log.warn("GeometrySystem: Cannot release geometry with ref count 0!", .{});
        return;
    }

    reference_count.* -|= 1;

    if (reference_count.* == 0 and auto_release) {
        self.unloadGeometry(handle);
    } else {
        std.log.info("GeometrySystem: Geometry '{s}' was released. Ref count: {}", .{ geometry.name.slice(), reference_count.* });
    }
}

pub fn getDefaultGeometry(self: *const GeometrySystem) GeometryHandle {
    return self.default_geometry;
}

pub fn getDefaultGeometry2D(self: *const GeometrySystem) GeometryHandle {
    return self.default_geometry_2d;
}

// utils
fn createDefaultGeometries(self: *GeometrySystem) !void {
    const vertices_3d = [_]Vertex3D{
        .{ .position = .{ -5.0, -5.0, 0.0 }, .texcoord = .{ 0.0, 0.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
        .{ .position = .{ 5.0, -5.0, 0.0 }, .texcoord = .{ 1.0, 0.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
        .{ .position = .{ 5.0, 5.0, 0.0 }, .texcoord = .{ 1.0, 1.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },
        .{ .position = .{ -5.0, 5.0, 0.0 }, .texcoord = .{ 0.0, 1.0 }, .color = .{ 1.0, 1.0, 0.0, 1.0 } },
    };

    const indices_3d = [_]u32{ 0, 1, 2, 0, 2, 3 };

    var geometry_3d = Geometry.init();
    geometry_3d.name = try Geometry.Name.fromSlice(default_geometry_name);
    geometry_3d.material = Engine.instance.material_system.getDefaultMaterial();
    geometry_3d.generation = null; // NOTE: default geometry always has null generation

    try Engine.instance.renderer.createGeometry(&geometry_3d, &vertices_3d, &indices_3d);
    errdefer Engine.instance.renderer.destroyGeometry(&geometry_3d);

    self.default_geometry = try self.geometries.add(.{
        .geometry = geometry_3d,
        .reference_count = 1,
        .auto_release = false,
    });

    const vertices_2d = [_]Vertex2D{
        .{ .position = .{ -5.0, -5.0 }, .texcoord = .{ 0.0, 0.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
        .{ .position = .{ 5.0, -5.0 }, .texcoord = .{ 1.0, 0.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
        .{ .position = .{ 5.0, 5.0 }, .texcoord = .{ 1.0, 1.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },
        .{ .position = .{ -5.0, 5.0 }, .texcoord = .{ 0.0, 1.0 }, .color = .{ 1.0, 1.0, 0.0, 1.0 } },
    };

    const indices_2d = [_]u32{ 0, 1, 2, 0, 2, 3 };

    var geometry_2d = Geometry.init();
    geometry_2d.name = try Geometry.Name.fromSlice(default_geometry_2d_name);
    geometry_2d.material = Engine.instance.material_system.getDefaultMaterial();
    geometry_2d.generation = null; // NOTE: default geometry always has null generation

    try Engine.instance.renderer.createGeometry(&geometry_2d, &vertices_2d, &indices_2d);
    errdefer Engine.instance.renderer.destroyGeometry(&geometry_2d);

    self.default_geometry_2d = try self.geometries.add(.{
        .geometry = geometry_2d,
        .reference_count = 1,
        .auto_release = false,
    });
}

fn loadGeometry(
    self: *GeometrySystem,
    config: anytype,
    geometry: *Geometry,
) !void {
    _ = self;

    var temp_geometry = Geometry.init();
    temp_geometry.name = try Geometry.Name.fromSlice(config.name);
    temp_geometry.generation = if (geometry.generation) |g| g +% 1 else 0;

    if (config.material_name.len > 0) {
        temp_geometry.material = Engine.instance.material_system.acquireMaterialByName(config.material_name) //
        catch Engine.instance.material_system.getDefaultMaterial();
    }

    try Engine.instance.renderer.createGeometry(&temp_geometry, config.vertices, config.indices);
    errdefer Engine.instance.renderer.destroyGeometry(&temp_geometry);

    Engine.instance.renderer.destroyGeometry(geometry);
    geometry.* = temp_geometry;
}

fn unloadGeometry(self: *GeometrySystem, handle: GeometryHandle) void {
    if (self.geometries.getColumnPtrIfLive(handle, .geometry)) |geometry| {
        const geometry_name = geometry.name; // NOTE: take a copy of the name

        Engine.instance.material_system.releaseMaterialByHandle(geometry.material);
        Engine.instance.renderer.destroyGeometry(geometry);

        self.geometries.removeAssumeLive(handle); // NOTE: this calls geometry.deinit()

        std.log.info("GeometrySystem: Geometry '{s}' was unloaded", .{geometry_name.slice()});
    }
}

fn unloadAllGeometries(self: *GeometrySystem) void {
    var it = self.geometries.liveHandles();
    while (it.next()) |handle| {
        self.unloadGeometry(handle);
    }
}
