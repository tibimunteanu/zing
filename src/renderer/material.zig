const std = @import("std");
const pool = @import("zpool");
const math = @import("zmath");

const Renderer = @import("renderer.zig");
const Texture = @import("texture.zig");
const Shader = @import("shader.zig");
const MaterialResource = @import("../resources/material_resource.zig");

const Allocator = std.mem.Allocator;
const Array = std.BoundedArray;

const Material = @This();

pub const Type = enum {
    world,
    ui,
};

pub const Config = struct {
    name: []const u8 = "New Material",
    material_type: []const u8 = "world",
    diffuse_color: math.Vec = math.Vec{ 1.0, 1.0, 1.0, 1.0 },
    diffuse_map_name: []const u8 = Texture.default_texture_name,
    auto_release: bool = false,
};

const MaterialPool = pool.Pool(16, 16, Material, struct {
    material: Material,
    reference_count: usize,
    auto_release: bool,
});
pub const Handle = MaterialPool.Handle;

pub const default_material_name = "default";

var allocator: Allocator = undefined;
var materials: MaterialPool = undefined;
var lookup: std.StringHashMap(Handle) = undefined;
var default_material: Handle = Handle.nil;

name: Array(u8, 256) = .{},
material_type: Type = .world,
diffuse_color: math.Vec = math.Vec{ 0, 0, 0, 0 },
diffuse_map: Texture.Map = .{},
generation: ?u32 = null,
instance_handle: ?Shader.InstanceHandle = null,

pub fn initSystem(ally: Allocator) !void {
    allocator = ally;

    materials = try MaterialPool.initMaxCapacity(allocator);
    errdefer materials.deinit();

    lookup = std.StringHashMap(Handle).init(allocator);
    errdefer lookup.deinit();

    try lookup.ensureTotalCapacity(@truncate(materials.capacity()));

    try createDefault();
}

pub fn deinitSystem() void {
    removeAll();
    lookup.deinit();
    materials.deinit();
}

pub fn acquireDefault() Handle {
    return default_material;
}

pub fn acquireByConfig(config: Config) !Handle {
    var material = try create(config);
    errdefer material.destroy();

    const handle = try materials.add(.{
        .material = material,
        .reference_count = 1,
        .auto_release = config.auto_release,
    });
    errdefer materials.removeAssumeLive(handle);

    try lookup.put(material.name.slice(), handle);

    std.log.info("Material: Create material '{s}'. Ref count: 1", .{material.name.slice()});

    return handle;
}

pub fn acquireByName(name: []const u8) !Handle {
    if (lookup.get(name)) |handle| {
        return acquireByHandle(handle);
    } else {
        var material_resource = try MaterialResource.init(allocator, name);
        defer material_resource.deinit();

        return acquireByConfig(material_resource.config.value);
    }
}

pub fn acquireByHandle(handle: Handle) !Handle {
    try materials.requireLiveHandle(handle);

    if (handle.id == default_material.id) {
        std.log.warn("Material: Cannot acquire default material. Use getDefaultMaterial() instead!", .{});
        return default_material;
    }

    const material = materials.getColumnPtrAssumeLive(handle, .material);
    const reference_count = materials.getColumnPtrAssumeLive(handle, .reference_count);

    reference_count.* +|= 1;

    std.log.info("Material: Material '{s}' was acquired. Ref count: {}", .{ material.name.slice(), reference_count.* });

    return handle;
}

pub fn releaseByName(name: []const u8) void {
    if (lookup.get(name)) |handle| {
        releaseByHandle(handle);
    } else {
        std.log.warn("Material: Cannot release non-existent material!", .{});
    }
}

pub fn releaseByHandle(handle: Handle) void {
    if (!materials.isLiveHandle(handle)) {
        std.log.warn("Material: Cannot release material with invalid handle!", .{});
        return;
    }

    if (handle.id == default_material.id) {
        std.log.warn("Material: Cannot release default material!", .{});
        return;
    }

    const material = materials.getColumnPtrAssumeLive(handle, .material);
    const reference_count = materials.getColumnPtrAssumeLive(handle, .reference_count);
    const auto_release = materials.getColumnAssumeLive(handle, .auto_release);

    if (reference_count.* == 0) {
        std.log.warn("Material: Cannot release material with ref count 0!", .{});
        return;
    }

    reference_count.* -|= 1;

    if (reference_count.* == 0 and auto_release) {
        remove(handle);
    } else {
        std.log.info("Material: Material '{s}' was released. Ref count: {}", .{ material.name.slice(), reference_count.* });
    }
}

pub fn reload(name: []const u8) !void {
    if (lookup.get(name)) |handle| {
        if (getIfExists(handle)) |material| {
            var material_resource = try MaterialResource.init(allocator, name);
            defer material_resource.deinit();

            var new_material = try create(material_resource.config);

            new_material.generation = if (material.generation) |g| g +% 1 else 0;

            material.destroy();
            material.* = new_material;
        }
    } else {
        return error.MaterialDoesNotExist;
    }
}

pub inline fn exists(handle: Handle) bool {
    return materials.isLiveHandle(handle);
}

pub inline fn get(handle: Handle) !*Material {
    return try materials.getColumnPtr(handle, .material);
}

pub inline fn getIfExists(handle: Handle) ?*Material {
    return materials.getColumnPtrIfLive(handle, .material);
}

pub inline fn getOrDefault(handle: Handle) *Material {
    return materials.getColumnPtrIfLive(handle, .material) //
    orelse materials.getColumnPtrAssumeLive(default_material, .material);
}

// utils
fn create(config: Config) !Material {
    var self: Material = undefined;

    self.name = try Array(u8, 256).fromSlice(config.name);
    self.material_type = if (std.mem.eql(u8, config.material_type, "ui")) .ui else .world;
    self.diffuse_color = config.diffuse_color;

    const diffuse_texture = Texture.acquireByName(config.diffuse_map_name, .{ .auto_release = true }) //
    catch Texture.acquireDefault();

    self.diffuse_map = Texture.Map{
        .use = .map_diffuse,
        .texture = diffuse_texture,
    };

    switch (self.material_type) {
        .world => self.instance_handle = try Renderer.phong_shader.initInstance(),
        .ui => self.instance_handle = try Renderer.ui_shader.initInstance(),
    }

    self.generation = 0;

    return self;
}

fn createDefault() !void {
    var material = try create(Config{
        .name = default_material_name,
        .material_type = "world",
        .diffuse_color = math.Vec{ 1, 1, 1, 1 },
        .diffuse_map_name = Texture.default_texture_name,
        .auto_release = false,
    });
    material.generation = null; // NOTE: default material must have null generation

    default_material = try materials.add(.{
        .material = material,
        .reference_count = 1,
        .auto_release = false,
    });

    try lookup.put(default_material_name, default_material);

    std.log.info("Material: Create default material '{s}'. Ref count: 1", .{material.name.slice()});
}

fn destroy(self: *Material) void {
    if (self.diffuse_map.texture.id != Texture.Handle.nil.id) {
        Texture.releaseByHandle(self.diffuse_map.texture);
    }

    if (self.instance_handle) |instance_handle| {
        switch (self.material_type) {
            .world => Renderer.phong_shader.deinitInstance(instance_handle),
            .ui => Renderer.ui_shader.deinitInstance(instance_handle),
        }
    }

    self.* = undefined;
}

fn remove(handle: Handle) void {
    if (materials.getColumnPtrIfLive(handle, .material)) |material| {
        std.log.info("Material: Remove material '{s}'", .{material.name.slice()});

        _ = lookup.remove(material.name.slice());
        materials.removeAssumeLive(handle);

        material.destroy();
    }
}

fn removeAll() void {
    var it = materials.liveHandles();
    while (it.next()) |handle| {
        remove(handle);
    }
}
