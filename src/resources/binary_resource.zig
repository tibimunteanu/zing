const std = @import("std");
const stbi = @import("zstbi");
const Allocator = std.mem.Allocator;

pub const BinaryResource = struct {
    allocator: Allocator,
    full_path: []const u8,
    bytes: []u8,

    pub fn init(allocator: Allocator, path: []const u8) !BinaryResource {
        const path_format = "assets/{s}";

        const file_path = try std.fmt.allocPrintZ(allocator, path_format, .{path});
        defer allocator.free(file_path);

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
};