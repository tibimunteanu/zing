const std = @import("std");
const builtin = @import("builtin");
const math = @import("zmath");
const glfw = @import("glfw");

const utils = @import("utils.zig");
const Renderer = @import("renderer/renderer.zig");
const Texture = @import("renderer/texture.zig");
const Material = @import("renderer/material.zig");
const Geometry = @import("renderer/geometry.zig");
const Shader = @import("renderer/shader.zig");
const ShaderResource = @import("resources/shader_resource.zig");

const RenderPacket = Renderer.RenderPacket;
const GeometryRenderData = Renderer.GeometryRenderData;
const Vertex3D = Renderer.Vertex3D;
const Vertex2D = Renderer.Vertex2D;

const Allocator = std.mem.Allocator;

const Engine = @This();

// TODO: temporary
var choice: usize = 2;
const names = [_][]const u8{
    "cobblestone",
    "paving",
    "paving2",
};
var test_geometry = Geometry.Handle.nil;
var test_ui_geometry = Geometry.Handle.nil;
// TODO: end temporary

var window: glfw.Window = undefined;
var last_time: f64 = 0;

var camera_view: math.Mat = undefined;
var camera_view_dirty: bool = true;
var camera_position: math.Vec = math.Vec{ 0.0, 0.0, -30.0, 0.0 };
var camera_euler: math.Vec = math.splat(math.Vec, 0.0); // pitch, yaw, roll

var prevPressN: glfw.Action = .release;

pub fn init(allocator: Allocator) !void {
    glfw.setErrorCallback(errorCallback);

    if (!glfw.init(.{})) {
        std.log.err("Failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        return error.GLFWInitFailed;
    }
    errdefer glfw.terminate();

    window = glfw.Window.create(960, 540, "Zing", null, null, .{
        .client_api = .no_api,
    }) orelse return blk: {
        std.log.err("Failed to create window: {?s}", .{glfw.getErrorString()});
        break :blk error.CreateWindowFailed;
    };
    errdefer window.destroy();

    try Renderer.init(allocator, window);
    errdefer Renderer.deinit();

    try Texture.initSystem(allocator);
    errdefer Texture.deinitSystem();

    try Material.initSystem(allocator);
    errdefer Material.deinitSystem();

    try Geometry.initSystem(allocator);
    errdefer Geometry.deinitSystem();

    // TODO: temporary
    // instance.test_geometry = .getDefaultGeometry();
    var test_plane_config = try Geometry.Config(Vertex3D, u32).initPlane(.{
        .name = "plane",
        .material_name = "diffuse",
        .width = 20,
        .height = 20,
        .segment_count_x = 4,
        .segment_count_y = 4,
        .tile_x = 2,
        .tile_y = 2,
    });
    defer test_plane_config.deinit();

    test_geometry = try Geometry.acquireByConfig(
        test_plane_config,
        .{ .auto_release = true },
    );

    var test_ui_plane_config = try Geometry.Config(Vertex2D, u32).initPlane(.{
        .name = "ui_plane",
        .material_name = "ui",
        .width = 512,
        .height = 512,
        .segment_count_x = 1,
        .segment_count_y = 1,
        .tile_x = 1,
        .tile_y = 1,
    });
    defer test_ui_plane_config.deinit();

    test_ui_geometry = try Geometry.acquireByConfig(
        test_ui_plane_config,
        .{ .auto_release = true },
    );
    // TODO: end temporary
}

pub fn deinit() void {
    Geometry.deinitSystem();
    Material.deinitSystem();
    Texture.deinitSystem();
    Renderer.deinit();

    window.destroy();

    glfw.terminate();
}

pub fn run() !void {
    last_time = glfw.getTime();

    while (!window.shouldClose()) {
        if (window.getAttrib(.iconified) == 0) {
            const frame_start_time = glfw.getTime();
            const precise_delta_time = frame_start_time - last_time;
            const delta_time = @as(f32, @floatCast(precise_delta_time));

            try updateCamera(delta_time);

            const packet = RenderPacket{
                .delta_time = delta_time,
                .geometries = &[_]GeometryRenderData{
                    GeometryRenderData{
                        .model = math.mul(math.translation(-5.0, 0.0, 0.0), math.rotationY(0.0)),
                        .geometry = test_geometry,
                    },
                },
                .ui_geometries = &[_]GeometryRenderData{
                    GeometryRenderData{
                        .model = math.translation(256.0, 256.0, 0.0),
                        .geometry = test_ui_geometry,
                    },
                },
            };

            try Renderer.drawFrame(packet);

            // const frame_end_time = glfw.getTime();
            // const frame_elapsed_time = frame_end_time - frame_start_time;
            // const fps = 1.0 / frame_elapsed_time;
            // std.log.info("{d:.0}", .{fps});

            last_time = frame_start_time;
        }
        glfw.pollEvents();
    }

    try Renderer.waitIdle();
}

// utils
fn updateCamera(delta_time: f32) !void {
    if (window.getKey(.d) == .press) {
        cameraYaw(1.0 * delta_time);
    }
    if (window.getKey(.a) == .press) {
        cameraYaw(-1.0 * delta_time);
    }
    if (window.getKey(.j) == .press) {
        cameraPitch(1.0 * delta_time);
    }
    if (window.getKey(.k) == .press) {
        cameraPitch(-1.0 * delta_time);
    }

    var velocity: math.Vec = math.splat(math.Vec, 0.0);

    if (window.getKey(.s) == .press) {
        const forward = utils.getForwardVec(camera_view);
        velocity += forward;
    }
    if (window.getKey(.w) == .press) {
        const backward = utils.getBackwardVec(camera_view);
        velocity += backward;
    }
    if (window.getKey(.h) == .press) {
        const left = utils.getLeftVec(camera_view);
        velocity += left;
    }
    if (window.getKey(.l) == .press) {
        const right = utils.getRightVec(camera_view);
        velocity += right;
    }

    if (!math.all(math.isNearEqual(velocity, math.splat(math.Vec, 0.0), math.splat(math.Vec, 0.0001)), 3)) {
        velocity = math.normalize3(velocity);

        const move_speed = math.splat(math.Vec, 5.0 * delta_time);
        camera_position += velocity * move_speed;
        camera_view_dirty = true;
    }

    recomputeCameraView();
    Renderer.view = camera_view;

    const pressN = window.getKey(.n);
    if (pressN == .press and prevPressN == .release) {
        choice += 1;
        choice %= names.len;

        if (test_geometry.getIfExists()) |geometry| {
            const material = try geometry.material.get();

            const prev_texture = material.diffuse_map.texture;
            material.diffuse_map.texture = try Texture.acquire(names[choice], .{ .auto_release = true });
            prev_texture.release();
        }
    }
    prevPressN = pressN;
}

fn recomputeCameraView() void {
    if (camera_view_dirty) {
        const rotation = math.matFromRollPitchYawV(camera_euler);
        const translation = math.translationV(camera_position);

        camera_view = math.inverse(math.mul(rotation, translation));
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

fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}\n", .{ error_code, description });
}
