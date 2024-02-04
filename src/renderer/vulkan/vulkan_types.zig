const std = @import("std");
const Image = @import("image.zig").Image;
const ID = @import("../../utils.zig").ID;
const vk = @import("vk.zig");

pub const max_object_count = 1024;
pub const object_shader_descriptor_count = 1;

pub const TextureData = struct {
    image: Image,
    sampler: vk.Sampler,
};

pub const DescriptorState = struct {
    generations: [3]ID,
};

pub const ObjectShaderObjectState = struct {
    descriptor_sets: [3]vk.DescriptorSet,
    descriptor_states: [object_shader_descriptor_count]DescriptorState,
};
