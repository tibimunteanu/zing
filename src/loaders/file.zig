const std = @import("std");

var active_io: ?std.Io = null;

pub fn init(io: std.Io) void {
    active_io = io;
}

pub fn readAlloc(allocator: std.mem.Allocator, path: [:0]const u8) ![]u8 {
    const io = active_io orelse return error.FileIoNotInitialized;
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(std.math.maxInt(usize)));
}
