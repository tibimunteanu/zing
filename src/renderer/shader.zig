const std = @import("std");
const pool = @import("zpool");
const vk = @import("vk.zig");
const config = @import("../config.zig");
const zing = @import("../zing.zig");
const Buffer = @import("buffer.zig");
const BinaryResource = @import("../resources/binary_resource.zig");
const TextureSystem = @import("../systems/texture_system.zig");

const TextureHandle = TextureSystem.TextureHandle;
const Allocator = std.mem.Allocator;
const Array = std.BoundedArray;

// TODO: TextureMap
// TODO: local push constant uniform block and apply local
// TODO: keep sampler uniforms separate or index lookup
// TODO: global_textures
// TODO: flags
// TODO: descriptor pool free list
// TODO: needs update

const Shader = @This();

pub const Scope = enum(u8) {
    global = 0,
    instance = 1,
    local = 2,
};

pub const Attribute = struct {
    name: Array(u8, 256),
    data_type: DataType,
    size: u32,

    pub const DataType = enum(u8) {
        int8,
        uint8,
        int16,
        uint16,
        int32,
        uint32,
        float32,
        float32_2,
        float32_3,
        float32_4,

        pub fn getSize(self: DataType) u32 {
            return switch (self) {
                .int8, .uint8 => 1,
                .int16, .uint16 => 2,
                .int32, .uint32, .float32 => 4,
                .float32_2 => 8,
                .float32_3 => 12,
                .float32_4 => 16,
            };
        }

        fn toVkFormat(self: DataType) !vk.Format {
            return switch (self) {
                .int8 => .r8_sint,
                .uint8 => .r8_uint,
                .int16 => .r16_sint,
                .uint16 => .r16_uint,
                .int32 => .r32_sint,
                .uint32 => .r32_uint,
                .float32 => .r32_sfloat,
                .float32_2 => .r32g32_sfloat,
                .float32_3 => .r32g32b32_sfloat,
                .float32_4 => .r32g32b32a32_sfloat,
            };
        }
    };
};

pub const Uniform = struct {
    scope: Scope,
    name: Array(u8, 256),
    data_type: DataType,
    size: u32,
    offset: u32,
    texture_index: u16,

    pub const DataType = enum(u8) {
        int8,
        uint8,
        int16,
        uint16,
        int32,
        uint32,
        float32,
        float32_2,
        float32_3,
        float32_4,
        mat4,
        sampler,

        pub fn getSize(self: DataType) u32 {
            return switch (self) {
                .sampler => 0,
                .int8, .uint8 => 1,
                .int16, .uint16 => 2,
                .int32, .uint32, .float32 => 4,
                .float32_2 => 8,
                .float32_3 => 12,
                .float32_4 => 16,
                .mat4 => 64,
            };
        }
    };
};

pub const ScopeState = struct {
    size: u32 = 0,
    stride: u32 = 0,
    binding_count: u32 = 0,
    uniform_count: u32 = 0,
    uniform_sampler_count: u16 = 0,
};

pub const GlobalState = struct {
    ubo_offset: u64,
    descriptor_sets: Array(vk.DescriptorSet, config.swapchain_max_images),
};

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

pub const UniformHandle = u8;

allocator: Allocator,
name: Array(u8, 256),

attributes: std.ArrayList(Attribute),

uniforms: std.ArrayList(Uniform),
uniform_lookup: std.StringHashMap(UniformHandle),

global_scope: ScopeState,
instance_scope: ScopeState,
local_scope: ScopeState,

shader_modules: Array(vk.ShaderModule, config.shader_max_stages),
descriptor_pool: vk.DescriptorPool,
descriptor_set_layouts: Array(vk.DescriptorSetLayout, 2),
pipeline_layout: vk.PipelineLayout,
pipeline: vk.Pipeline,

global_state: GlobalState,
instance_state_pool: InstancePool,

ubo: Buffer,
ubo_ptr: [*]u8,
ubo_bound_offset: u64,
ubo_bound_instance_handle: InstanceHandle,

pub fn init(allocator: Allocator, shader_config: Config) !Shader {
    var self: Shader = undefined;
    self.allocator = allocator;

    // initialize everything so we can only do an errdefer self.deinit();
    self.attributes.capacity = 0;

    self.uniforms.capacity = 0;
    self.uniform_lookup.unmanaged.metadata = null;

    self.global_scope = ScopeState{};
    self.local_scope = ScopeState{};
    self.instance_scope = ScopeState{};

    self.shader_modules.len = 0;
    self.descriptor_set_layouts.len = 0;
    self.descriptor_pool = .null_handle;
    self.pipeline_layout = .null_handle;
    self.pipeline = .null_handle;

    self.global_state = GlobalState{
        .ubo_offset = 0,
        .descriptor_sets = try Array(vk.DescriptorSet, config.swapchain_max_images).init(0),
    };
    self.instance_state_pool._storage.capacity = 0;

    self.ubo.handle = .null_handle;
    self.ubo_bound_offset = 0;
    self.ubo_bound_instance_handle = InstanceHandle.nil;

    errdefer self.deinit();

    self.name = try Array(u8, 256).fromSlice(shader_config.name);

    // parse attributes and uniforms from config
    self.attributes = try std.ArrayList(Attribute).initCapacity(allocator, 8);

    try self.addAttributes(shader_config.attributes);

    self.uniforms = try std.ArrayList(Uniform).initCapacity(allocator, 8);
    self.uniform_lookup = std.StringHashMap(UniformHandle).init(allocator);

    // NOTE: this also sets scope states
    try self.addUniforms(shader_config.uniforms);

    // create shader stages
    var shader_stages = try Array(vk.PipelineShaderStageCreateInfo, config.shader_max_stages).init(0);

    try self.shader_modules.resize(0);

    for (shader_config.stages) |stage| {
        const module = try createShaderModule(allocator, stage.path);
        try self.shader_modules.append(module);

        try shader_stages.append(vk.PipelineShaderStageCreateInfo{
            .flags = .{},
            .stage = try parseVkShaderStageFlags(stage.stage_type),
            .module = module,
            .p_name = "main",
            .p_specialization_info = null,
        });
    }

    // create vertex input state
    var attribute_descriptions = try Array(vk.VertexInputAttributeDescription, config.shader_max_attributes).init(0);

    var offset: u32 = 0;
    for (self.attributes.items, 0..) |attribute, location| {
        try attribute_descriptions.append(vk.VertexInputAttributeDescription{
            .binding = 0,
            .location = @intCast(location),
            .format = try attribute.data_type.toVkFormat(),
            .offset = offset,
        });

        offset += attribute.size;
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

    try self.descriptor_set_layouts.resize(0);

    // create global descriptor set layouts
    var global_bindings = try Array(vk.DescriptorSetLayoutBinding, 2).init(0);

    try global_bindings.append(
        vk.DescriptorSetLayoutBinding{
            .binding = 0,
            .descriptor_count = 1,
            .descriptor_type = .uniform_buffer,
            .p_immutable_samplers = null,
            .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
        },
    );

    if (self.global_scope.uniform_sampler_count > 0) {
        try global_bindings.append(
            vk.DescriptorSetLayoutBinding{
                .binding = 1,
                .descriptor_count = self.global_scope.uniform_sampler_count,
                .descriptor_type = .combined_image_sampler,
                .p_immutable_samplers = null,
                .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
            },
        );
    }

    try self.descriptor_set_layouts.append(try zing.renderer.device_api.createDescriptorSetLayout(
        zing.renderer.device,
        &vk.DescriptorSetLayoutCreateInfo{
            .binding_count = global_bindings.len,
            .p_bindings = global_bindings.slice().ptr,
        },
        null,
    ));

    self.global_scope.binding_count = global_bindings.len;

    // create instance descriptor set layouts
    if (self.instance_scope.uniform_count + self.instance_scope.uniform_sampler_count > 0) {
        var instance_bindings = try Array(vk.DescriptorSetLayoutBinding, 2).init(0);

        try instance_bindings.append(
            vk.DescriptorSetLayoutBinding{
                .binding = 0,
                .descriptor_count = 1,
                .descriptor_type = .uniform_buffer,
                .p_immutable_samplers = null,
                .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
            },
        );

        if (self.instance_scope.uniform_sampler_count > 0) {
            try instance_bindings.append(
                vk.DescriptorSetLayoutBinding{
                    .binding = 1,
                    .descriptor_count = self.instance_scope.uniform_sampler_count,
                    .descriptor_type = .combined_image_sampler,
                    .p_immutable_samplers = null,
                    .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
                },
            );
        }

        try self.descriptor_set_layouts.append(try zing.renderer.device_api.createDescriptorSetLayout(
            zing.renderer.device,
            &vk.DescriptorSetLayoutCreateInfo{
                .binding_count = instance_bindings.len,
                .p_bindings = instance_bindings.slice().ptr,
            },
            null,
        ));

        self.instance_scope.binding_count = instance_bindings.len;
    }

    // create local push constant ranges
    var push_constant_ranges = try Array(vk.PushConstantRange, 32).init(0);
    var push_constant_offset: u32 = 0;

    for (self.uniforms.items) |uniform| {
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

    // create pipeline layout
    self.pipeline_layout = try zing.renderer.device_api.createPipelineLayout(zing.renderer.device, &.{
        .flags = .{},
        .set_layout_count = self.descriptor_set_layouts.len,
        .p_set_layouts = self.descriptor_set_layouts.slice().ptr,
        .push_constant_range_count = push_constant_ranges.len,
        .p_push_constant_ranges = push_constant_ranges.slice().ptr,
    }, null);

    // create other pipeline state
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

    // create pipeline
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
        .render_pass = try parseVkRenderPass(shader_config.render_pass_name),
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    _ = try zing.renderer.device_api.createGraphicsPipelines(
        zing.renderer.device,
        .null_handle,
        1,
        @ptrCast(&pipeline_create_info),
        null,
        @ptrCast(&self.pipeline),
    );

    // create descriptor pool
    const descriptor_pool_sizes = [_]vk.DescriptorPoolSize{
        vk.DescriptorPoolSize{ .type = .uniform_buffer, .descriptor_count = 1024 },
        vk.DescriptorPoolSize{ .type = .combined_image_sampler, .descriptor_count = 4096 },
    };

    self.descriptor_pool = try zing.renderer.device_api.createDescriptorPool(
        zing.renderer.device,
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
    try global_ubo_layouts.appendNTimes(global_ubo_layout, zing.renderer.swapchain.images.len);

    const global_ubo_descriptor_set_alloc_info = vk.DescriptorSetAllocateInfo{
        .descriptor_pool = self.descriptor_pool,
        .descriptor_set_count = global_ubo_layouts.len,
        .p_set_layouts = global_ubo_layouts.slice().ptr,
    };

    try self.global_state.descriptor_sets.resize(global_ubo_layouts.len);

    try zing.renderer.device_api.allocateDescriptorSets(
        zing.renderer.device,
        &global_ubo_descriptor_set_alloc_info,
        self.global_state.descriptor_sets.slice().ptr,
    );

    // create and map ubo
    const ubo_alignment: u32 = @intCast(zing.renderer.physical_device.properties.limits.min_uniform_buffer_offset_alignment);

    self.global_scope.stride = std.mem.alignForward(u32, self.global_scope.size, ubo_alignment);
    self.instance_scope.stride = std.mem.alignForward(u32, self.instance_scope.size, ubo_alignment);

    const ubo_size = self.global_scope.stride + (self.instance_scope.stride * config.shader_max_instances);

    self.ubo = try Buffer.init(
        allocator,
        ubo_size,
        .{ .transfer_dst_bit = true, .uniform_buffer_bit = true },
        .{
            .device_local_bit = zing.renderer.physical_device.supports_local_host_visible,
            .host_visible_bit = true,
            .host_coherent_bit = true,
        },
        .{ .managed = true, .bind_on_create = true },
    );

    self.ubo_ptr = try self.ubo.lock(0, vk.WHOLE_SIZE, .{});

    // alloc global ubo range
    self.global_state.ubo_offset = try self.ubo.alloc(self.global_scope.stride);

    // create instance state pool
    self.instance_state_pool = try InstancePool.initMaxCapacity(allocator);

    return self;
}

pub fn deinit(self: *Shader) void {
    if (self.instance_state_pool.capacity() > 0) {
        self.instance_state_pool.deinit();
    }

    if (self.ubo.handle != .null_handle) {
        self.ubo.deinit();
    }

    if (self.global_state.descriptor_sets.len > 0) {
        zing.renderer.device_api.freeDescriptorSets(
            zing.renderer.device,
            self.descriptor_pool,
            self.global_state.descriptor_sets.len,
            self.global_state.descriptor_sets.slice().ptr,
        ) catch {};
        self.global_state.descriptor_sets.len = 0;
    }

    if (self.descriptor_pool != .null_handle) {
        zing.renderer.device_api.destroyDescriptorPool(zing.renderer.device, self.descriptor_pool, null);
    }

    if (self.pipeline != .null_handle) {
        zing.renderer.device_api.destroyPipeline(zing.renderer.device, self.pipeline, null);
    }

    if (self.pipeline_layout != .null_handle) {
        zing.renderer.device_api.destroyPipelineLayout(zing.renderer.device, self.pipeline_layout, null);
    }

    for (self.descriptor_set_layouts.slice()) |descriptor_set_layout| {
        if (descriptor_set_layout != .null_handle) {
            zing.renderer.device_api.destroyDescriptorSetLayout(zing.renderer.device, descriptor_set_layout, null);
        }
    }
    self.descriptor_set_layouts.len = 0;

    for (self.shader_modules.slice()) |module| {
        if (module != .null_handle) {
            zing.renderer.device_api.destroyShaderModule(zing.renderer.device, module, null);
        }
    }
    self.shader_modules.len = 0;

    if (self.uniform_lookup.unmanaged.metadata != null) {
        var it = self.uniform_lookup.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }

        self.uniform_lookup.deinit();
    }

    if (self.uniforms.capacity > 0) {
        self.uniforms.deinit();
    }

    if (self.attributes.capacity > 0) {
        self.attributes.deinit();
    }

    self.* = undefined;
}

pub fn initInstance(self: *Shader) !InstanceHandle {
    var instance_state: InstanceState = undefined;

    // allocate instance descriptor sets
    const instance_ubo_layout = self.descriptor_set_layouts.get(@intFromEnum(Shader.Scope.instance));
    var instance_ubo_layouts = try Array(vk.DescriptorSetLayout, config.swapchain_max_images).init(0);
    try instance_ubo_layouts.appendNTimes(instance_ubo_layout, zing.renderer.swapchain.images.len);

    const instance_ubo_descriptor_set_alloc_info = vk.DescriptorSetAllocateInfo{
        .descriptor_pool = self.descriptor_pool,
        .descriptor_set_count = instance_ubo_layouts.len,
        .p_set_layouts = instance_ubo_layouts.slice().ptr,
    };

    try instance_state.descriptor_sets.resize(instance_ubo_layouts.len);

    try zing.renderer.device_api.allocateDescriptorSets(
        zing.renderer.device,
        &instance_ubo_descriptor_set_alloc_info,
        instance_state.descriptor_sets.slice().ptr,
    );

    errdefer {
        zing.renderer.device_api.freeDescriptorSets(
            zing.renderer.device,
            self.descriptor_pool,
            instance_state.descriptor_sets.len,
            instance_state.descriptor_sets.slice().ptr,
        ) catch {};
        instance_state.descriptor_sets.len = 0;
    }

    // allocate instance ubo range
    instance_state.ubo_offset = try self.ubo.alloc(self.instance_scope.stride);
    errdefer self.ubo.free(instance_state.ubo_offset, self.instance_scope.stride) catch {};

    // clear descriptor states
    instance_state.descriptor_states = try Array(DescriptorState, config.shader_max_bindings).init(
        self.instance_scope.binding_count,
    );
    for (instance_state.descriptor_states.slice()) |*descriptor_state| {
        try descriptor_state.generations.resize(0);
        try descriptor_state.generations.appendNTimes(null, zing.renderer.swapchain.images.len);

        try descriptor_state.handles.resize(0);
        try descriptor_state.handles.appendNTimes(TextureHandle.nil, zing.renderer.swapchain.images.len);
    }

    // clear textures to default texture handle
    const default_texture_handle = zing.sys.texture.acquireDefaultTexture();
    try instance_state.textures.resize(0);
    try instance_state.textures.appendNTimes(default_texture_handle, self.instance_scope.uniform_sampler_count);

    // add instance to pool
    const handle = try self.instance_state_pool.add(.{
        .instance_state = instance_state,
    });

    return handle;
}

pub fn deinitInstance(self: *Shader, handle: InstanceHandle) void {
    if (self.instance_state_pool.getColumnPtrIfLive(handle, .instance_state)) |instance_state| {
        self.instance_state_pool.removeAssumeLive(handle);

        self.ubo.free(instance_state.ubo_offset, self.instance_scope.stride) catch {};

        zing.renderer.device_api.freeDescriptorSets(
            zing.renderer.device,
            self.descriptor_pool,
            instance_state.descriptor_sets.len,
            instance_state.descriptor_sets.slice().ptr,
        ) catch {};
        instance_state.descriptor_sets.len = 0;

        instance_state.* = undefined;
    }
}

pub fn bind(self: *const Shader) void {
    zing.renderer.device_api.cmdBindPipeline(zing.renderer.getCurrentCommandBuffer().handle, .graphics, self.pipeline);
}

pub fn bindGlobal(self: *Shader) void {
    self.ubo_bound_instance_handle = InstanceHandle.nil;
    self.ubo_bound_offset = self.global_state.ubo_offset;
}

pub fn bindInstance(self: *Shader, handle: InstanceHandle) !void {
    if (self.instance_state_pool.getColumnPtrIfLive(handle, .instance_state)) |instance_state| {
        self.ubo_bound_instance_handle = handle;
        self.ubo_bound_offset = instance_state.ubo_offset;
    } else return error.InvalidShaderInstanceHandle;
}

pub fn getUniformHandle(self: *Shader, name: []const u8) !UniformHandle {
    return self.uniform_lookup.get(name) orelse error.UniformNotFound;
}

pub fn setUniform(self: *Shader, uniform: anytype, value: anytype) !void {
    const uniform_handle = if (@TypeOf(uniform) == UniformHandle)
        uniform
    else if (@typeInfo(@TypeOf(uniform)) == .Pointer and std.meta.Elem(@TypeOf(uniform)) == u8)
        try self.getUniformHandle(uniform)
    else
        unreachable;

    const p_uniform = &self.uniforms.items[uniform_handle];

    if (p_uniform.data_type == .sampler) {
        if (@TypeOf(value) != TextureHandle) {
            return error.InvalidSamplerValue;
        }

        switch (p_uniform.scope) {
            .global => return error.GlobalTexturesNotYetSupported,
            .instance => {
                if (self.instance_state_pool.getColumnPtrIfLive(self.ubo_bound_instance_handle, .instance_state)) |instance_state| {
                    instance_state.textures.slice()[p_uniform.texture_index] = value;
                } else return error.InvalidShaderInstanceHandle;
            },
            .local => return error.CannotSetLocalSamplers,
        }
    } else {
        switch (p_uniform.scope) {
            .local => {
                zing.renderer.device_api.cmdPushConstants(
                    zing.renderer.getCurrentCommandBuffer().handle,
                    self.pipeline_layout,
                    .{ .vertex_bit = true, .fragment_bit = true },
                    p_uniform.offset,
                    p_uniform.size,
                    &value,
                );
            },
            .global, .instance => {
                const ubo_offset_ptr = @as([*]u8, @ptrFromInt(
                    @intFromPtr(self.ubo_ptr) + self.ubo_bound_offset + p_uniform.offset,
                ));

                @memcpy(ubo_offset_ptr, &std.mem.toBytes(value));
            },
        }
    }
}

pub fn applyGlobal(self: *Shader) !void {
    const image_index = zing.renderer.swapchain.image_index;
    const command_buffer = zing.renderer.getCurrentCommandBuffer();
    const descriptor_set = self.global_state.descriptor_sets.get(image_index);

    const buffer_info = vk.DescriptorBufferInfo{
        .buffer = self.ubo.handle,
        .offset = self.global_state.ubo_offset,
        .range = self.global_scope.stride,
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

    if (self.global_scope.uniform_sampler_count > 0) {
        return error.GlobalTexturesNotYetSupported;
    }

    if (descriptor_writes.len > 0) {
        zing.renderer.device_api.updateDescriptorSets(
            zing.renderer.device,
            descriptor_writes.len,
            @ptrCast(descriptor_writes.slice().ptr),
            0,
            null,
        );
    }

    zing.renderer.device_api.cmdBindDescriptorSets(
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

pub fn applyInstance(self: *Shader) !void {
    const image_index = zing.renderer.swapchain.image_index;
    const command_buffer = zing.renderer.getCurrentCommandBuffer();

    if (self.instance_state_pool.getColumnPtrIfLive(self.ubo_bound_instance_handle, .instance_state)) |instance_state| {
        const descriptor_set = instance_state.descriptor_sets.get(image_index);

        var descriptor_writes = try Array(vk.WriteDescriptorSet, 2).init(0);

        var dst_binding: u32 = 0;

        // descriptor 0 - uniform buffer
        const buffer_info = vk.DescriptorBufferInfo{
            .buffer = self.ubo.handle,
            .offset = instance_state.ubo_offset,
            .range = self.instance_scope.stride,
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

        for (0..self.instance_scope.uniform_sampler_count) |sampler_index| {
            const texture_handle = instance_state.textures.slice()[sampler_index];
            const texture = try zing.sys.texture.get(texture_handle);

            try image_infos.append(vk.DescriptorImageInfo{
                .image_layout = .shader_read_only_optimal,
                .image_view = texture.image.view,
                .sampler = texture.sampler,
            });
        }

        try descriptor_writes.append(vk.WriteDescriptorSet{
            .dst_set = descriptor_set,
            .dst_binding = dst_binding,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = self.instance_scope.uniform_sampler_count,
            .dst_array_element = 0,
            .p_buffer_info = undefined,
            .p_image_info = @ptrCast(image_infos.slice().ptr),
            .p_texel_buffer_view = undefined,
        });

        if (descriptor_writes.len > 0) {
            zing.renderer.device_api.updateDescriptorSets(
                zing.renderer.device,
                descriptor_writes.len,
                @ptrCast(descriptor_writes.slice().ptr),
                0,
                null,
            );
        }

        zing.renderer.device_api.cmdBindDescriptorSets(
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
fn addAttributes(self: *Shader, attribute_configs: []const AttributeConfig) !void {
    for (attribute_configs) |attribute_config| {
        const attribute_data_type = try parseAttributeDataType(attribute_config.data_type);
        const attribute_size = attribute_data_type.getSize();

        try self.attributes.append(Attribute{
            .name = try Array(u8, 256).fromSlice(attribute_config.name),
            .data_type = attribute_data_type,
            .size = attribute_size,
        });
    }
}

fn addUniforms(self: *Shader, uniform_configs: []const UniformConfig) !void {
    for (uniform_configs) |uniform_config| {
        const scope = try parseUniformScope(uniform_config.scope);

        var scope_config = switch (scope) {
            .global => &self.global_scope,
            .instance => &self.instance_scope,
            .local => &self.local_scope,
        };

        const uniform_handle: UniformHandle = @truncate(self.uniforms.items.len);
        const uniform_data_type = try parseUniformDataType(uniform_config.data_type);
        const uniform_size = uniform_data_type.getSize();
        const is_sampler = uniform_data_type == .sampler;

        try self.uniforms.append(Uniform{
            .scope = scope,
            .name = try Array(u8, 256).fromSlice(uniform_config.name),
            .data_type = uniform_data_type,
            .size = uniform_size,
            .offset = if (is_sampler) 0 else scope_config.stride,
            .texture_index = if (is_sampler) scope_config.uniform_sampler_count else 0,
        });

        try self.uniform_lookup.put(try self.allocator.dupe(u8, uniform_config.name), uniform_handle);

        if (is_sampler) {
            if (scope == .local) {
                return error.LocalSamplersNotSupported;
            }
            scope_config.uniform_sampler_count += 1;
        } else {
            scope_config.uniform_count += 1;
            scope_config.size += uniform_size;
            scope_config.stride += if (scope == .local) std.mem.alignForward(u32, uniform_size, 4) else uniform_size;
        }
    }
}

fn createShaderModule(allocator: Allocator, path: []const u8) !vk.ShaderModule {
    var binary_resource = try BinaryResource.init(allocator, path);
    defer binary_resource.deinit();

    return try zing.renderer.device_api.createShaderModule(
        zing.renderer.device,
        &vk.ShaderModuleCreateInfo{
            .flags = .{},
            .code_size = binary_resource.bytes.len,
            .p_code = @ptrCast(@alignCast(binary_resource.bytes.ptr)),
        },
        null,
    );
}

// parse from config
inline fn parseUniformScope(scope: []const u8) !Scope {
    return std.meta.stringToEnum(Scope, scope) orelse error.UnknownUniformScope;
}

inline fn parseUniformDataType(data_type: []const u8) !Uniform.DataType {
    return std.meta.stringToEnum(Uniform.DataType, data_type) orelse error.UnknownUniformDataType;
}

inline fn parseAttributeDataType(data_type: []const u8) !Attribute.DataType {
    return std.meta.stringToEnum(Attribute.DataType, data_type) orelse error.UnknownAttributeDataType;
}

inline fn parseVkShaderStageFlags(stage_type: []const u8) !vk.ShaderStageFlags {
    if (std.mem.eql(u8, stage_type, "vertex")) return .{ .vertex_bit = true };
    if (std.mem.eql(u8, stage_type, "fragment")) return .{ .fragment_bit = true };

    return error.UnknownShaderStage;
}

inline fn parseVkRenderPass(render_pass_name: []const u8) !vk.RenderPass {
    if (std.mem.eql(u8, render_pass_name, "world")) return zing.renderer.world_render_pass.handle;
    if (std.mem.eql(u8, render_pass_name, "ui")) return zing.renderer.ui_render_pass.handle;

    return error.UnknownRenderPass;
}

// config
pub const Config = struct {
    name: []const u8 = "new_shader",
    render_pass_name: []const u8 = "world",
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
