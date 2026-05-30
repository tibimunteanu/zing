const std = @import("std");
const config = @import("../config.zig");
const file = @import("file.zig");

const Allocator = std.mem.Allocator;

const BinaryAsset = @This();

allocator: Allocator,
full_path: []const u8,
bytes: []u8,

pub fn init(allocator: Allocator, path: []const u8) !BinaryAsset {
    const path_format = "assets/{s}";

    var file_path_buf: [config.max_path_length]u8 = undefined;
    const file_path = try std.fmt.bufPrintZ(&file_path_buf, path_format, .{path});

    const bytes = try file.readAlloc(allocator, file_path);
    errdefer allocator.free(bytes);

    return .{
        .allocator = allocator,
        .full_path = try allocator.dupe(u8, file_path),
        .bytes = bytes,
    };
}

pub fn deinit(self: *BinaryAsset) void {
    self.allocator.free(self.full_path);
    self.allocator.free(self.bytes);
    self.* = undefined;
}
