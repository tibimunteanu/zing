const std = @import("std");
const Context = @import("vulkan/context.zig").Context;
const glfw = @import("mach-glfw");
const zm = @import("zmath");
const Allocator = std.mem.Allocator;
const BeginFrameResult = @import("types.zig").BeginFrameResult;
const GeometryRenderData = @import("types.zig").GeometryRenderData;
const Engine = @import("../engine.zig").Engine;
const Texture = @import("../resources/texture.zig").Texture;
const zstbi = @import("zstbi");
const deg2rad = std.math.degreesToRadians;

fn framebufferSizeCallback(_: glfw.Window, width: u32, height: u32) void {
    Engine.instance.renderer.onResized(glfw.Window.Size{ .width = width, .height = height });
}

pub const Renderer = struct {
    allocator: Allocator,
    context: *Context,

    projection: zm.Mat,
    view: zm.Mat,
    fov: f32,
    near_clip: f32,
    far_clip: f32,

    default_texture: Texture,

    // TODO: temporary
    test_diffuse: Texture,

    pub fn init(self: *Renderer, allocator: Allocator, window: glfw.Window) !void {
        self.allocator = allocator;

        self.context = try allocator.create(Context);
        errdefer allocator.destroy(self.context);

        // this is used in init
        self.context.default_diffuse = &self.default_texture;

        try self.context.init(allocator, "Zing app", window);
        errdefer self.context.deinit();

        std.log.info("Graphics device: {?s}", .{self.context.physical_device.properties.device_name});
        std.log.info("GQ: {}, PQ: {}, CQ: {}, TQ: {}", .{
            self.context.graphics_queue.family_index,
            self.context.present_queue.family_index,
            self.context.compute_queue.family_index,
            self.context.transfer_queue.family_index,
        });

        window.setFramebufferSizeCallback(framebufferSizeCallback);

        self.fov = deg2rad(f32, 45.0);
        self.near_clip = 0.1;
        self.far_clip = 1000.0;

        const fb_size = window.getFramebufferSize();

        self.projection = zm.perspectiveFovLh(
            self.fov,
            @as(f32, @floatFromInt(fb_size.width)) / @as(f32, @floatFromInt(fb_size.height)),
            self.near_clip,
            self.far_clip,
        );

        self.view = zm.inverse(zm.translation(0.0, 0.0, -30.0));

        const tex_dimension: u32 = 64;
        const channels: u32 = 4;
        const pixel_count = tex_dimension * tex_dimension;

        var pixels: [pixel_count * channels]u8 = undefined;
        @memset(&pixels, 255);

        for (0..tex_dimension) |row| {
            for (0..tex_dimension) |col| {
                const index = (row * tex_dimension) + col;
                const index_channel = index * channels;

                if (row % 2 == col % 2) {
                    pixels[index_channel + 0] = 0;
                    pixels[index_channel + 1] = 0;
                }
            }
        }

        self.default_texture = try self.createTexture(
            allocator,
            "default",
            tex_dimension,
            tex_dimension,
            4,
            false,
            false,
            &pixels,
        );
        errdefer self.destroyTexture(&self.default_texture);

        self.default_texture.generation = .null_handle;

        resetTexture(&self.test_diffuse);
    }

    pub fn deinit(self: *Renderer) void {
        self.destroyTexture(&self.test_diffuse);
        self.destroyTexture(&self.default_texture);

        self.context.deinit();
        self.allocator.destroy(self.context);
    }

    pub fn beginFrame(self: *Renderer, delta_time: f32) !BeginFrameResult {
        return try self.context.beginFrame(delta_time);
    }

    pub fn endFrame(self: *Renderer) !void {
        try self.context.endFrame();
    }

    pub fn drawFrame(self: *Renderer, delta_time: f32) !void {
        switch (try self.beginFrame(delta_time)) {
            .resize => {
                // NOTE: Skip rendering this frame.
            },
            .render => {
                try self.context.updateGlobalState(self.projection, self.view);

                var data: GeometryRenderData = undefined;
                data.object_id = @enumFromInt(0);
                data.model = zm.mul(zm.translation(-5, 0.0, 0.0), zm.rotationY(-0.0));
                data.textures = [_]?*Texture{null} ** 16;
                data.textures[0] = &self.test_diffuse;

                try self.context.updateObjectState(data);

                self.context.drawFrame();

                try self.endFrame();
            },
        }
    }

    pub fn onResized(self: *Renderer, new_desired_extent: glfw.Window.Size) void {
        self.projection = zm.perspectiveFovLh(
            self.fov,
            @as(f32, @floatFromInt(new_desired_extent.width)) / @as(f32, @floatFromInt(new_desired_extent.height)),
            self.near_clip,
            self.far_clip,
        );
        self.context.onResized(new_desired_extent);
    }

    pub fn waitIdle(self: Renderer) !void {
        try self.context.swapchain.waitForAllFences();
    }

    pub fn createTexture(
        self: *Renderer,
        allocator: Allocator,
        name: []const u8,
        width: u32,
        height: u32,
        channel_count: u8,
        has_transparency: bool,
        auto_release: bool,
        pixels: []const u8,
    ) !Texture {
        return try self.context.createTexture(
            allocator,
            name,
            width,
            height,
            channel_count,
            has_transparency,
            auto_release,
            pixels,
        );
    }

    pub fn destroyTexture(self: *Renderer, texture: *Texture) void {
        self.context.destroyTexture(texture);
    }

    // utils
    fn resetTexture(texture: *Texture) void {
        texture.id = 0;
        texture.width = 0;
        texture.height = 0;
        texture.channel_count = 0;
        texture.has_transparency = false;
        texture.generation = .null_handle;
        texture.internal_data = null;
    }

    fn loadTexture(self: *Renderer, allocator: Allocator, name: []const u8, texture: *Texture) !void {
        zstbi.init(allocator);
        defer zstbi.deinit();

        const path_format = "assets/textures/{s}.{s}";

        const texture_path = try std.fmt.allocPrintZ(allocator, path_format, .{ name, "png" });
        defer allocator.free(texture_path);

        zstbi.setFlipVerticallyOnLoad(true);

        var image = try zstbi.Image.loadFromFile(texture_path, 4);
        defer image.deinit();

        var has_transparency = false;
        var i: u32 = 0;
        const total_size: usize = image.width * image.height * image.num_components;
        while (i < total_size) : (i += image.num_components) {
            const a: u8 = image.data[i + 3];
            if (a < 255) {
                has_transparency = true;
                break;
            }
        }

        var temp_texture = try self.createTexture(
            allocator,
            name,
            image.width,
            image.height,
            @truncate(image.num_components),
            has_transparency,
            true,
            image.data,
        );

        temp_texture.generation = texture.generation;
        temp_texture.generation.increment();

        self.destroyTexture(texture);
        texture.* = temp_texture;
    }

    // TODO: temporary
    pub var choice: usize = 2;
    pub fn changeTexture(self: *Renderer) !void {
        const names = [_][]const u8{
            "cobblestone",
            "paving",
            "paving2",
        };

        choice += 1;
        choice %= names.len;

        try self.loadTexture(self.allocator, names[choice], &self.test_diffuse);
    }
};
