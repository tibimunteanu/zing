const std = @import("std");
const Shader = @import("../renderer/shader.zig");

const Allocator = std.mem.Allocator;

const ShaderResource = @This();

allocator: Allocator,
name: []const u8,
full_path: []const u8,
config: std.json.Parsed(Shader.Config),

pub fn init(allocator: Allocator, name: []const u8) !ShaderResource {
    const path_format = "assets/shaders/{s}.shader.json";

    const file_path = try std.fmt.allocPrintZ(allocator, path_format, .{name});
    defer allocator.free(file_path);

    const file = try std.fs.cwd().openFile(file_path, .{ .mode = .read_only });
    defer file.close();

    const stat = try file.stat();
    const bytes = try file.readToEndAlloc(allocator, stat.size);
    defer allocator.free(bytes);

    const config = try std.json.parseFromSlice(
        Shader.Config,
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

pub fn deinit(self: *ShaderResource) void {
    self.allocator.free(self.name);
    self.allocator.free(self.full_path);
    self.config.deinit();
    self.* = undefined;
}
