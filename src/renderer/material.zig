const std = @import("std");
const pool = @import("zpool");
const math = @import("zmath");

const Texture = @import("texture.zig");
const Shader = @import("shader.zig");
const MaterialAsset = @import("../loaders/material_asset.zig");

const Allocator = std.mem.Allocator;
const Array = std.BoundedArray;

const Material = @This();

pub const Config = struct {
    name: []const u8 = "New Material",
    shader_name: []const u8 = Shader.default_name,
    properties: []const PropertyConfig = &[_]PropertyConfig{},
    auto_release: bool = false,

    pub const PropertyConfig = struct {
        name: []const u8,
        data_type: []const u8,
        value: std.json.Value,
    };
};

const MaterialPool = pool.Pool(16, 16, Material, struct {
    material: Material,
    reference_count: usize,
    auto_release: bool,
});

pub const Handle = MaterialPool.Handle;

pub const default_name = "default";
pub var default: Handle = Handle.nil;

var allocator: Allocator = undefined;
var materials: MaterialPool = undefined;
var lookup: std.StringHashMap(Handle) = undefined;

name: Array(u8, 256),
shader: Shader.Handle,
properties: std.ArrayList(Property),
instance_handle: ?Shader.InstanceHandle,
generation: ?u32,

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
        remove(handle);
    }

    lookup.deinit();
    materials.deinit();
}

pub fn acquire(name: []const u8) !Handle {
    if (lookup.get(name)) |handle| {
        return acquireExisting(handle);
    } else {
        var asset = try MaterialAsset.init(allocator, name);
        defer asset.deinit();

        var material = try create(asset.config.value);
        errdefer material.destroy();

        const handle = try materials.add(.{
            .material = material,
            .reference_count = 1,
            .auto_release = asset.config.value.auto_release,
        });
        errdefer materials.removeAssumeLive(handle);

        const material_ptr = try get(handle); // NOTE: use name from ptr as key
        try lookup.put(material_ptr.name.constSlice(), handle);

        std.log.info("Material: Create '{s}' (1)", .{name});

        return handle;
    }
}

pub fn reload(name: []const u8) !void {
    if (lookup.get(name)) |handle| {
        var material = try handle.get();

        var resource = try MaterialAsset.init(allocator, name);
        defer resource.deinit();

        var new_material = try create(resource.config);

        new_material.generation = if (material.generation) |g| g +% 1 else 0;

        material.destroy();
        material.* = new_material;
    } else {
        return error.MaterialDoesNotExist;
    }
}

// handle
pub fn acquireExisting(handle: Handle) !Handle {
    if (eql(handle, default)) {
        return default;
    }

    const material = try get(handle);
    const reference_count = materials.getColumnPtrAssumeLive(handle, .reference_count);

    reference_count.* +|= 1;

    std.log.info("Material: Acquire '{s}' ({})", .{ material.name.slice(), reference_count.* });

    return handle;
}

pub fn release(handle: Handle) void {
    if (eql(handle, default)) {
        return;
    }

    if (getIfExists(handle)) |material| {
        const reference_count = materials.getColumnPtrAssumeLive(handle, .reference_count);
        const auto_release = materials.getColumnAssumeLive(handle, .auto_release);

        if (reference_count.* == 0) {
            std.log.warn("Material: Release with ref count 0!", .{});
            return;
        }

        reference_count.* -|= 1;

        if (auto_release and reference_count.* == 0) {
            remove(handle);
        } else {
            std.log.info("Material: Release '{s}' ({})", .{ material.name.slice(), reference_count.* });
        }
    } else {
        std.log.warn("Material: Release invalid handle!", .{});
    }
}

pub inline fn eql(left: Handle, right: Handle) bool {
    return left.id == right.id;
}

pub inline fn isNilOrDefault(handle: Handle) bool {
    return eql(handle, Handle.nil) or eql(handle, default);
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
    orelse materials.getColumnPtrAssumeLive(default, .material);
}

pub fn remove(handle: Handle) void {
    if (getIfExists(handle)) |material| {
        std.log.info("Material: Remove '{s}'", .{material.name.slice()});

        _ = lookup.remove(material.name.slice());
        materials.removeAssumeLive(handle);

        material.destroy();
    }
}

// utils
fn createDefault() !void {
    var diffuse_color = try std.ArrayList(std.json.Value).initCapacity(allocator, 4);
    defer diffuse_color.deinit();

    try diffuse_color.appendNTimes(.{ .float = 1.0 }, 4);

    var material = try create(Config{
        .name = default_name,
        .shader_name = Shader.default_name,
        .properties = &[_]Config.PropertyConfig{
            .{
                .name = "diffuse_color",
                .data_type = "float32_4",
                .value = std.json.Value{ .array = diffuse_color },
            },
            .{
                .name = "diffuse_texture",
                .data_type = "sampler",
                .value = .{ .string = Texture.default_name },
            },
        },
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

    self.shader = Shader.acquire(config.shader_name) catch Shader.default;

    self.properties = try std.ArrayList(Property).initCapacity(allocator, config.properties.len);
    for (config.properties) |prop_config| {
        try self.properties.append(try Property.fromConfig(prop_config));
    }

    self.instance_handle = try Shader.createInstance(self.shader);

    self.generation = 0;

    return self;
}

fn destroy(self: *Material) void {
    if (self.instance_handle) |instance_handle| {
        Shader.destroyInstance(self.shader, instance_handle);
    }

    for (self.properties.items) |property| {
        if (property.getDataType() == .sampler and !Texture.isNilOrDefault(property.value.sampler)) {
            Texture.release(property.value.sampler);
        }
    }
    self.properties.deinit();

    if (!Shader.isNilOrDefault(self.shader)) {
        Shader.release(self.shader);
    }

    self.* = undefined;
}

pub const Property = struct {
    name: Array(u8, 128),
    value: Value,

    pub const Value = union(Shader.Uniform.DataType) {
        int8: i8,
        uint8: u8,
        int16: i16,
        uint16: u16,
        int32: i32,
        uint32: u32,
        float32: f32,
        float32_2: [2]f32,
        float32_3: [3]f32,
        float32_4: [4]f32,
        mat4: math.Mat,
        sampler: Texture.Handle,
    };

    pub fn getDataType(self: Property) Shader.Uniform.DataType {
        return std.meta.activeTag(self.value);
    }

    pub fn fromConfig(config: Config.PropertyConfig) !Property {
        var self: Property = undefined;

        self.name = try Array(u8, 128).fromSlice(config.name);
        const data_type = try Shader.Uniform.DataType.parse(config.data_type);

        if (switch (data_type) {
            .int8, .uint8, .int16, .uint16, .int32, .uint32 => config.value != .integer,
            .float32 => config.value != .float,
            .sampler => config.value != .string,
            .float32_2, .float32_3, .float32_4, .mat4 => config.value != .array,
        }) {
            return error.IncompatibleDataType;
        }

        self.value = switch (data_type) {
            .int8 => .{ .int8 = @intCast(config.value.integer) },
            .uint8 => .{ .uint8 = @intCast(config.value.integer) },
            .int16 => .{ .int16 = @intCast(config.value.integer) },
            .uint16 => .{ .uint16 = @intCast(config.value.integer) },
            .int32 => .{ .int32 = @intCast(config.value.integer) },
            .uint32 => .{ .uint32 = @intCast(config.value.integer) },
            .float32 => .{ .float32 = @floatCast(config.value.float) },
            .float32_2 => blk: {
                var value: [2]f32 = undefined;
                for (config.value.array.items, 0..) |item, i| {
                    value[i] = @floatCast(item.float);
                }
                break :blk .{ .float32_2 = value };
            },
            .float32_3 => blk: {
                var value: [3]f32 = undefined;
                for (config.value.array.items, 0..) |item, i| {
                    value[i] = @floatCast(item.float);
                }
                break :blk .{ .float32_3 = value };
            },
            .float32_4 => blk: {
                var value: [4]f32 = undefined;
                for (config.value.array.items, 0..) |item, i| {
                    value[i] = @floatCast(item.float);
                }
                break :blk .{ .float32_4 = value };
            },
            .mat4 => blk: {
                var value: [16]f32 = undefined;
                for (config.value.array.items, 0..) |item, i| {
                    value[i] = @floatCast(item.float);
                }
                break :blk .{ .mat4 = math.matFromArr(value) };
            },
            .sampler => .{ .sampler = Texture.acquire(config.value.string) catch Texture.default },
        };

        return self;
    }
};
