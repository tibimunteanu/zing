const std = @import("std");
const Engine = @import("engine.zig").Engine;
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit() != .ok) unreachable;
    }
    const allocator = gpa.allocator();

    try Engine.init(allocator);
    defer Engine.deinit();

    try Engine.run();
}
