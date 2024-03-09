const std = @import("std");
const stbi = @import("zstbi");
const math = @import("zmath");

const TextureSystem = @import("../systems/texture_system.zig").TextureSystem;
const TextureMap = @import("image_resource.zig").TextureMap;

const Allocator = std.mem.Allocator;

pub const MaterialConfig = struct {
    name: []const u8 = "New Material",
    material_type: []const u8 = "world",
    diffuse_color: math.Vec = math.Vec{ 1.0, 1.0, 1.0, 1.0 },
    diffuse_map_name: []const u8 = TextureSystem.default_texture_name,
    auto_release: bool = false,
};

pub const MaterialResource = struct {
    allocator: Allocator,
    name: []const u8,
    full_path: []const u8,
    config: std.json.Parsed(MaterialConfig),

    pub fn init(allocator: Allocator, name: []const u8) !MaterialResource {
        const path_format = "assets/materials/{s}.mat.json";

        const file_path = try std.fmt.allocPrintZ(allocator, path_format, .{name});
        defer allocator.free(file_path);

        const file = try std.fs.cwd().openFile(file_path, .{ .mode = .read_only });
        defer file.close();

        const stat = try file.stat();
        const bytes = try file.readToEndAlloc(allocator, stat.size);
        defer allocator.free(bytes);

        const config = try std.json.parseFromSlice(
            MaterialConfig,
            allocator,
            bytes,
            .{
                .allocate = .alloc_always,
                .ignore_unknown_fields = true,
            },
        );
        errdefer config.deinit();

        return .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .full_path = try allocator.dupe(u8, file_path),
            .config = config,
        };
    }

    pub fn deinit(self: *MaterialResource) void {
        self.allocator.free(self.name);
        self.allocator.free(self.full_path);
        self.config.deinit();
        self.* = undefined;
    }
};

pub const MaterialName = std.BoundedArray(u8, 256);

pub const MaterialTypes = enum {
    world,
    ui,
};

pub const Material = struct {
    name: MaterialName = .{},
    material_type: MaterialTypes = .world,
    diffuse_color: math.Vec = math.Vec{ 0, 0, 0, 0 },
    diffuse_map: TextureMap = .{},
    generation: ?u32 = null,
    internal_id: ?u32 = null,

    pub fn init() Material {
        return .{};
    }

    pub fn deinit(self: *Material) void {
        self.* = .{};
    }
};
