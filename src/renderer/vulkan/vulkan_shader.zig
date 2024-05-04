const std = @import("std");
const config = @import("../../config.zig");
const vk = @import("vk.zig");
const Engine = @import("../../engine.zig");
const RenderPass = @import("renderpass.zig");
const Buffer = @import("buffer.zig");
const Shader = @import("../shader.zig");

const VulkanShader = @This();

// The index of the global descriptor set.
const desc_set_index_global: u32 = 0;

// The index of the instance descriptor set.
const desc_set_index_instance: u32 = 1;

// The index of the UBO binding.
const binding_index_ubo: u32 = 0;

// The index of the image sampler binding.
const binding_index_sampler: u32 = 1;

id: u32,
mapped_uniform_buffer_block: *anyopaque,
// config: VulkanShaderConfig,
renderpass: *RenderPass,
stages: [config.shader_max_stages]Shader.Stage,
descriptor_pool: vk.DescriptorPool,
descriptor_set_layouts: [2]vk.DescriptorSetLayout, // 0=global, 1=instance
global_descriptor_sets: [config.max_swapchain_image_count]vk.DescriptorSet,
uniform_buffer: Buffer,
pipeline: vk.Pipeline,

pub fn init(shader: *Shader, renderpass_id: u8, stage_count: u8, stage_filenames: []const []const u8, stages: []const Shader.Stage) !VulkanShader {
    _ = shader; // autofix
    _ = stage_filenames; // autofix
    var self: VulkanShader = undefined;

    const context = Engine.instance.renderer.context;

    // TODO: dynamic renderpasses
    self.renderpass = if (renderpass_id == 1) &context.world_render_pass else &context.ui_render_pass;

    // Translate stages
    var vk_stages: [config.shader_max_stages]vk.ShaderStageFlags = undefined;

    // TODO: replace param with a bit mask similar to vk.ShaderStageFlags
    for (0..stage_count) |i| {
        switch (stages[i]) {
            .fragment => vk_stages[i] = .{ .fragment_bit = true },
            .vertex => vk_stages[i] = .{ .vertex_bit = true },
            .geometry => vk_stages[i] = .{ .geometry_bit = true },
            .compute => vk_stages[i] = .{ .compute_bit = true },
        }
    }

    // TODO: configurable max descriptor allocate count.
    // const max_descriptor_allocate_count: u32 = 1024;

    // Build out the configuration.
    // self.config.max_descriptor_set_count = max_descriptor_allocate_count;

    return self;
}

pub fn deinit(self: *VulkanShader, shader: *Shader) void {
    _ = shader; // autofix
    self.* = undefined;
}

pub fn setup(self: *VulkanShader, shader: *Shader) !void {
    _ = shader; // autofix
    _ = self; // autofix
}

pub fn use(self: *VulkanShader, shader: *Shader) void {
    _ = shader; // autofix
    _ = self; // autofix
}

pub fn bindGlobals(self: *VulkanShader, shader: *Shader) void {
    _ = shader; // autofix
    _ = self; // autofix
}

pub fn bindInstance(self: *VulkanShader, shader: *Shader, instance_id: u32) void {
    _ = shader; // autofix
    _ = self; // autofix
    _ = instance_id; // autofix
}

pub fn applyGlobals(self: *VulkanShader, shader: *Shader) void {
    _ = shader; // autofix
    _ = self; // autofix
}

pub fn applyInstance(self: *VulkanShader, shader: *Shader) void {
    _ = shader; // autofix
    _ = self; // autofix
}

pub fn acquireInstanceResources(self: *VulkanShader, shader: *Shader) u32 {
    _ = shader; // autofix
    _ = self; // autofix
}

pub fn releaseInstanceResources(self: *VulkanShader, shader: *Shader, instance_id: u32) void {
    _ = shader; // autofix
    _ = self; // autofix
    _ = instance_id; // autofix
}

pub fn setUniform(self: *VulkanShader, shader: *Shader, uniform: *Shader.Uniform, value: []const u8) void {
    _ = shader; // autofix
    _ = self; // autofix
    _ = uniform; // autofix
    _ = value; // autofix
}
