const std = @import("std");
const pool = @import("zpool");
const vk = @import("vk.zig");
const config = @import("../../config.zig");
const Engine = @import("../../engine.zig");
const Context = @import("context.zig");
const Shader = @import("../shader.zig");
const Buffer = @import("buffer.zig");
const BinaryResource = @import("../../resources/binary_resource.zig");
const TextureSystem = @import("../../systems/texture_system.zig");
const TextureHandle = TextureSystem.TextureHandle;
const TextureData = Context.TextureData;

const ctx = @import("context.zig").ctx;

const Allocator = std.mem.Allocator;
const Array = std.BoundedArray;

const VulkanShader = @This();

pub const DescriptorState = struct {
    generations: Array(?u32, config.swapchain_max_images),
    handles: Array(TextureHandle, config.swapchain_max_images),
};

pub const InstanceState = struct {
    ubo_offset: u64,
    descriptor_sets: Array(vk.DescriptorSet, config.swapchain_max_images),
    descriptor_states: Array(DescriptorState, config.shader_max_bindings),
    textures: Array(TextureHandle, config.shader_max_instance_textures),
};

// NOTE: index_bits = 10 results in a maximum of 1024 instances
pub const InstancePool = pool.Pool(10, 22, InstanceState, struct {
    instance_state: InstanceState,
});
pub const InstanceHandle = InstancePool.Handle;

allocator: Allocator,

shader_modules: Array(vk.ShaderModule, config.shader_max_stages),
descriptor_set_layouts: Array(vk.DescriptorSetLayout, 2),
descriptor_pool: vk.DescriptorPool,
pipeline_layout: vk.PipelineLayout,
pipeline: vk.Pipeline,

instance_pool: InstancePool,

global_descriptor_sets: Array(vk.DescriptorSet, config.swapchain_max_images),
global_ubo_size: u64,
global_ubo_stride: u64,
global_ubo_offset: u64,
global_binding_count: u32,
global_sampler_count: u32,

instance_ubo_size: u64,
instance_ubo_stride: u64,
instance_binding_count: u32,
instance_sampler_count: u32,

ubo: Buffer,
ubo_ptr: [*]u8,

bound_instance_handle: InstanceHandle,
bound_ubo_offset: u64,

pub fn init(allocator: Allocator, shader: *Shader, shader_config: Shader.Config) !VulkanShader {
    var self: VulkanShader = undefined;
    self.allocator = allocator;

    self.shader_modules.len = 0;
    self.descriptor_set_layouts.len = 0;
    self.descriptor_pool = .null_handle;
    self.pipeline_layout = .null_handle;
    self.pipeline = .null_handle;
    self.global_descriptor_sets.len = 0;

    errdefer self.deinit();

    // shader stages
    var shader_stages = try Array(vk.PipelineShaderStageCreateInfo, config.shader_max_stages).init(0);

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
    var attribute_descriptions = try Array(vk.VertexInputAttributeDescription, config.shader_max_attributes).init(0);

    var offset: u32 = 0;
    for (shader_config.attributes, 0..) |attribute, location| {
        const format = try getVkFormat(attribute.data_type);
        const size = try getFormatSize(attribute.data_type);

        try attribute_descriptions.append(vk.VertexInputAttributeDescription{
            .binding = 0,
            .location = @intCast(location),
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
        .vertex_attribute_description_count = attribute_descriptions.len,
        .p_vertex_attribute_descriptions = attribute_descriptions.slice().ptr,
    };

    // global descriptors
    self.global_ubo_size = 0;
    self.global_sampler_count = 0;

    for (shader.uniforms.items) |uniform| {
        if (uniform.scope == .global) {
            if (uniform.data_type == .sampler) {
                self.global_sampler_count += 1;
            } else {
                self.global_ubo_size += uniform.size;
            }
        }
    }

    var global_ubo_layout_bindings = try Array(vk.DescriptorSetLayoutBinding, 2).init(0);

    try global_ubo_layout_bindings.append(
        vk.DescriptorSetLayoutBinding{
            .binding = 0,
            .descriptor_count = 1,
            .descriptor_type = .uniform_buffer,
            .p_immutable_samplers = null,
            .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
        },
    );

    if (self.global_sampler_count > 0) {
        try global_ubo_layout_bindings.append(
            vk.DescriptorSetLayoutBinding{
                .binding = 1,
                .descriptor_count = self.global_sampler_count,
                .descriptor_type = .combined_image_sampler,
                .p_immutable_samplers = null,
                .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
            },
        );
    }

    self.global_binding_count = global_ubo_layout_bindings.len;

    try self.descriptor_set_layouts.append(try ctx().device_api.createDescriptorSetLayout(
        ctx().device,
        &vk.DescriptorSetLayoutCreateInfo{
            .binding_count = global_ubo_layout_bindings.len,
            .p_bindings = global_ubo_layout_bindings.slice().ptr,
        },
        null,
    ));

    // instance descriptors
    self.instance_ubo_size = 0;
    self.instance_sampler_count = 0;
    self.instance_binding_count = 0;

    if (shader_config.instance_uniforms.len > 0) {
        for (shader.uniforms.items) |uniform| {
            if (uniform.scope == .instance) {
                if (uniform.data_type == .sampler) {
                    self.instance_sampler_count += 1;
                } else {
                    self.instance_ubo_size += uniform.size;
                }
            }
        }

        var instance_ubo_layout_bindings = try Array(vk.DescriptorSetLayoutBinding, 2).init(0);

        try instance_ubo_layout_bindings.append(
            vk.DescriptorSetLayoutBinding{
                .binding = 0,
                .descriptor_count = 1,
                .descriptor_type = .uniform_buffer,
                .p_immutable_samplers = null,
                .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
            },
        );

        if (self.instance_sampler_count > 0) {
            try instance_ubo_layout_bindings.append(
                vk.DescriptorSetLayoutBinding{
                    .binding = 1,
                    .descriptor_count = self.instance_sampler_count,
                    .descriptor_type = .combined_image_sampler,
                    .p_immutable_samplers = null,
                    .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
                },
            );
        }

        self.instance_binding_count = instance_ubo_layout_bindings.len;

        try self.descriptor_set_layouts.append(try ctx().device_api.createDescriptorSetLayout(
            ctx().device,
            &vk.DescriptorSetLayoutCreateInfo{
                .binding_count = instance_ubo_layout_bindings.len,
                .p_bindings = instance_ubo_layout_bindings.slice().ptr,
            },
            null,
        ));
    }

    // local push constants
    var push_constant_offset: u32 = 0;
    var push_constant_ranges = try Array(vk.PushConstantRange, 32).init(0);

    for (shader.uniforms.items) |uniform| {
        if (uniform.scope == .local) {
            const uniform_aligned_size = std.mem.alignForward(u32, uniform.size, 4);

            try push_constant_ranges.append(vk.PushConstantRange{
                .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
                .offset = push_constant_offset,
                .size = uniform_aligned_size,
            });

            push_constant_offset += uniform_aligned_size;
        }
    }

    self.pipeline_layout = try ctx().device_api.createPipelineLayout(ctx().device, &.{
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

    _ = try ctx().device_api.createGraphicsPipelines(
        ctx().device,
        .null_handle,
        1,
        @ptrCast(&pipeline_create_info),
        null,
        @ptrCast(&self.pipeline),
    );

    const ubo_alignment = ctx().physical_device.properties.limits.min_uniform_buffer_offset_alignment;

    self.global_ubo_stride = std.mem.alignForward(u64, self.global_ubo_size, ubo_alignment);
    self.instance_ubo_stride = std.mem.alignForward(u64, self.instance_ubo_size, ubo_alignment);

    // TODO: should we allocate separate ranges per swapchain image?
    const ubo_size = self.global_ubo_stride + (self.instance_ubo_stride * config.shader_max_instances);

    self.ubo = try Buffer.init(
        ctx(),
        ubo_size,
        .{ .transfer_dst_bit = true, .uniform_buffer_bit = true },
        .{
            .device_local_bit = ctx().physical_device.supports_local_host_visible,
            .host_visible_bit = true,
            .host_coherent_bit = true,
        },
        .{ .managed = true, .bind_on_create = true },
    );

    self.ubo_ptr = try self.ubo.lock(0, vk.WHOLE_SIZE, .{});

    self.global_ubo_offset = try self.ubo.alloc(self.global_ubo_stride);

    // descriptor pool
    const descriptor_pool_sizes = [_]vk.DescriptorPoolSize{
        vk.DescriptorPoolSize{ .type = .uniform_buffer, .descriptor_count = 1024 },
        vk.DescriptorPoolSize{ .type = .combined_image_sampler, .descriptor_count = 4096 },
    };

    self.descriptor_pool = try ctx().device_api.createDescriptorPool(
        ctx().device,
        &vk.DescriptorPoolCreateInfo{
            .flags = .{ .free_descriptor_set_bit = true },
            .pool_size_count = descriptor_pool_sizes.len,
            .p_pool_sizes = &descriptor_pool_sizes,
            .max_sets = config.shader_max_descriptor_sets_allocate,
        },
        null,
    );

    // allocate global descriptor sets
    const global_ubo_layout = self.descriptor_set_layouts.get(@intFromEnum(Shader.Scope.global));
    var global_ubo_layouts = try Array(vk.DescriptorSetLayout, config.swapchain_max_images).init(0);
    try global_ubo_layouts.appendNTimes(global_ubo_layout, ctx().swapchain.images.len);

    const global_ubo_descriptor_set_alloc_info = vk.DescriptorSetAllocateInfo{
        .descriptor_pool = self.descriptor_pool,
        .descriptor_set_count = global_ubo_layouts.len,
        .p_set_layouts = global_ubo_layouts.slice().ptr,
    };

    try self.global_descriptor_sets.resize(global_ubo_layouts.len);

    try ctx().device_api.allocateDescriptorSets(
        ctx().device,
        &global_ubo_descriptor_set_alloc_info,
        self.global_descriptor_sets.slice().ptr,
    );

    self.instance_pool = try InstancePool.initMaxCapacity(allocator);

    return self;
}

pub fn deinit(self: *VulkanShader) void {
    self.instance_pool.deinit();

    ctx().device_api.freeDescriptorSets(
        ctx().device,
        self.descriptor_pool,
        self.global_descriptor_sets.len,
        self.global_descriptor_sets.slice().ptr,
    ) catch {};
    self.global_descriptor_sets.len = 0;

    self.ubo.deinit();

    if (self.descriptor_pool != .null_handle) {
        ctx().device_api.destroyDescriptorPool(ctx().device, self.descriptor_pool, null);
    }

    if (self.pipeline != .null_handle) {
        ctx().device_api.destroyPipeline(ctx().device, self.pipeline, null);
    }

    if (self.pipeline_layout != .null_handle) {
        ctx().device_api.destroyPipelineLayout(ctx().device, self.pipeline_layout, null);
    }

    for (self.descriptor_set_layouts.slice()) |descriptor_set_layout| {
        if (descriptor_set_layout != .null_handle) {
            ctx().device_api.destroyDescriptorSetLayout(ctx().device, descriptor_set_layout, null);
        }
    }
    self.descriptor_set_layouts.len = 0;

    for (self.shader_modules.slice()) |module| {
        if (module != .null_handle) {
            ctx().device_api.destroyShaderModule(ctx().device, module, null);
        }
    }
    self.shader_modules.len = 0;

    self.* = undefined;
}

pub fn initInstance(self: *VulkanShader) !InstanceHandle {
    var instance_state: InstanceState = undefined;

    instance_state.ubo_offset = try self.ubo.alloc(self.instance_ubo_stride);

    // clear descriptor states
    instance_state.descriptor_states = try Array(DescriptorState, config.shader_max_bindings).init(
        self.instance_binding_count,
    );
    for (instance_state.descriptor_states.slice()) |*descriptor_state| {
        try descriptor_state.generations.resize(0);
        try descriptor_state.generations.appendNTimes(null, ctx().swapchain.images.len);

        try descriptor_state.handles.resize(0);
        try descriptor_state.handles.appendNTimes(TextureHandle.nil, ctx().swapchain.images.len);
    }

    // clear textures to default texture handle
    const default_texture_handle = Engine.instance.texture_system.getDefaultTexture();
    try instance_state.textures.resize(0);
    try instance_state.textures.appendNTimes(default_texture_handle, self.instance_sampler_count);

    // allocate instance descriptor sets
    const instance_ubo_layout = self.descriptor_set_layouts.get(@intFromEnum(Shader.Scope.instance));
    var instance_ubo_layouts = try Array(vk.DescriptorSetLayout, config.swapchain_max_images).init(0);
    try instance_ubo_layouts.appendNTimes(instance_ubo_layout, ctx().swapchain.images.len);

    const instance_ubo_descriptor_set_alloc_info = vk.DescriptorSetAllocateInfo{
        .descriptor_pool = self.descriptor_pool,
        .descriptor_set_count = instance_ubo_layouts.len,
        .p_set_layouts = instance_ubo_layouts.slice().ptr,
    };

    try instance_state.descriptor_sets.resize(instance_ubo_layouts.len);

    try ctx().device_api.allocateDescriptorSets(
        ctx().device,
        &instance_ubo_descriptor_set_alloc_info,
        instance_state.descriptor_sets.slice().ptr,
    );

    // add instance to pool
    const handle = try self.instance_pool.add(.{
        .instance_state = instance_state,
    });

    return handle;
}

pub fn deinitInstance(self: *VulkanShader, handle: InstanceHandle) void {
    if (self.instance_pool.getColumnPtrIfLive(handle, .instance_state)) |instance_state| {
        ctx().device_api.freeDescriptorSets(
            ctx().device,
            self.descriptor_pool,
            instance_state.descriptor_sets.len,
            instance_state.descriptor_sets.slice().ptr,
        ) catch {};
        instance_state.descriptor_sets.len = 0;

        self.ubo.free(instance_state.ubo_offset, self.instance_ubo_stride) catch {};

        instance_state.* = undefined;

        self.instance_pool.removeAssumeLive(handle);
    }
}

pub fn bind(self: *const VulkanShader) void {
    ctx().device_api.cmdBindPipeline(ctx().getCurrentCommandBuffer().handle, .graphics, self.pipeline);
}

pub fn bindGlobal(self: *VulkanShader) void {
    self.bound_ubo_offset = self.global_ubo_offset;
}

pub fn bindInstance(self: *VulkanShader, handle: InstanceHandle) !void {
    if (self.instance_pool.getColumnPtrIfLive(handle, .instance_state)) |instance_state| {
        self.bound_instance_handle = handle;
        self.bound_ubo_offset = instance_state.ubo_offset;
    } else return error.InvalidShaderInstanceHandle;
}

pub fn setUniform(self: *VulkanShader, uniform: *const Shader.Uniform, value: anytype) !void {
    if (uniform.data_type == .sampler) {
        if (@TypeOf(value) != TextureHandle) {
            return error.InvalidSamplerValue;
        }

        switch (uniform.scope) {
            .global => return error.GlobalTexturesNotYetSupported,
            .instance => {
                if (self.instance_pool.getColumnPtrIfLive(self.bound_instance_handle, .instance_state)) |instance_state| {
                    instance_state.textures.slice()[uniform.texture_index] = value;
                } else return error.InvalidShaderInstanceHandle;
            },
            .local => return error.CannotSetLocalSamplers,
        }
    } else {
        switch (uniform.scope) {
            .local => {
                ctx().device_api.cmdPushConstants(
                    ctx().getCurrentCommandBuffer().handle,
                    self.pipeline_layout,
                    .{ .vertex_bit = true, .fragment_bit = true },
                    uniform.offset,
                    uniform.size,
                    &value,
                );
            },
            .global, .instance => {
                const uniform_ptr = @as([*]u8, @ptrFromInt(
                    @intFromPtr(self.ubo_ptr) + self.bound_ubo_offset + uniform.offset,
                ));

                @memcpy(uniform_ptr, &std.mem.toBytes(value));
            },
        }
    }
}

pub fn applyGlobal(self: *VulkanShader) !void {
    const image_index = ctx().swapchain.image_index;
    const command_buffer = ctx().getCurrentCommandBuffer();
    const descriptor_set = self.global_descriptor_sets.get(image_index);

    const buffer_info = vk.DescriptorBufferInfo{
        .buffer = self.ubo.handle,
        .offset = self.global_ubo_offset,
        .range = self.global_ubo_stride,
    };

    var descriptor_writes = try Array(vk.WriteDescriptorSet, 2).init(0);

    try descriptor_writes.append(vk.WriteDescriptorSet{
        .dst_set = descriptor_set,
        .dst_binding = 0,
        .dst_array_element = 0,
        .descriptor_type = .uniform_buffer,
        .descriptor_count = 1,
        .p_buffer_info = @ptrCast(&buffer_info),
        .p_image_info = undefined,
        .p_texel_buffer_view = undefined,
    });

    if (self.global_sampler_count > 0) {
        return error.GlobalTexturesNotYetSupported;
    }

    if (descriptor_writes.len > 0) {
        ctx().device_api.updateDescriptorSets(
            ctx().device,
            descriptor_writes.len,
            @ptrCast(descriptor_writes.slice().ptr),
            0,
            null,
        );
    }

    ctx().device_api.cmdBindDescriptorSets(
        command_buffer.handle,
        .graphics,
        self.pipeline_layout,
        0,
        1,
        @ptrCast(&descriptor_set),
        0,
        null,
    );
}

pub fn applyInstance(self: *VulkanShader) !void {
    const image_index = ctx().swapchain.image_index;
    const command_buffer = ctx().getCurrentCommandBuffer();

    if (self.instance_pool.getColumnPtrIfLive(self.bound_instance_handle, .instance_state)) |instance_state| {
        const descriptor_set = instance_state.descriptor_sets.get(image_index);

        var descriptor_writes = try Array(vk.WriteDescriptorSet, 2).init(0);

        var dst_binding: u32 = 0;

        // descriptor 0 - uniform buffer
        const buffer_info = vk.DescriptorBufferInfo{
            .buffer = self.ubo.handle,
            .offset = instance_state.ubo_offset,
            .range = self.instance_ubo_stride,
        };

        try descriptor_writes.append(vk.WriteDescriptorSet{
            .dst_set = descriptor_set,
            .dst_binding = dst_binding,
            .dst_array_element = 0,
            .descriptor_type = .uniform_buffer,
            .descriptor_count = 1,
            .p_buffer_info = @ptrCast(&buffer_info),
            .p_image_info = undefined,
            .p_texel_buffer_view = undefined,
        });

        dst_binding += 1;

        // descriptor 1 - samplers
        var image_infos = try Array(vk.DescriptorImageInfo, config.shader_max_instance_textures).init(0);

        for (0..self.instance_sampler_count) |sampler_index| {
            const texture_handle = instance_state.textures.slice()[sampler_index];
            const texture = Engine.instance.texture_system.textures.getColumnPtrAssumeLive(texture_handle, .texture);
            const texture_backend: *TextureData = @ptrCast(@alignCast(texture.internal_data));

            try image_infos.append(vk.DescriptorImageInfo{
                .image_layout = .shader_read_only_optimal,
                .image_view = texture_backend.image.view,
                .sampler = texture_backend.sampler,
            });
        }

        try descriptor_writes.append(vk.WriteDescriptorSet{
            .dst_set = descriptor_set,
            .dst_binding = dst_binding,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = self.instance_sampler_count,
            .dst_array_element = 0,
            .p_buffer_info = undefined,
            .p_image_info = @ptrCast(image_infos.slice().ptr),
            .p_texel_buffer_view = undefined,
        });

        if (descriptor_writes.len > 0) {
            ctx().device_api.updateDescriptorSets(
                ctx().device,
                descriptor_writes.len,
                @ptrCast(descriptor_writes.slice().ptr),
                0,
                null,
            );
        }

        ctx().device_api.cmdBindDescriptorSets(
            command_buffer.handle,
            .graphics,
            self.pipeline_layout,
            1,
            1,
            @ptrCast(&descriptor_set),
            0,
            null,
        );
    }
}

// utils
fn createShaderModule(allocator: Allocator, path: []const u8) !vk.ShaderModule {
    var binary_resource = try BinaryResource.init(allocator, path);
    defer binary_resource.deinit();

    return try ctx().device_api.createShaderModule(
        ctx().device,
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
    if (std.mem.eql(u8, render_pass_name, "world")) return ctx().world_render_pass.handle;
    if (std.mem.eql(u8, render_pass_name, "ui")) return ctx().ui_render_pass.handle;

    return error.UnknownRenderPass;
}
