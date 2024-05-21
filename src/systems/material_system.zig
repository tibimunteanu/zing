const std = @import("std");
const pool = @import("zpool");
const math = @import("zmath");

const zing = @import("../zing.zig");
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
    const diffuse_texture = zing.sys.texture.acquireTextureByName(config.diffuse_map_name, .{ .auto_release = true }) //
    catch zing.sys.texture.acquireDefaultTexture();

    var material = try Material.init(
        config.name,
        if (std.mem.eql(u8, config.material_type, "ui")) .ui else .world,
        config.diffuse_color,
        diffuse_texture,
    );
    errdefer material.deinit();

    material.generation = if (material.generation) |g| g +% 1 else 0;

    const handle = try self.materials.add(.{
        .material = material,
        .reference_count = 1,
        .auto_release = config.auto_release,
    });
    errdefer self.materials.removeAssumeLive(handle);

    try self.lookup.put(material.name.slice(), handle);

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

pub inline fn exists(self: *MaterialSystem, handle: MaterialHandle) bool {
    return self.materials.isLiveHandle(handle);
}

pub inline fn get(self: *MaterialSystem, handle: MaterialHandle) !*Material {
    return try self.materials.getColumnPtr(handle, .material);
}

pub inline fn getIfExists(self: *MaterialSystem, handle: MaterialHandle) ?*Material {
    return self.materials.getColumnPtrIfLive(handle, .material);
}

// utils
fn createDefaultMaterial(self: *MaterialSystem) !void {
    const material = try Material.init(
        default_material_name,
        .world,
        math.Vec{ 1, 1, 1, 1 },
        zing.sys.texture.acquireDefaultTexture(),
    );

    self.default_material = try self.materials.add(.{
        .material = material,
        .reference_count = 1,
        .auto_release = false,
    });

    try self.lookup.put(default_material_name, self.default_material);

    std.log.info("MaterialSystem: Create default material '{s}'. Ref count: 1", .{material.name.slice()});
}

fn destroyMaterial(self: *MaterialSystem, handle: MaterialHandle) void {
    if (self.materials.getColumnPtrIfLive(handle, .material)) |material| {
        std.log.info("MaterialSystem: Destroy material '{s}'", .{material.name.slice()});

        _ = self.lookup.remove(material.name.slice());
        self.materials.removeAssumeLive(handle); // NOTE: this calls material.deinit()
    }
}

fn destroyAllMaterials(self: *MaterialSystem) void {
    var it = self.materials.liveHandles();
    while (it.next()) |handle| {
        self.destroyMaterial(handle);
    }
}
