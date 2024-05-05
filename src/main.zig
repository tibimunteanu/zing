const std = @import("std");
const Engine = @import("engine.zig");

const Shader = @import("renderer/shader.zig");
const ShaderResource = @import("resources/shader_resource.zig");

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

    var shader_resource = try ShaderResource.init(allocator, "phong");
    defer shader_resource.deinit();

    var shader = try Shader.init(allocator, shader_resource.config.value);
    defer shader.deinit();

    try Engine.run();
}
