const std = @import("std");

const Engine = @import("engine.zig");

const Allocator = std.mem.Allocator;

// pub const std_options: std.Options = .{
//     .log_level = .info,
//     .log_scope_levels = &[_]std.log.ScopeLevel{
//         .{ .scope = .some_scope, .level = .err },
//     },
// };

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
