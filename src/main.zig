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

    var camera_view: zm.Mat = undefined;
    var camera_view_dirty: bool = true;
    var camera_position: zm.Vec = zm.Vec{ 0.0, 0.0, -30.0, 0.0 };
    var camera_euler: zm.Vec = zm.Vec{ 0.0, 0.0, 0.0, 0.0 }; // pitch, yaw, roll

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
                if (self.window.getKey(.a) == .press) {
                    cameraYaw(0.001);
                }
                if (self.window.getKey(.d) == .press) {
                    cameraYaw(-0.001);
                }
                if (self.window.getKey(.w) == .press) {
                    cameraPitch(0.001);
                }
                if (self.window.getKey(.s) == .press) {
                    cameraPitch(-0.001);
                }

                recomputeCameraView();
                self.renderer.view = camera_view;

                try self.renderer.drawFrame();
            }
            glfw.pollEvents();
        }

        try self.renderer.waitIdle();
    }

    // utils
    fn recomputeCameraView() void {
        if (camera_view_dirty) {
            const rotation = zm.matFromRollPitchYawV(camera_euler);
            const translation = zm.translationV(camera_position);

            camera_view = zm.inverse(zm.mul(rotation, translation));
        }
        camera_view_dirty = false;
    }

    fn cameraPitch(amount: f32) void {
        const limit = 89.0; // prevent gimbal lock
        camera_euler[0] += amount;
        camera_euler[0] = @max(-limit, @min(camera_euler[0], limit));
        camera_view_dirty = true;
    }

    fn cameraYaw(amount: f32) void {
        camera_euler[1] += amount;
        camera_view_dirty = true;
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
