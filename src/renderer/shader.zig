const std = @import("std");
const config = @import("../config.zig");

// TODO: make this an union(enum) and dispatch based on a global variable rather than a compile time constant
const ShaderBackend = switch (config.renderer_backend_type) {
    .vulkan => @import("vulkan/vulkan_shader.zig"),
};

const Allocator = std.mem.Allocator;

const Shader = @This();

allocator: Allocator,
name: std.BoundedArray(u8, 256),

backend: ShaderBackend,

pub fn init(allocator: Allocator, shader_config: Config) !Shader {
    var self: Shader = undefined;
    self.allocator = allocator;

    self.name = try std.BoundedArray(u8, 256).fromSlice(shader_config.name);

    self.backend = try ShaderBackend.init(allocator, &self, shader_config);

    return self;
}

pub fn deinit(self: *Shader) void {
    self.backend.deinit();

    self.* = undefined;
}

// config
pub const Config = struct {
    name: []const u8 = "new_shader",
    render_pass_name: []const u8 = "world",
    stages: []const StageConfig,
    attributes: []const AttributeConfig,
    global_uniforms: []const UniformConfig,
    instance_uniforms: []const UniformConfig,
    local_uniforms: []const UniformConfig,
};

pub const StageConfig = struct {
    stage_type: []const u8,
    path: []const u8,
};

pub const AttributeConfig = struct {
    name: []const u8,
    data_type: []const u8,
};

pub const UniformConfig = struct {
    name: []const u8,
    data_type: []const u8,
};
