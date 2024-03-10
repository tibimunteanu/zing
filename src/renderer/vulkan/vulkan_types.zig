const std = @import("std");
const vk = @import("vk.zig");
const math = @import("zmath");

const Image = @import("image.zig");
const TextureHandle = @import("../../systems/texture_system.zig").TextureHandle;

pub const material_shader_instance_max_count: u32 = 1024;
pub const material_shader_descriptor_count: u32 = 2;
pub const material_shader_sampler_count: u32 = 1;

pub const ui_shader_instance_max_count: u32 = 1024;
pub const ui_shader_descriptor_count: u32 = 2;
pub const ui_shader_sampler_count: u32 = 1;

pub const geometry_max_count: u32 = 4096;

pub const WorldGlobalUniformData = struct {
    projection: math.Mat,
    view: math.Mat,
    _reserved_1: math.Mat = undefined,
    _reserved_2: math.Mat = undefined,
};

pub const WorldInstanceUniformData = struct {
    diffuse_color: math.Vec,
    _reserved_0: math.Vec = undefined,
    _reserved_1: math.Vec = undefined,
    _reserved_2: math.Vec = undefined,
};

pub const UIGlobalUniformData = struct {
    projection: math.Mat,
    view: math.Mat,
    _reserved_1: math.Mat = undefined,
    _reserved_2: math.Mat = undefined,
};

pub const UIInstanceUniformData = struct {
    diffuse_color: math.Vec,
    _reserved_0: math.Vec = undefined,
    _reserved_1: math.Vec = undefined,
    _reserved_2: math.Vec = undefined,
};

pub const TextureData = struct {
    image: Image,
    sampler: vk.Sampler,
};

pub const DescriptorState = struct {
    generations: [3]?u32,
    handles: [3]TextureHandle,
};

pub const MaterialShaderInstanceState = struct {
    descriptor_sets: [3]vk.DescriptorSet,
    descriptor_states: [material_shader_descriptor_count]DescriptorState,
};

pub const UIShaderInstanceState = struct {
    descriptor_sets: [3]vk.DescriptorSet,
    descriptor_states: [ui_shader_descriptor_count]DescriptorState,
};

pub const GeometryData = struct {
    id: ?u32,
    generation: ?u32,
    vertex_count: u32,
    vertex_size: u32,
    vertex_buffer_offset: u32,
    index_count: u32,
    index_size: u32,
    index_buffer_offset: u32,
};
