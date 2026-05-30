const std = @import("std");

const Material = @import("../renderer/material.zig");
const file = @import("file.zig");

const Allocator = std.mem.Allocator;

const MaterialAsset = @This();

allocator: Allocator,
name: []const u8,
full_path: []const u8,
config: std.json.Parsed(Material.Config),

pub fn init(allocator: Allocator, name: []const u8) !MaterialAsset {
    const path_format = "assets/materials/{s}.mat.json";

    const file_path = try std.fmt.allocPrintSentinel(allocator, path_format, .{name}, 0);
    defer allocator.free(file_path);

    const bytes = try file.readAlloc(allocator, file_path);
    defer allocator.free(bytes);

    const config = try std.json.parseFromSlice(
        Material.Config,
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

pub fn deinit(self: *MaterialAsset) void {
    self.allocator.free(self.name);
    self.allocator.free(self.full_path);
    self.config.deinit();
    self.* = undefined;
}
