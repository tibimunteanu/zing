const std = @import("std");
const pool = @import("zpool");
const math = @import("zmath");

const Engine = @import("../engine.zig").Engine;
const TextureSystem = @import("texture_system.zig").TextureSystem;

const resources_material = @import("../resources/material.zig");
const resources_texture = @import("../resources/texture.zig");

const Material = resources_material.Material;
const MaterialName = resources_material.MaterialName;
const TextureName = resources_texture.TextureName;
const TextureMap = resources_texture.TextureMap;
const Allocator = std.mem.Allocator;

pub const MaterialPool = pool.Pool(16, 16, Material, struct {
    material: Material,
    reference_count: usize,
    auto_release: bool,
});
pub const MaterialHandle = MaterialPool.Handle;

pub const MaterialSystem = struct {
    pub const default_material_name = "default";

    pub const Config = struct {};

    pub const MaterialConfig = struct {
        parsed: ?std.json.Parsed(MaterialConfig) = null,

        name: []const u8 = "New Material",
        diffuse_color: math.Vec = math.Vec{ 1.0, 1.0, 1.0, 1.0 },
        diffuse_map_name: []const u8 = TextureSystem.default_texture_name,
        auto_release: bool = false,

        pub fn initFromFile(allocator: Allocator, path: []const u8) !MaterialConfig {
            const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
            defer file.close();

            const stat = try file.stat();

            const content: [stat.size]u8 = undefined;
            try file.readAll(&content);

            const parsed = try std.json.parseFromSlice(
                MaterialConfig,
                allocator,
                content,
                .{
                    .allocate = .alloc_always,
                    .ignore_unknown_fields = true,
                },
            );
            errdefer parsed.deinit();

            parsed.value.parsed = parsed;

            return parsed.value;
        }

        pub fn deinit(self: *MaterialConfig) void {
            if (self.parsed) |parsed| {
                parsed.deinit();
            }
        }
    };

    allocator: Allocator,
    config: Config,
    default_material: MaterialHandle,
    materials: MaterialPool,
    lookup: std.StringHashMap(MaterialHandle),

    pub fn init(self: *MaterialSystem, allocator: Allocator, config: Config) !void {
        self.allocator = allocator;
        self.config = config;

        self.materials = try MaterialPool.initMaxCapacity(allocator);
        errdefer self.materials.deinit();

        self.lookup = std.StringHashMap(MaterialHandle).init(allocator);
        errdefer self.lookup.deinit();

        try self.lookup.ensureTotalCapacity(@truncate(self.materials.capacity()));

        try self.createDefaultMaterial();
    }

    pub fn deinit(self: *MaterialSystem) void {
        self.unloadAllMaterials();
        self.lookup.deinit();
        self.materials.deinit();
    }

    pub fn acquireMaterialByConfig(self: *MaterialSystem, config: MaterialConfig) !MaterialHandle {
        var material = Material.init();
        try self.loadMaterial(config, &material);

        const handle = try self.materials.add(.{
            .material = material,
            .reference_count = 1,
            .auto_release = config.auto_release,
        });
        errdefer self.materials.removeAssumeLive(handle);

        try self.lookup.put(material.name.slice(), handle);
        errdefer self.lookup.remove(material.name.slice());

        std.log.info("MaterialSystem: Material '{s}' was loaded. Ref count: 1", .{material.name.slice()});

        return handle;
    }

    pub fn acquireMaterialByName(self: *MaterialSystem, name: []const u8) !MaterialHandle {
        if (self.lookup.get(name)) |handle| {
            return self.acquireMaterialByHandle(handle);
        } else {
            const path_format = "assets/materials/{s}.mat.json";

            const config_path = try std.fmt.allocPrintZ(self.allocator, path_format, .{name});
            defer self.allocator.free(config_path);

            const config = try MaterialConfig.initFromFile(config_path);
            defer config.deinit();

            return self.acquireMaterialByConfig(config);
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
            self.unloadMaterial(handle);
        } else {
            std.log.info("MaterialSystem: Material '{s}' was released. Ref count: {}", .{ material.name.slice(), reference_count.* });
        }
    }

    pub fn getDefaultMaterial(self: MaterialSystem) MaterialHandle {
        return self.default_material;
    }

    // utils
    fn createDefaultMaterial(self: *MaterialSystem) !void {
        var material = Material.init();
        material.name = try MaterialName.fromSlice(default_material_name);
        material.diffuse_color = math.Vec{ 1, 1, 1, 1 };
        material.diffuse_map = .{
            .use = .map_diffuse,
            .texture = Engine.instance.texture_system.getDefaultTexture(),
        };
        material.generation = null; // NOTE: default material always has null generation

        try Engine.instance.renderer.createMaterial(&material);
        errdefer Engine.instance.renderer.destroyMaterial(&material);

        self.default_material = try self.materials.add(.{
            .material = material,
            .reference_count = 1,
            .auto_release = false,
        });

        try self.lookup.put(default_material_name, self.default_material);
    }

    fn loadMaterial(self: *MaterialSystem, config: MaterialConfig, material: *Material) !void {
        _ = self;
        var temp_material = Material.init();
        temp_material.name = try MaterialName.fromSlice(config.name);
        temp_material.diffuse_color = config.diffuse_color;

        if (config.diffuse_map_name.len > 0) {
            temp_material.diffuse_map = TextureMap{
                .use = .map_diffuse,
                .texture = Engine.instance.texture_system.acquireTextureByName(
                    config.diffuse_map_name,
                    .{ .auto_release = true },
                ) catch Engine.instance.texture_system.getDefaultTexture(),
            };
        }

        temp_material.generation = if (material.generation) |g| g +% 1 else 0;

        try Engine.instance.renderer.createMaterial(&temp_material);
        errdefer Engine.instance.renderer.destroyMaterial(&temp_material);

        Engine.instance.renderer.destroyMaterial(material);
        material.* = temp_material;
    }

    fn unloadMaterial(self: *MaterialSystem, handle: MaterialHandle) void {
        if (self.materials.getColumnPtrIfLive(handle, .material)) |material| {
            const material_name = material.name; // NOTE: take a copy of the name

            Engine.instance.texture_system.releaseTextureByHandle(material.diffuse_map.texture);
            Engine.instance.renderer.destroyMaterial(material);

            self.materials.removeAssumeLive(handle); // NOTE: this calls material.deinit()
            _ = self.lookup.remove(material_name.slice());

            std.log.info("MaterialSystem: Material '{s}' was unloaded", .{material_name.slice()});
        }
    }

    fn unloadAllMaterials(self: *MaterialSystem) void {
        var it = self.materials.liveHandles();
        while (it.next()) |handle| {
            self.unloadMaterial(handle);
        }
    }
};
