const std = @import("std");
const pool = @import("zpool");
const math = @import("zmath");

const Engine = @import("../engine.zig").Engine;

const renderer_types = @import("../renderer/renderer_types.zig");
const resources_geometry = @import("../resources/geometry.zig");
const resources_material = @import("../resources/material.zig");
const resources_texture = @import("../resources/texture.zig");

const Vertex = renderer_types.Vertex;

const Geometry = resources_geometry.Geometry;
const GeometryName = resources_geometry.GeometryName;
const MaterialName = resources_material.MaterialName;

const Allocator = std.mem.Allocator;

pub const GeometryPool = pool.Pool(16, 16, Geometry, struct {
    geometry: Geometry,
    reference_count: usize,
    auto_release: bool,
});
pub const GeometryHandle = GeometryPool.Handle;

pub const GeometrySystem = struct {
    pub const default_geometry_name = "default";

    pub const Config = struct {};

    pub const GeometryConfig = struct {
        allocator: Allocator,

        name: []const u8,
        vertices: []const Vertex,
        indices: []const u32,
        material_name: []const u8,

        // pub fn initFromFile(allocator: Allocator, path: []const u8) !GeometryConfig {
        //     const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
        //     defer file.close();

        //     const stat = try file.stat();
        //     const content = try file.readToEndAlloc(allocator, stat.size);
        //     defer allocator.free(content);

        //     const parsed = try std.json.parseFromSlice(
        //         struct {
        //             name: []const u8,
        //             diffuse_color: math.Vec,
        //             diffuse_map_name: []const u8,
        //             auto_release: bool = false,
        //         },
        //         allocator,
        //         content,
        //         .{
        //             .allocate = .alloc_always,
        //             .ignore_unknown_fields = true,
        //         },
        //     );
        //     defer parsed.deinit();

        //     return GeometryConfig{
        //         .allocator = allocator,
        //         .name = try GeometryName.fromSlice(parsed.value.name),
        //         .diffuse_color = parsed.value.diffuse_color,
        //         .diffuse_map_name = try TextureName.fromSlice(parsed.value.diffuse_map_name),
        //         .auto_release = parsed.value.auto_release,
        //     };
        // }

        // pub fn initPlane(
        //     allocator: Allocator,
        //     width: f32,
        //     height: f32,
        //     segment_count_x: u32,
        //     segment_count_y: u32,
        //     tile_x: u32,
        //     tile_y: u32,
        //     name: []const u8,
        //     material_name: []const u8,
        // ) !GeometryConfig {
        //     //
        // }

        // pub fn deinit(self: *GeometryConfig) void {
        //     _ = self;
        //     // TODO: free allocated name, vertices, indices and material_name
        // }
    };

    allocator: Allocator,
    config: Config,
    default_geometry: GeometryHandle,
    geometries: GeometryPool,

    pub fn init(self: *GeometrySystem, allocator: Allocator, config: Config) !void {
        self.allocator = allocator;
        self.config = config;

        self.geometries = try GeometryPool.initMaxCapacity(allocator);
        errdefer self.geometries.deinit();

        try self.createDefaultGeometry();
    }

    pub fn deinit(self: *GeometrySystem) void {
        self.unloadAllGeometries();
        self.geometries.deinit();
    }

    pub fn acquireGeometryByConfig(
        self: *GeometrySystem,
        config: GeometryConfig,
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

    pub fn getDefaultGeometry(self: GeometrySystem) GeometryHandle {
        return self.default_geometry;
    }

    // utils
    fn createDefaultGeometry(self: *GeometrySystem) !void {
        const vertices = [_]Vertex{
            .{ .position = .{ -5.0, -5.0, 0.0 }, .texcoord = .{ 0.0, 0.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
            .{ .position = .{ 5.0, -5.0, 0.0 }, .texcoord = .{ 1.0, 0.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
            .{ .position = .{ 5.0, 5.0, 0.0 }, .texcoord = .{ 1.0, 1.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },
            .{ .position = .{ -5.0, 5.0, 0.0 }, .texcoord = .{ 0.0, 1.0 }, .color = .{ 1.0, 1.0, 0.0, 1.0 } },
        };

        const indices = [_]u32{ 0, 1, 2, 0, 2, 3 };

        var geometry = Geometry.init();
        geometry.name = try GeometryName.fromSlice(default_geometry_name);
        geometry.material = Engine.instance.material_system.getDefaultMaterial();
        geometry.generation = null; // NOTE: default geometry always has null generation

        try Engine.instance.renderer.createGeometry(&geometry, &vertices, &indices);
        errdefer Engine.instance.renderer.destroyGeometry(&geometry);

        self.default_geometry = try self.geometries.add(.{
            .geometry = geometry,
            .reference_count = 1,
            .auto_release = false,
        });
    }

    fn loadGeometry(self: *GeometrySystem, config: GeometryConfig, geometry: *Geometry) !void {
        _ = self;
        var temp_geometry = Geometry.init();
        temp_geometry.name = config.name;
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
};
