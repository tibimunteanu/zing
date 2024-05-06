const std = @import("std");
const config = @import("../../config.zig");
const vk = @import("vk.zig");
const Engine = @import("../../engine.zig");
const Shader = @import("../shader.zig");
const BinaryResource = @import("../../resources/binary_resource.zig");

const Allocator = std.mem.Allocator;

const VulkanShader = @This();

allocator: Allocator,

shader_modules: std.BoundedArray(vk.ShaderModule, config.shader_max_stages),
descriptor_set_layouts: std.BoundedArray(vk.DescriptorSetLayout, 2),
descriptor_pool: vk.DescriptorPool,
pipeline_layout: vk.PipelineLayout,
pipeline: vk.Pipeline,

pub fn init(
    allocator: Allocator,
    shader: *Shader,
    shader_config: Shader.Config,
) !VulkanShader {
    var context = Engine.instance.renderer.context;

    var self: VulkanShader = undefined;
    self.allocator = allocator;

    self.shader_modules.len = 0;
    self.descriptor_set_layouts.len = 0;
    self.descriptor_pool = .null_handle;
    self.pipeline_layout = .null_handle;
    self.pipeline = .null_handle;

    errdefer self.deinit();

    // shader stages
    var shader_stages = try std.BoundedArray(vk.PipelineShaderStageCreateInfo, config.shader_max_stages).init(0);

    for (shader_config.stages) |stage| {
        const module = try createShaderModule(allocator, stage.path);
        try self.shader_modules.append(module);

        try shader_stages.append(vk.PipelineShaderStageCreateInfo{
            .flags = .{},
            .stage = try getVkShaderStageFlags(stage.stage_type),
            .module = module,
            .p_name = "main",
            .p_specialization_info = null,
        });
    }

    // vertex input
    var attribute_description = try std.ArrayList(vk.VertexInputAttributeDescription).initCapacity(allocator, 8);
    defer attribute_description.deinit();

    var offset: u32 = 0;
    for (shader_config.attributes, 0..) |attribute, location| {
        const format = try getVkFormat(attribute.data_type);
        const size = try getFormatSize(attribute.data_type);

        try attribute_description.append(vk.VertexInputAttributeDescription{
            .binding = 0,
            .location = @as(u32, @intCast(location)),
            .format = format,
            .offset = offset,
        });

        offset += size;
    }

    const vertex_input_state = vk.PipelineVertexInputStateCreateInfo{
        .flags = .{},
        .vertex_binding_description_count = 1,
        .p_vertex_binding_descriptions = @ptrCast(&vk.VertexInputBindingDescription{
            .binding = 0,
            .stride = offset,
            .input_rate = .vertex,
        }),
        .vertex_attribute_description_count = @truncate(attribute_description.items.len),
        .p_vertex_attribute_descriptions = attribute_description.items.ptr,
    };

    // descriptor pool
    const descriptor_pool_sizes = [_]vk.DescriptorPoolSize{
        vk.DescriptorPoolSize{ .type = .uniform_buffer, .descriptor_count = 1024 },
        vk.DescriptorPoolSize{ .type = .combined_image_sampler, .descriptor_count = 4096 },
    };

    self.descriptor_pool = try context.device_api.createDescriptorPool(
        context.device,
        &vk.DescriptorPoolCreateInfo{
            .flags = .{ .free_descriptor_set_bit = true },
            .pool_size_count = descriptor_pool_sizes.len,
            .p_pool_sizes = &descriptor_pool_sizes,
            .max_sets = config.shader_descriptor_allocate_max_sets,
        },
        null,
    );

    // global descriptors
    var global_ubo_layout_bindings = try std.BoundedArray(vk.DescriptorSetLayoutBinding, 2).init(0);

    try global_ubo_layout_bindings.append(
        vk.DescriptorSetLayoutBinding{
            .binding = 0,
            .descriptor_count = 1,
            .descriptor_type = .uniform_buffer,
            .p_immutable_samplers = null,
            .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
        },
    );

    for (shader_config.global_uniforms) |global_uniform| {
        if (isSampler(global_uniform.data_type)) {
            if (global_ubo_layout_bindings.len < 2) {
                try global_ubo_layout_bindings.append(
                    vk.DescriptorSetLayoutBinding{
                        .binding = 1,
                        .descriptor_count = 1,
                        .descriptor_type = .combined_image_sampler,
                        .p_immutable_samplers = null,
                        .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
                    },
                );
            } else {
                global_ubo_layout_bindings.slice()[1].descriptor_count += 1;
            }
        }
    }

    try self.descriptor_set_layouts.append(try context.device_api.createDescriptorSetLayout(
        context.device,
        &vk.DescriptorSetLayoutCreateInfo{
            .binding_count = global_ubo_layout_bindings.len,
            .p_bindings = global_ubo_layout_bindings.slice().ptr,
        },
        null,
    ));

    // instance descriptors
    if (shader_config.instance_uniforms.len > 0) {
        var instance_ubo_layout_bindings = try std.BoundedArray(vk.DescriptorSetLayoutBinding, 2).init(0);

        try instance_ubo_layout_bindings.append(
            vk.DescriptorSetLayoutBinding{
                .binding = 0,
                .descriptor_count = 1,
                .descriptor_type = .uniform_buffer,
                .p_immutable_samplers = null,
                .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
            },
        );

        for (shader_config.instance_uniforms) |instance_uniform| {
            if (isSampler(instance_uniform.data_type)) {
                if (instance_ubo_layout_bindings.len < 2) {
                    try instance_ubo_layout_bindings.append(
                        vk.DescriptorSetLayoutBinding{
                            .binding = 1,
                            .descriptor_count = 1,
                            .descriptor_type = .combined_image_sampler,
                            .p_immutable_samplers = null,
                            .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
                        },
                    );
                } else {
                    instance_ubo_layout_bindings.slice()[1].descriptor_count += 1;
                }
            }
        }

        try self.descriptor_set_layouts.append(try context.device_api.createDescriptorSetLayout(
            context.device,
            &vk.DescriptorSetLayoutCreateInfo{
                .binding_count = instance_ubo_layout_bindings.len,
                .p_bindings = instance_ubo_layout_bindings.slice().ptr,
            },
            null,
        ));
    }

    // local push constants
    var push_constant_offset: u32 = 0;
    var push_constant_ranges = try std.BoundedArray(vk.PushConstantRange, 32).init(0);

    for (shader_config.local_uniforms) |local_uniform| {
        push_constant_offset = std.mem.alignForward(u32, push_constant_offset, 4);

        const size = try getFormatSize(local_uniform.data_type);
        const aligned_size = std.mem.alignForward(u32, size, 4);

        try push_constant_ranges.append(vk.PushConstantRange{
            .stage_flags = .{ .vertex_bit = true },
            .offset = push_constant_offset,
            .size = aligned_size,
        });

        push_constant_offset += aligned_size;
    }

    self.pipeline_layout = try context.device_api.createPipelineLayout(context.device, &.{
        .flags = .{},
        .set_layout_count = self.descriptor_set_layouts.len,
        .p_set_layouts = self.descriptor_set_layouts.slice().ptr,
        .push_constant_range_count = push_constant_ranges.len,
        .p_push_constant_ranges = push_constant_ranges.slice().ptr,
    }, null);

    const input_assembly_state = vk.PipelineInputAssemblyStateCreateInfo{
        .flags = .{},
        .topology = .triangle_list,
        .primitive_restart_enable = vk.FALSE,
    };

    const rasterization_state = vk.PipelineRasterizationStateCreateInfo{
        .flags = .{},
        .depth_clamp_enable = vk.FALSE,
        .rasterizer_discard_enable = vk.FALSE,
        .polygon_mode = .fill,
        .cull_mode = .{ .back_bit = true },
        .front_face = .counter_clockwise,
        .depth_bias_enable = vk.FALSE,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
        .line_width = 1,
    };

    const multisample_state = vk.PipelineMultisampleStateCreateInfo{
        .flags = .{},
        .rasterization_samples = .{ .@"1_bit" = true },
        .sample_shading_enable = vk.FALSE,
        .min_sample_shading = 1,
        .p_sample_mask = null,
        .alpha_to_coverage_enable = vk.FALSE,
        .alpha_to_one_enable = vk.FALSE,
    };

    const depth_stencil_state = vk.PipelineDepthStencilStateCreateInfo{
        .flags = .{},
        .depth_test_enable = vk.TRUE,
        .depth_write_enable = vk.TRUE,
        .depth_compare_op = .less,
        .depth_bounds_test_enable = vk.FALSE,
        .stencil_test_enable = vk.FALSE,
        .front = undefined,
        .back = undefined,
        .min_depth_bounds = 0,
        .max_depth_bounds = 0,
    };

    const color_blend_attachment_state = vk.PipelineColorBlendAttachmentState{
        .blend_enable = vk.TRUE,
        .src_color_blend_factor = .src_alpha,
        .dst_color_blend_factor = .one_minus_src_alpha,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .src_alpha,
        .dst_alpha_blend_factor = .one_minus_src_alpha,
        .alpha_blend_op = .add,
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
    };

    const color_blend_state = vk.PipelineColorBlendStateCreateInfo{
        .flags = .{},
        .logic_op_enable = vk.FALSE,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = @ptrCast(&color_blend_attachment_state),
        .blend_constants = [_]f32{ 0, 0, 0, 0 },
    };

    const viewport_state = vk.PipelineViewportStateCreateInfo{
        .flags = .{},
        .viewport_count = 1,
        .p_viewports = undefined,
        .scissor_count = 1,
        .p_scissors = undefined,
    };

    const dynamic_state_props = [_]vk.DynamicState{ .viewport, .scissor, .line_width };
    const dynamic_state = vk.PipelineDynamicStateCreateInfo{
        .flags = .{},
        .dynamic_state_count = dynamic_state_props.len,
        .p_dynamic_states = &dynamic_state_props,
    };

    const pipeline_create_info = vk.GraphicsPipelineCreateInfo{
        .flags = .{},
        .stage_count = shader_stages.len,
        .p_stages = shader_stages.slice().ptr,
        .p_viewport_state = &viewport_state,
        .p_vertex_input_state = &vertex_input_state,
        .p_input_assembly_state = &input_assembly_state,
        .p_tessellation_state = null,
        .p_rasterization_state = &rasterization_state,
        .p_multisample_state = &multisample_state,
        .p_depth_stencil_state = &depth_stencil_state,
        .p_color_blend_state = &color_blend_state,
        .p_dynamic_state = &dynamic_state,
        .layout = self.pipeline_layout,
        .render_pass = try getVkRenderPass(shader_config.render_pass_name),
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    _ = try context.device_api.createGraphicsPipelines(
        context.device,
        .null_handle,
        1,
        @ptrCast(&pipeline_create_info),
        null,
        @ptrCast(&self.pipeline),
    );

    _ = shader; // autofix

    return self;
}

pub fn deinit(self: *VulkanShader) void {
    var context = Engine.instance.renderer.context;

    if (self.pipeline != .null_handle) {
        context.device_api.destroyPipeline(context.device, self.pipeline, null);
    }

    if (self.pipeline_layout != .null_handle) {
        context.device_api.destroyPipelineLayout(context.device, self.pipeline_layout, null);
    }

    for (self.descriptor_set_layouts.slice()) |descriptor_set_layout| {
        if (descriptor_set_layout != .null_handle) {
            context.device_api.destroyDescriptorSetLayout(context.device, descriptor_set_layout, null);
        }
    }
    self.descriptor_set_layouts.len = 0;

    if (self.descriptor_pool != .null_handle) {
        context.device_api.destroyDescriptorPool(context.device, self.descriptor_pool, null);
    }

    for (self.shader_modules.slice()) |module| {
        if (module != .null_handle) {
            context.device_api.destroyShaderModule(context.device, module, null);
        }
    }
    self.shader_modules.len = 0;

    self.* = undefined;
}

// utils
fn createShaderModule(allocator: Allocator, path: []const u8) !vk.ShaderModule {
    var context = Engine.instance.renderer.context;

    var binary_resource = try BinaryResource.init(allocator, path);
    defer binary_resource.deinit();

    return try context.device_api.createShaderModule(
        context.device,
        &vk.ShaderModuleCreateInfo{
            .flags = .{},
            .code_size = binary_resource.bytes.len,
            .p_code = @ptrCast(@alignCast(binary_resource.bytes.ptr)),
        },
        null,
    );
}

fn getVkShaderStageFlags(stage_type: []const u8) !vk.ShaderStageFlags {
    if (std.mem.eql(u8, stage_type, "vertex")) return .{ .vertex_bit = true };
    if (std.mem.eql(u8, stage_type, "fragment")) return .{ .fragment_bit = true };

    return error.UnknownShaderStage;
}

fn isSampler(data_type: []const u8) bool {
    return std.mem.eql(u8, data_type, "sampler");
}

fn getVkFormat(data_type: []const u8) !vk.Format {
    if (std.mem.eql(u8, data_type, "float32")) return .r32_sfloat;
    if (std.mem.eql(u8, data_type, "float32_2")) return .r32g32_sfloat;
    if (std.mem.eql(u8, data_type, "float32_3")) return .r32g32b32_sfloat;
    if (std.mem.eql(u8, data_type, "float32_4")) return .r32g32b32a32_sfloat;

    if (std.mem.eql(u8, data_type, "sampler")) return error.FoundSampler;

    return error.UnknownDataType;
}

fn getFormatSize(data_type: []const u8) !u32 {
    if (std.mem.eql(u8, data_type, "float32")) return @as(u32, @intCast(4));
    if (std.mem.eql(u8, data_type, "float32_2")) return @as(u32, @intCast(8));
    if (std.mem.eql(u8, data_type, "float32_3")) return @as(u32, @intCast(12));
    if (std.mem.eql(u8, data_type, "float32_4")) return @as(u32, @intCast(16));
    if (std.mem.eql(u8, data_type, "mat_4")) return @as(u32, @intCast(64));
    if (std.mem.eql(u8, data_type, "sampler")) return @as(u32, @intCast(0));

    return error.UnknownDataType;
}

fn getVkRenderPass(render_pass_name: []const u8) !vk.RenderPass {
    const context = Engine.instance.renderer.context;

    if (std.mem.eql(u8, render_pass_name, "world")) return context.world_render_pass.handle;
    if (std.mem.eql(u8, render_pass_name, "ui")) return context.ui_render_pass.handle;

    return error.UnknownRenderPass;
}
