const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("mach-glfw");
const Renderer = @import("renderer/renderer.zig").Renderer;
const Allocator = std.mem.Allocator;
const zm = @import("zmath");

pub var engine: Engine = undefined;

fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}\n", .{ error_code, description });
}

pub const Engine = struct {
    const Self = @This();

    window: glfw.Window,
    renderer: Renderer,

    pub fn init(allocator: Allocator) !Self {
        var self: Self = undefined;

        glfw.setErrorCallback(errorCallback);

        if (!glfw.init(.{})) {
            std.log.err("Failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
            std.process.exit(1);
        }
        errdefer glfw.terminate();

        self.window = glfw.Window.create(960, 540, "Zing", null, null, .{
            .client_api = .no_api,
        }) orelse {
            std.log.err("Failed to create window: {?s}", .{glfw.getErrorString()});
            std.process.exit(1);
        };
        errdefer self.window.destroy();
        self.window.setUserPointer(&engine);

        self.renderer = try Renderer.init(allocator, self.window);

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.renderer.deinit();
        self.window.destroy();
        glfw.terminate();
    }

    pub fn run(self: *Self) !void {
        while (!self.window.shouldClose()) {
            if (self.window.getAttrib(.iconified) == 0) {
                try self.renderer.drawFrame();
            }
            glfw.pollEvents();
        }

        try self.renderer.waitIdle();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit() != .ok) unreachable;
    }
    const allocator = gpa.allocator();

    engine = try Engine.init(allocator);
    defer engine.deinit();

    try engine.run();
}
