const std = @import("std");
const config = @import("../config.zig");

// TODO: make this an union(enum) and dispatch based on a global variable rather than a compile time constant
const ShaderBackend = switch (config.renderer_backend_type) {
    .vulkan => @import("vulkan/vulkan_shader.zig"),
};

const Allocator = std.mem.Allocator;

const Shader = @This();

name: std.BoundedArray(u8, 256),

backend: ShaderBackend,

pub fn init(shader_config: Config) !Shader {
    var self: Shader = undefined;
    self.backend = try ShaderBackend.init(&self, shader_config);
    return self;
}

pub fn deinit(self: *Shader) void {
    self.backend.deinit(self);
    self.* = undefined;
}

// config
pub const Config = struct {
    name: []const u8 = "new_shader",
    render_pass_name: []const u8 = "world",
    use_instance: bool = false,
    use_local: bool = false,
    stages: []const StageConfig,
    attributes: []const AttributeConfig,
    uniforms: []const UniformConfig,
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
    scope: []const u8,
    name: []const u8,
    data_type: []const u8,
};
