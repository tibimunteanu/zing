const std = @import("std");
const config = @import("../config.zig");

// TODO: make this an union(enum) and dispatch based on a global variable rather than a compile time constant
const ShaderBackend = switch (config.renderer_backend_type) {
    .vulkan => @import("vulkan/vulkan_shader.zig"),
};

const Allocator = std.mem.Allocator;
pub const InstanceHandle = ShaderBackend.InstanceHandle;

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

pub fn initInstance(self: *Shader) !InstanceHandle {
    return try self.backend.initInstance();
}

pub fn deinitInstance(self: *Shader, handle: InstanceHandle) void {
    self.backend.deinitInstance(handle);
}

pub fn bind(self: *const Shader) void {
    self.backend.bind();
}

pub fn bindGlobal(self: *Shader) void {
    self.backend.bindGlobal();
}

pub fn bindInstance(self: *Shader, handle: InstanceHandle) !void {
    try self.backend.bindInstance(handle);
}

pub fn setUniform(self: *Shader, uniform: *Uniform, value: anytype) !void {
    try self.backend.setUniform(uniform, value);
}

pub const Scope = enum(u8) {
    global = 0,
    instance = 1,
    local = 2,
};

pub const UniformDataType = enum(u8) {
    float32,
    float32_2,
    float32_3,
    float32_4,
    int8,
    uint8,
    int16,
    uint16,
    int32,
    uint32,
    mat_4,
    sampler,
};

pub const Uniform = struct {
    scope: Scope,
    data_type: UniformDataType,
    size: u32,
    offset: u32,
    location: u16,
    texture_index: u16,
};

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
