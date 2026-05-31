const std = @import("std");
const builtin = @import("builtin");
const math = @import("math.zig");
const utils = @import("utils.zig");
const Errors = @import("platform/errors.zig");
const Events = @import("platform/events.zig");
const Input = @import("platform/input.zig");
const Time = @import("platform/time.zig");
const VulkanWSI = @import("platform/vulkan_wsi.zig");
const Window = @import("platform/window.zig");

const Renderer = @import("renderer/renderer.zig");
const Image = @import("renderer/image.zig");
const Texture = @import("renderer/texture.zig");
const Material = @import("renderer/material.zig");
const Geometry = @import("renderer/geometry.zig");
const Shader = @import("renderer/shader.zig");

const RenderPacket = Renderer.RenderPacket;
const GeometryRenderData = Renderer.GeometryRenderData;
const Vertex3D = Renderer.Vertex3D;
const Vertex2D = Renderer.Vertex2D;

const Allocator = std.mem.Allocator;

const Engine = @This();

var window: Window = undefined;
var last_time: f64 = 0;

var camera_view: math.Mat = undefined;
var camera_view_dirty: bool = true;
var camera_position: math.Vec = math.Vec{ 0.0, 0.0, -30.0, 0.0 };
var camera_euler: math.Vec = math.splat(math.Vec, 0.0); // pitch, yaw, roll

var prevPressN: Input.Action = .release;

pub fn init(allocator: Allocator) !void {
    _ = Errors.setCallback(errorCallback);

    try Time.initSystem();
    errdefer Time.deinitSystem();

    try VulkanWSI.initSystem(null);
    errdefer VulkanWSI.deinitSystem();

    try Window.initSystem();
    errdefer Window.deinitSystem();

    window = Window.create(960, 540, "Zing", null, null, .{
        .client_api = .no_api,
    }) catch |err| {
        std.log.err("Failed to create window: {?s}", .{Errors.getString()});
        return err;
    };
    errdefer window.destroy() catch {};

    try Renderer.init(allocator, window);
    errdefer Renderer.deinit();

    try Image.initSystem(allocator);
    errdefer Image.deinitSystem();

    try Texture.initSystem(allocator);
    errdefer Texture.deinitSystem();

    try Shader.initSystem(allocator);
    errdefer Shader.deinitSystem();

    try Material.initSystem(allocator);
    errdefer Material.deinitSystem();

    try Geometry.initSystem(allocator);
    errdefer Geometry.deinitSystem();

    try tempTest();
}

pub fn deinit() void {
    Geometry.deinitSystem();
    Material.deinitSystem();
    Shader.deinitSystem();
    Texture.deinitSystem();
    Image.deinitSystem();
    Renderer.deinit();

    window.destroy() catch {};

    Window.deinitSystem();
    VulkanWSI.deinitSystem();
    Time.deinitSystem();
}

pub fn run() !void {
    last_time = try Time.get();

    while (!try window.shouldClose()) {
        if (!try window.getAttrib(.iconified)) {
            const frame_start_time = try Time.get();
            const precise_delta_time = frame_start_time - last_time;
            const delta_time: f32 = @floatCast(precise_delta_time);

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

            // const frame_end_time = try Time.get();
            // const frame_elapsed_time = frame_end_time - frame_start_time;
            // const fps = 1.0 / frame_elapsed_time;
            // std.log.info("{d:.0}", .{fps});

            last_time = frame_start_time;
        }
        try Events.poll();
    }

    Renderer.waitIdle();
}

// utils
fn updateCamera(delta_time: f32) !void {
    if (try window.getKey(.d) == .press) {
        cameraYaw(1.0 * delta_time);
    }
    if (try window.getKey(.a) == .press) {
        cameraYaw(-1.0 * delta_time);
    }
    if (try window.getKey(.j) == .press) {
        cameraPitch(1.0 * delta_time);
    }
    if (try window.getKey(.k) == .press) {
        cameraPitch(-1.0 * delta_time);
    }

    var velocity: math.Vec = math.splat(math.Vec, 0.0);

    if (try window.getKey(.s) == .press) {
        const forward = utils.getForwardVec(camera_view);
        velocity += forward;
    }
    if (try window.getKey(.w) == .press) {
        const backward = utils.getBackwardVec(camera_view);
        velocity += backward;
    }
    if (try window.getKey(.h) == .press) {
        const left = utils.getLeftVec(camera_view);
        velocity += left;
    }
    if (try window.getKey(.l) == .press) {
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
    Renderer.world_view = camera_view;

    const pressN = try window.getKey(.n);
    if (pressN == .press and prevPressN == .release) {
        choice += 1;
        choice %= names.len;

        if (Geometry.getIfExists(test_geometry)) |geometry| {
            const material = try Material.get(geometry.material);

            const prev_texture = material.properties.items[1].value.sampler;
            material.properties.items[1].value.sampler = try Texture.acquire(names[choice]);
            Texture.release(prev_texture);
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

fn errorCallback(error_code: Errors.Code, description: [:0]const u8) void {
    std.log.err("zing: {}: {s}", .{ error_code, description });
}

// TODO: temporary
var choice: usize = 2;
const names = [_][]const u8{
    "cobblestone",
    "paving2",
    "paving",
};
var test_geometry = Geometry.Handle.nil;
var test_ui_geometry = Geometry.Handle.nil;

fn tempTest() !void {
    var test_plane_config = try Geometry.Config(Vertex3D, u32).initPlane(.{
        .name = "plane",
        .material_name = "diffuse",
        .width = 20,
        .height = 20,
        .segment_count_x = 4,
        .segment_count_y = 4,
        .tile_x = 2,
        .tile_y = 2,
        .auto_release = true,
    });
    defer test_plane_config.deinit();

    test_geometry = try Geometry.acquire(test_plane_config);

    var test_ui_plane_config = try Geometry.Config(Vertex2D, u32).initPlane(.{
        .name = "ui_plane",
        .material_name = "ui",
        .width = 512,
        .height = 512,
        .segment_count_x = 1,
        .segment_count_y = 1,
        .tile_x = 1,
        .tile_y = 1,
        .auto_release = true,
    });
    defer test_ui_plane_config.deinit();

    test_ui_geometry = try Geometry.acquire(test_ui_plane_config);
}
// TODO: end temporary
