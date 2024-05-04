const std = @import("std");
const config = @import("../config.zig");
const TextureSystem = @import("../systems/texture_system.zig");

const ShaderBackend = switch (config.renderer_backend_type) {
    .vulkan => @import("vulkan/vulkan_shader.zig"),
};

const TextureHandle = TextureSystem.TextureHandle;
const Allocator = std.mem.Allocator;

const Shader = @This();

id: u32,
name: []const u8,
use_instances: bool,
use_locals: bool,
required_ubo_alignment: u64,
global_ubo_size: u64,
global_ubo_stride: u64,
global_ubo_offset: u64,
ubo_size: u64,
ubo_stride: u64,
push_constant_size: u64,
push_constant_stride: u64,
global_textures: []TextureHandle,
instance_texture_count: u8,
bound_scope: Scope,
bound_instance_id: u32,
bound_ubo_offset: u32,
// uniform_lookup: Lookup,
uniforms: []Uniform,
attributes: []Attribute,
state: State,
push_constant_range_count: u8,
// push_constant_ranges: [32]Range,
attribute_stride: u16,

backend: ShaderBackend,

pub fn init(renderpass_id: u8, stage_count: u8, stage_filenames: []const []const u8, stages: []const Shader.Stage) !Shader {
    var self: Shader = undefined;
    self.backend = try ShaderBackend.init(&self, renderpass_id, stage_count, stage_filenames, stages);
    return self;
}

pub fn deinit(self: *Shader) void {
    self.backend.deinit(self);
    self.* = undefined;
}

pub fn setup(self: *Shader) !void {
    try self.backend.setup(self);
}

pub fn use(self: *Shader) void {
    self.backend.use(self);
}

pub fn bindGlobals(self: *Shader) void {
    self.backend.bindGlobals(self);
}

pub fn bindInstance(self: *Shader, instance_id: u32) void {
    self.backend.bindInstance(self, instance_id);
}

pub fn applyGlobals(self: *Shader) void {
    self.backend.applyGlobals(self);
}

pub fn applyInstance(self: *Shader) void {
    self.backend.applyInstance(self);
}

pub fn acquireInstanceResources(self: *Shader) u32 {
    return self.backend.acquireInstanceResources(self);
}

pub fn releaseInstanceResources(self: *Shader, instance_id: u32) void {
    self.backend.releaseInstanceResources(self, instance_id);
}

pub fn setUniform(self: *Shader, uniform: *Uniform, value: []const u8) void {
    self.backend.setUniform(self, uniform, value);
}

pub const State = enum(u8) {
    not_created,
    uninitialized,
    initialized,
};

pub const Scope = enum(u8) {
    global = 0,
    instance = 1,
    local = 2,
};

pub const Stage = enum(u32) {
    vertex = 1 << 0,
    geometry = 1 << 1,
    fragment = 1 << 2,
    compute = 1 << 3,
};

pub const AttributeType = enum(u8) {
    float32 = 0,
    float32_2 = 1,
    float32_3 = 2,
    float32_4 = 3,
    matrix_4 = 4,
    int8 = 5,
    uint8 = 6,
    int16 = 7,
    uint16 = 8,
    int32 = 9,
    uint32 = 10,
};

pub const UniformType = enum(u8) {
    float32 = 0,
    float32_2 = 1,
    float32_3 = 2,
    float32_4 = 3,
    int8 = 4,
    uint8 = 5,
    int16 = 6,
    uint16 = 7,
    int32 = 8,
    uint32 = 9,
    matrix_4 = 10,
    sampler = 11,
    custom = 255,
};

pub const Attribute = struct {
    name: []const u8,
    attribute_type: AttributeType,
    size: u32,
};

pub const Uniform = struct {
    offset: u64,
    location: u16,
    index: u16,
    size: u16,
    set_index: u8, // The index of the descriptor set the uniform belongs to (0=global, 1=instance, INVALID_ID=local).
    scope: Scope,
    uniform_type: UniformType,
};
