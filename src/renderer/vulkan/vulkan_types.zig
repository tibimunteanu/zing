const std = @import("std");
const vk = @import("vk.zig");

const Image = @import("image.zig").Image;
const TextureHandle = @import("../../systems/texture_system.zig").TextureHandle;

pub const material_shader_instance_max_count = 1024;
pub const material_shader_descriptor_count = 2;
pub const material_shader_sampler_count = 1;

pub const geometry_max_count = 4096;

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
