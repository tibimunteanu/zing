const std = @import("std");
const builtin = @import("builtin");
const math = @import("zmath");
const glfw = @import("glfw");

const cnt = @import("cnt.zig");
const utils = @import("utils.zig");
const Renderer = @import("renderer/renderer.zig");
const TextureSystem = @import("systems/texture_system.zig");
const MaterialSystem = @import("systems/material_system.zig");
const GeometrySystem = @import("systems/geometry_system.zig");

const GeometryHandle = GeometrySystem.GeometryHandle;
const RenderPacket = Renderer.RenderPacket;
const GeometryRenderData = Renderer.GeometryRenderData;
const Vertex3D = Renderer.Vertex3D;
const Vertex2D = Renderer.Vertex2D;

const Allocator = std.mem.Allocator;

const Engine = @This();

pub var instance: Engine = undefined;

// TODO: temporary
var choice: usize = 2;
const names = [_][]const u8{
    "cobblestone",
    "paving",
    "paving2",
};
test_geometry: GeometryHandle,
test_ui_geometry: GeometryHandle,
// TODO: end temporary

allocator: Allocator,
window: glfw.Window,
renderer: *Renderer,
texture_system: *TextureSystem,
material_system: *MaterialSystem,
geometry_system: *GeometrySystem,
last_time: f64,

var camera_view: math.Mat = undefined;
var camera_view_dirty: bool = true;
var camera_position: math.Vec = math.Vec{ 0.0, 0.0, -30.0, 0.0 };
var camera_euler: math.Vec = math.splat(math.Vec, 0.0); // pitch, yaw, roll

var prevPressN: glfw.Action = .release;

pub fn init(allocator: Allocator) !void {
    instance.allocator = allocator;

    glfw.setErrorCallback(errorCallback);

    if (!glfw.init(.{})) {
        std.log.err("Failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        return error.GLFWInitFailed;
    }
    errdefer glfw.terminate();

    instance.window = glfw.Window.create(960, 540, "Zing", null, null, .{
        .client_api = .no_api,
    }) orelse return blk: {
        std.log.err("Failed to create window: {?s}", .{glfw.getErrorString()});
        break :blk error.CreateWindowFailed;
    };
    errdefer instance.window.destroy();

    instance.renderer = try allocator.create(Renderer);
    errdefer allocator.destroy(instance.renderer);

    try instance.renderer.init(allocator, instance.window);
    errdefer instance.renderer.deinit();

    instance.texture_system = try allocator.create(TextureSystem);
    errdefer allocator.destroy(instance.texture_system);

    try instance.texture_system.init(allocator);
    errdefer instance.texture_system.deinit();

    instance.material_system = try allocator.create(MaterialSystem);
    errdefer allocator.destroy(instance.material_system);

    try instance.material_system.init(allocator);
    errdefer instance.material_system.deinit();

    instance.geometry_system = try allocator.create(GeometrySystem);
    errdefer allocator.destroy(instance.geometry_system);

    try instance.geometry_system.init(allocator);
    errdefer instance.geometry_system.deinit();

    // TODO: temporary
    // instance.test_geometry = instance.geometry_system.getDefaultGeometry();
    var test_plane_config = try GeometrySystem.GeometryConfig(Vertex3D, u32).initPlane(
        allocator,
        .{
            .name = "plane",
            .material_name = "diffuse",
            .width = 20,
            .height = 20,
            .segment_count_x = 4,
            .segment_count_y = 4,
            .tile_x = 2,
            .tile_y = 2,
        },
    );
    defer test_plane_config.deinit();

    instance.test_geometry = try instance.geometry_system.acquireGeometryByConfig(
        test_plane_config,
        .{ .auto_release = true },
    );

    var test_ui_plane_config = try GeometrySystem.GeometryConfig(Vertex2D, u32).initPlane(
        allocator,
        .{
            .name = "ui_plane",
            .material_name = "ui",
            .width = 512,
            .height = 512,
            .segment_count_x = 1,
            .segment_count_y = 1,
            .tile_x = 1,
            .tile_y = 1,
        },
    );
    defer test_ui_plane_config.deinit();

    instance.test_ui_geometry = try instance.geometry_system.acquireGeometryByConfig(
        test_ui_plane_config,
        .{ .auto_release = true },
    );
    // TODO: end temporary
}

pub fn deinit() void {
    instance.geometry_system.deinit();
    instance.allocator.destroy(instance.geometry_system);

    instance.material_system.deinit();
    instance.allocator.destroy(instance.material_system);

    instance.texture_system.deinit();
    instance.allocator.destroy(instance.texture_system);

    instance.renderer.deinit();
    instance.allocator.destroy(instance.renderer);

    instance.window.destroy();

    glfw.terminate();
}

pub fn run() !void {
    instance.last_time = glfw.getTime();

    while (!instance.window.shouldClose()) {
        if (instance.window.getAttrib(.iconified) == 0) {
            const frame_start_time = glfw.getTime();
            const precise_delta_time = frame_start_time - instance.last_time;
            const delta_time = @as(f32, @floatCast(precise_delta_time));

            try instance.updateCamera(delta_time);

            const packet = RenderPacket{
                .delta_time = delta_time,
                .geometries = &[_]GeometryRenderData{
                    GeometryRenderData{
                        .model = math.mul(math.translation(-5.0, 0.0, 0.0), math.rotationY(0.0)),
                        .geometry = instance.test_geometry,
                    },
                },
                .ui_geometries = &[_]GeometryRenderData{
                    GeometryRenderData{
                        .model = math.translation(256.0, 256.0, 0.0),
                        .geometry = instance.test_ui_geometry,
                    },
                },
            };

            try instance.renderer.drawFrame(packet);

            // const frame_end_time = glfw.getTime();
            // const frame_elapsed_time = frame_end_time - frame_start_time;
            // const fps = 1.0 / frame_elapsed_time;
            // std.log.info("{d:.0}", .{fps});

            instance.last_time = frame_start_time;
        }
        glfw.pollEvents();
    }

    try instance.renderer.waitIdle();
}

// utils
fn updateCamera(self: *const Engine, delta_time: f32) !void {
    if (self.window.getKey(.d) == .press) {
        cameraYaw(1.0 * delta_time);
    }
    if (self.window.getKey(.a) == .press) {
        cameraYaw(-1.0 * delta_time);
    }
    if (self.window.getKey(.j) == .press) {
        cameraPitch(1.0 * delta_time);
    }
    if (self.window.getKey(.k) == .press) {
        cameraPitch(-1.0 * delta_time);
    }

    var velocity: math.Vec = math.splat(math.Vec, 0.0);

    if (self.window.getKey(.s) == .press) {
        const forward = utils.getForwardVec(camera_view);
        velocity += forward;
    }
    if (self.window.getKey(.w) == .press) {
        const backward = utils.getBackwardVec(camera_view);
        velocity += backward;
    }
    if (self.window.getKey(.h) == .press) {
        const left = utils.getLeftVec(camera_view);
        velocity += left;
    }
    if (self.window.getKey(.l) == .press) {
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
    self.renderer.view = camera_view;

    const pressN = self.window.getKey(.n);
    if (pressN == .press and prevPressN == .release) {
        choice += 1;
        choice %= names.len;

        if (self.geometry_system.geometries.getColumnPtrIfLive(self.test_geometry, .geometry)) |geometry| {
            const material = self.material_system.materials.getColumnPtrAssumeLive(geometry.material, .material);

            const prev_texture = material.diffuse_map.texture;
            material.diffuse_map.texture = try self.texture_system.acquireTextureByName(
                names[choice],
                .{ .auto_release = true },
            );
            self.texture_system.releaseTextureByHandle(prev_texture);
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
