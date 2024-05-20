const std = @import("std");
const pool = @import("zpool");
const math = @import("zmath");

const Engine = @import("../engine.zig");
const TextureSystem = @import("texture_system.zig");
const Material = @import("../renderer/material.zig");
const Texture = @import("../renderer/texture.zig");
const MaterialResource = @import("../resources/material_resource.zig");

const TextureMap = TextureSystem.TextureMap;
const Allocator = std.mem.Allocator;
const Array = std.BoundedArray;

const MaterialSystem = @This();

pub const MaterialPool = pool.Pool(16, 16, Material, struct {
    material: Material,
    reference_count: usize,
    auto_release: bool,
});
pub const MaterialHandle = MaterialPool.Handle;

pub const default_material_name = "default";

allocator: Allocator,
default_material: MaterialHandle,
materials: MaterialPool,
lookup: std.StringHashMap(MaterialHandle),

pub fn init(self: *MaterialSystem, allocator: Allocator) !void {
    self.allocator = allocator;

    self.materials = try MaterialPool.initMaxCapacity(allocator);
    errdefer self.materials.deinit();

    self.lookup = std.StringHashMap(MaterialHandle).init(allocator);
    errdefer self.lookup.deinit();

    try self.lookup.ensureTotalCapacity(@truncate(self.materials.capacity()));

    try self.createDefaultMaterial();
}

pub fn deinit(self: *MaterialSystem) void {
    self.destroyAllMaterials();
    self.lookup.deinit();
    self.materials.deinit();
}

pub fn acquireDefaultMaterial(self: *const MaterialSystem) MaterialHandle {
    return self.default_material;
}

pub fn acquireMaterialByConfig(self: *MaterialSystem, config: Material.Config) !MaterialHandle {
    var material = Material.init();
    try self.createMaterial(config, &material);

    const handle = try self.materials.add(.{
        .material = material,
        .reference_count = 1,
        .auto_release = config.auto_release,
    });
    errdefer self.materials.removeAssumeLive(handle);

    try self.lookup.put(material.name.slice(), handle);
    errdefer self.lookup.remove(material.name.slice());

    std.log.info("MaterialSystem: Create material '{s}'. Ref count: 1", .{material.name.slice()});

    return handle;
}

pub fn acquireMaterialByName(self: *MaterialSystem, name: []const u8) !MaterialHandle {
    if (self.lookup.get(name)) |handle| {
        return self.acquireMaterialByHandle(handle);
    } else {
        var material_resource = try MaterialResource.init(self.allocator, name);
        defer material_resource.deinit();

        return self.acquireMaterialByConfig(material_resource.config.value);
    }
}

pub fn acquireMaterialByHandle(self: *MaterialSystem, handle: MaterialHandle) !MaterialHandle {
    try self.materials.requireLiveHandle(handle);

    if (handle.id == self.default_material.id) {
        std.log.warn("MaterialSystem: Cannot acquire default material. Use getDefaultMaterial() instead!", .{});
        return self.default_material;
    }

    const material = self.materials.getColumnPtrAssumeLive(handle, .material);
    const reference_count = self.materials.getColumnPtrAssumeLive(handle, .reference_count);

    reference_count.* +|= 1;

    std.log.info("MaterialSystem: Material '{s}' was acquired. Ref count: {}", .{ material.name.slice(), reference_count.* });

    return handle;
}

pub fn releaseMaterialByName(self: *MaterialSystem, name: []const u8) void {
    if (self.lookup.get(name)) |handle| {
        self.releaseMaterialByHandle(handle);
    } else {
        std.log.warn("MaterialSystem: Cannot release non-existent material!", .{});
    }
}

pub fn releaseMaterialByHandle(self: *MaterialSystem, handle: MaterialHandle) void {
    if (!self.materials.isLiveHandle(handle)) {
        std.log.warn("MaterialSystem: Cannot release material with invalid handle!", .{});
        return;
    }

    if (handle.id == self.default_material.id) {
        std.log.warn("MaterialSystem: Cannot release default material!", .{});
        return;
    }

    const material = self.materials.getColumnPtrAssumeLive(handle, .material);
    const reference_count = self.materials.getColumnPtrAssumeLive(handle, .reference_count);
    const auto_release = self.materials.getColumnAssumeLive(handle, .auto_release);

    if (reference_count.* == 0) {
        std.log.warn("MaterialSystem: Cannot release material with ref count 0!", .{});
        return;
    }

    reference_count.* -|= 1;

    if (reference_count.* == 0 and auto_release) {
        self.destroyMaterial(handle);
    } else {
        std.log.info("MaterialSystem: Material '{s}' was released. Ref count: {}", .{ material.name.slice(), reference_count.* });
    }
}

// utils
fn createDefaultMaterial(self: *MaterialSystem) !void {
    var material = Material.init();
    material.name = try Array(u8, 256).fromSlice(default_material_name);
    material.diffuse_color = math.Vec{ 1, 1, 1, 1 };
    material.diffuse_map = .{
        .use = .map_diffuse,
        .texture = Engine.instance.texture_system.acquireDefaultTexture(),
    };
    material.generation = null; // NOTE: default material always has null generation

    try Engine.renderer.createMaterial(&material);
    errdefer Engine.renderer.destroyMaterial(&material);

    self.default_material = try self.materials.add(.{
        .material = material,
        .reference_count = 1,
        .auto_release = false,
    });

    try self.lookup.put(default_material_name, self.default_material);
}

fn createMaterial(self: *MaterialSystem, config: Material.Config, material: *Material) !void {
    _ = self;
    var temp_material = Material.init();
    temp_material.name = try Array(u8, 256).fromSlice(config.name);
    temp_material.material_type = if (std.mem.eql(u8, config.material_type, "ui")) .ui else .world;
    temp_material.diffuse_color = config.diffuse_color;

    if (config.diffuse_map_name.len > 0) {
        temp_material.diffuse_map = TextureMap{
            .use = .map_diffuse,
            .texture = Engine.instance.texture_system.acquireTextureByName(
                config.diffuse_map_name,
                .{ .auto_release = true },
            ) catch Engine.instance.texture_system.acquireDefaultTexture(),
        };
    }

    temp_material.generation = if (material.generation) |g| g +% 1 else 0;

    try Engine.renderer.createMaterial(&temp_material);
    errdefer Engine.renderer.destroyMaterial(&temp_material);

    Engine.renderer.destroyMaterial(material);
    material.* = temp_material;
}

fn destroyMaterial(self: *MaterialSystem, handle: MaterialHandle) void {
    if (self.materials.getColumnPtrIfLive(handle, .material)) |material| {
        std.log.info("MaterialSystem: Destroy material '{s}'", .{material.name.slice()});

        const material_name = material.name; // NOTE: take a copy of the name

        Engine.instance.texture_system.releaseTextureByHandle(material.diffuse_map.texture);
        Engine.renderer.destroyMaterial(material);

        self.materials.removeAssumeLive(handle); // NOTE: this calls material.deinit()
        _ = self.lookup.remove(material_name.slice());
    }
}

fn destroyAllMaterials(self: *MaterialSystem) void {
    var it = self.materials.liveHandles();
    while (it.next()) |handle| {
        self.destroyMaterial(handle);
    }
}
