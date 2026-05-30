const std = @import("std");
const Allocator = std.mem.Allocator;

const Engine = @import("engine.zig");
const file = @import("loaders/file.zig");

// pub const std_options: std.Options = .{
//     .log_level = .info,
//     .log_scope_levels = &.{
//         .{ .scope = .some_scope, .level = .err },
//     },
// };

pub fn main(init: std.process.Init) !void {
    file.init(init.io);

    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        if (gpa.deinit() != .ok) unreachable;
    }
    const allocator = gpa.allocator();

    try Engine.init(allocator);
    defer Engine.deinit();

    try Engine.run();
}
