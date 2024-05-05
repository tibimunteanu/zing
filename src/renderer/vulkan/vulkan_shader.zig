const std = @import("std");
const config = @import("../../config.zig");
const vk = @import("vk.zig");
const Engine = @import("../../engine.zig");
const Shader = @import("../shader.zig");

const VulkanShader = @This();

pub fn init(
    shader: *Shader,
    shader_config: Shader.Config,
) !VulkanShader {
    _ = shader; // autofix
    _ = shader_config; // autofix
    const self: VulkanShader = undefined;

    return self;
}

pub fn deinit(self: *VulkanShader, shader: *Shader) void {
    _ = shader; // autofix
    self.* = undefined;
}
