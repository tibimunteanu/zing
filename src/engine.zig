const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("mach-glfw");
const Renderer = @import("renderer/renderer.zig").Renderer;
const zm = @import("zmath");
const utils = @import("utils.zig");
const Allocator = std.mem.Allocator;

fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}\n", .{ error_code, description });
}

pub const Engine = struct {
    pub var instance: Engine = undefined;

    const target_frame_seconds: f64 = 1.0 / 60.0;

    allocator: Allocator,
    window: glfw.Window,
    renderer: *Renderer,
    last_time: f64,
    frame_count: f64,

    var camera_view: zm.Mat = undefined;
    var camera_view_dirty: bool = true;
    var camera_position: zm.Vec = zm.Vec{ 0.0, 0.0, -30.0, 0.0 };
    var camera_euler: zm.Vec = zm.splat(zm.Vec, 0.0); // pitch, yaw, roll

    pub fn init(allocator: Allocator) !void {
        instance.allocator = allocator;

        glfw.setErrorCallback(errorCallback);

        if (!glfw.init(.{})) {
            std.log.err("Failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
            std.process.exit(1);
        }
        errdefer glfw.terminate();

        instance.window = glfw.Window.create(960, 540, "Zing", null, null, .{
            .client_api = .no_api,
        }) orelse {
            std.log.err("Failed to create window: {?s}", .{glfw.getErrorString()});
            std.process.exit(1);
        };
        errdefer instance.window.destroy();

        instance.renderer = try allocator.create(Renderer);
        errdefer allocator.destroy(instance.renderer);

        try instance.renderer.init(allocator, instance.window);
        errdefer instance.renderer.deinit();
    }

    pub fn deinit() void {
        instance.renderer.deinit();
        instance.allocator.destroy(instance.renderer);
        instance.window.destroy();
        glfw.terminate();
    }

    pub fn run() !void {
        instance.last_time = glfw.getTime();
        instance.frame_count = 0;

        while (!instance.window.shouldClose()) {
            if (instance.window.getAttrib(.iconified) == 0) {
                const frame_start_time = glfw.getTime();
                const precise_delta_time = frame_start_time - instance.last_time;
                const delta_time: f32 = @as(f32, @floatCast(precise_delta_time));

                // test camera
                if (instance.window.getKey(.d) == .press) {
                    cameraYaw(1.0 * delta_time);
                }
                if (instance.window.getKey(.a) == .press) {
                    cameraYaw(-1.0 * delta_time);
                }
                if (instance.window.getKey(.j) == .press) {
                    cameraPitch(1.0 * delta_time);
                }
                if (instance.window.getKey(.k) == .press) {
                    cameraPitch(-1.0 * delta_time);
                }

                var velocity: zm.Vec = zm.splat(zm.Vec, 0.0);

                if (instance.window.getKey(.s) == .press) {
                    const forward = utils.getForwardVec(camera_view);
                    velocity += forward;
                }
                if (instance.window.getKey(.w) == .press) {
                    const backward = utils.getBackwardVec(camera_view);
                    velocity += backward;
                }
                if (instance.window.getKey(.h) == .press) {
                    const left = utils.getLeftVec(camera_view);
                    velocity += left;
                }
                if (instance.window.getKey(.l) == .press) {
                    const right = utils.getRightVec(camera_view);
                    velocity += right;
                }

                if (!zm.all(zm.isNearEqual(velocity, zm.splat(zm.Vec, 0.0), zm.splat(zm.Vec, 0.0001)), 3)) {
                    velocity = zm.normalize3(velocity);

                    const move_speed = zm.splat(zm.Vec, 5.0 * delta_time);
                    camera_position += velocity * move_speed;
                    camera_view_dirty = true;
                }

                recomputeCameraView();
                instance.renderer.view = camera_view;

                try instance.renderer.drawFrame();

                // const frame_end_time = glfw.getTime();
                // const frame_elapsed_time = frame_end_time - frame_start_time;
                // var frame_stall_time = target_frame_seconds - frame_elapsed_time;

                // if (frame_stall_time > 0) {
                //     std.time.sleep(@as(u64, @intFromFloat(frame_stall_time)) * std.time.ns_per_s);
                // }

                instance.last_time = frame_start_time;
            }
            glfw.pollEvents();
        }

        try instance.renderer.waitIdle();
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
