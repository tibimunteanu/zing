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
    diffuse_map_name: []const u8 = Texture.default_name,
    auto_release: bool = false,
};

const MaterialPool = pool.Pool(16, 16, Material, struct {
    material: Material,
    reference_count: usize,
    auto_release: bool,
}, struct {
    pub fn acquire(self: Handle) !Handle {
        if (self.eql(default)) {
            return default;
        }

        const material = try self.get();
        const reference_count = materials.getColumnPtrAssumeLive(self, .reference_count);

        reference_count.* +|= 1;

        std.log.info("Material: Acquire '{s}' ({})", .{ material.name.slice(), reference_count.* });

        return self;
    }

    pub fn release(self: Handle) void {
        if (self.eql(default)) {
            return;
        }

        if (self.getIfExists()) |material| {
            const reference_count = materials.getColumnPtrAssumeLive(self, .reference_count);
            const auto_release = materials.getColumnAssumeLive(self, .auto_release);

            if (reference_count.* == 0) {
                std.log.warn("Material: Release with ref count 0!", .{});
                return;
            }

            reference_count.* -|= 1;

            if (reference_count.* == 0 and auto_release) {
                self.remove();
            } else {
                std.log.info("Material: Release '{s}' ({})", .{ material.name.slice(), reference_count.* });
            }
        } else {
            std.log.warn("Material: Release invalid handle!", .{});
        }
    }

    pub inline fn eql(self: Handle, other: Handle) bool {
        return self.id == other.id;
    }

    pub inline fn isNilOrDefault(self: Handle) bool {
        return self.eql(Handle.nil) or self.eql(default);
    }

    pub inline fn exists(self: Handle) bool {
        return materials.isLiveHandle(self);
    }

    pub inline fn get(self: Handle) !*Material {
        return try materials.getColumnPtr(self, .material);
    }

    pub inline fn getIfExists(self: Handle) ?*Material {
        return materials.getColumnPtrIfLive(self, .material);
    }

    pub inline fn getOrDefault(self: Handle) *Material {
        return materials.getColumnPtrIfLive(self, .material) //
        orelse materials.getColumnPtrAssumeLive(default, .material);
    }

    pub fn remove(self: Handle) void {
        if (self.getIfExists()) |material| {
            std.log.info("Material: Remove '{s}'", .{material.name.slice()});

            _ = lookup.remove(material.name.slice());
            materials.removeAssumeLive(self);

            material.destroy();
        }
    }
});

pub const Handle = MaterialPool.Handle;

pub const default_name = "default";
pub var default: Handle = Handle.nil;

var allocator: Allocator = undefined;
var materials: MaterialPool = undefined;
var lookup: std.StringHashMap(Handle) = undefined;

name: Array(u8, 256),
material_type: Type,
diffuse_color: math.Vec,
diffuse_map: Texture.Map,
generation: ?u32,
instance_handle: ?Shader.InstanceHandle,

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
    var it = materials.liveHandles();
    while (it.next()) |handle| {
        handle.remove();
    }

    lookup.deinit();
    materials.deinit();
}

pub fn acquire(name: []const u8) !Handle {
    if (lookup.get(name)) |handle| {
        return handle.acquire();
    } else {
        var resource = try MaterialResource.init(allocator, name);
        defer resource.deinit();

        var material = try create(resource.config.value);
        errdefer material.destroy();

        const handle = try materials.add(.{
            .material = material,
            .reference_count = 1,
            .auto_release = resource.config.value.auto_release,
        });
        errdefer materials.removeAssumeLive(handle);

        try lookup.put(material.name.slice(), handle);

        std.log.info("Material: Create '{s}' (1)", .{name});

        return handle;
    }
}

pub fn reload(name: []const u8) !void {
    if (lookup.get(name)) |handle| {
        if (handle.getIfExists()) |material| {
            var resource = try MaterialResource.init(allocator, name);
            defer resource.deinit();

            var new_material = try create(resource.config);

            new_material.generation = if (material.generation) |g| g +% 1 else 0;

            material.destroy();
            material.* = new_material;
        }
    } else {
        return error.MaterialDoesNotExist;
    }
}

// utils
fn createDefault() !void {
    var material = try create(Config{
        .name = default_name,
        .material_type = "world",
        .diffuse_color = math.Vec{ 1, 1, 1, 1 },
        .diffuse_map_name = Texture.default_name,
        .auto_release = false,
    });
    material.generation = null; // NOTE: default material must have null generation

    default = try materials.add(.{
        .material = material,
        .reference_count = 1,
        .auto_release = false,
    });

    try lookup.put(default_name, default);

    std.log.info("Material: Create '{s}'", .{default_name});
}

fn create(config: Config) !Material {
    var self: Material = undefined;

    self.name = try Array(u8, 256).fromSlice(config.name);
    self.material_type = if (std.mem.eql(u8, config.material_type, "ui")) .ui else .world;
    self.diffuse_color = config.diffuse_color;
    self.generation = 0;

    const diffuse_texture = Texture.acquire(config.diffuse_map_name, .{ .auto_release = true }) //
    catch Texture.default;

    self.diffuse_map = Texture.Map{
        .use = .map_diffuse,
        .texture = diffuse_texture,
    };

    switch (self.material_type) {
        .world => self.instance_handle = try Renderer.phong_shader.initInstance(),
        .ui => self.instance_handle = try Renderer.ui_shader.initInstance(),
    }

    return self;
}

fn destroy(self: *Material) void {
    if (!self.diffuse_map.texture.isNilOrDefault()) {
        self.diffuse_map.texture.release();
    }

    if (self.instance_handle) |instance_handle| {
        switch (self.material_type) {
            .world => Renderer.phong_shader.deinitInstance(instance_handle),
            .ui => Renderer.ui_shader.deinitInstance(instance_handle),
        }
    }

    self.* = undefined;
}
