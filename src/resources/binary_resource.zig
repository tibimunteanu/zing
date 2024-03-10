const std = @import("std");
const cnt = @import("../cnt.zig");

const Allocator = std.mem.Allocator;

const BinaryResource = @This();

allocator: Allocator,
full_path: []const u8,
bytes: []u8,

pub fn init(allocator: Allocator, path: []const u8) !BinaryResource {
    const path_format = "assets/{s}";

    var file_path_buf: [cnt.max_path_length]u8 = undefined;
    const file_path = try std.fmt.bufPrintZ(&file_path_buf, path_format, .{path});

    const file = try std.fs.cwd().openFile(file_path, .{ .mode = .read_only });
    defer file.close();

    const stat = try file.stat();
    const bytes = try file.readToEndAlloc(allocator, stat.size);
    errdefer allocator.free(bytes);

    return .{
        .allocator = allocator,
        .full_path = try allocator.dupe(u8, file_path),
        .bytes = bytes,
    };
}

pub fn deinit(self: *BinaryResource) void {
    self.allocator.free(self.full_path);
    self.allocator.free(self.bytes);
    self.* = undefined;
}
