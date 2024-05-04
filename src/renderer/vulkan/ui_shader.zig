const std = @import("std");
const vk = @import("vk.zig");
const math = @import("zmath");

const config = @import("../../config.zig");
const Engine = @import("../../engine.zig");
const Renderer = @import("../renderer.zig");
const Context = @import("context.zig");
const Buffer = @import("buffer.zig");
const CommandBuffer = @import("command_buffer.zig");
const Texture = @import("../texture.zig");
const Material = @import("../material.zig");
const BinaryResource = @import("../../resources/binary_resource.zig");
const TextureHandle = @import("../../systems/texture_system.zig").TextureHandle;
const MaterialHandle = @import("../../systems/material_system.zig").MaterialHandle;

const Vertex2D = Renderer.Vertex2D;
const TextureData = Context.TextureData;
const GeometryRenderData = Renderer.GeometryRenderData;

const Allocator = std.mem.Allocator;

const Shader = @This();

const shader_path_format = "shaders/{s}.{s}.spv";
const shader_name = "ui_shader";

pub const instance_max_count: u32 = 1024;
pub const descriptor_count: u32 = 2;
pub const sampler_count: u32 = 1;

pub const GlobalUniformData = struct {
    projection: math.Mat,
    view: math.Mat,
    _reserved_1: math.Mat = undefined,
    _reserved_2: math.Mat = undefined,
};

pub const InstanceUniformData = struct {
    diffuse_color: math.Vec,
    _reserved_0: math.Vec = undefined,
    _reserved_1: math.Vec = undefined,
    _reserved_2: math.Vec = undefined,
};

pub const DescriptorState = struct {
    generations: std.BoundedArray(?u32, config.max_swapchain_image_count),
    handles: std.BoundedArray(TextureHandle, config.max_swapchain_image_count),
};

pub const InstanceState = struct {
    descriptor_sets: std.BoundedArray(vk.DescriptorSet, config.max_swapchain_image_count),
    descriptor_states: [descriptor_count]DescriptorState,
};

context: *const Context,

vertex_shader_module: vk.ShaderModule,
fragment_shader_module: vk.ShaderModule,

pipeline: vk.Pipeline,
pipeline_layout: vk.PipelineLayout,
bind_point: vk.PipelineBindPoint,

global_uniform_data: GlobalUniformData,
global_descriptor_pool: vk.DescriptorPool,
global_descriptor_set_layout: vk.DescriptorSetLayout,
global_descriptor_sets: std.BoundedArray(vk.DescriptorSet, config.max_swapchain_image_count),
global_uniform_buffer: Buffer,

material_descriptor_pool: vk.DescriptorPool,
material_descriptor_set_layout: vk.DescriptorSetLayout,
material_uniform_buffer: Buffer,
material_uniform_buffer_index: ?u32, // TODO: turn this into a proper pool

instance_states: [instance_max_count]InstanceState,

sampler_uses: [sampler_count]Texture.Use,

// public
pub fn init(allocator: Allocator, context: *const Context) !Shader {
    var self: Shader = undefined;
    self.context = context;
    self.bind_point = .graphics;

    var vert_path_buf: [config.max_path_length]u8 = undefined;
    const vert_path = try std.fmt.bufPrint(&vert_path_buf, shader_path_format, .{ shader_name, "vert" });

    // NOTE: allocator only needed for resource loading
    self.vertex_shader_module = try self.createShaderModule(allocator, vert_path);
    errdefer context.device_api.destroyShaderModule(context.device, self.vertex_shader_module, null);

    var frag_path_buf: [config.max_path_length]u8 = undefined;
    const frag_path = try std.fmt.bufPrint(&frag_path_buf, shader_path_format, .{ shader_name, "frag" });

    self.fragment_shader_module = try self.createShaderModule(allocator, frag_path);
    errdefer context.device_api.destroyShaderModule(context.device, self.fragment_shader_module, null);

    const shader_stages = [_]vk.PipelineShaderStageCreateInfo{
        .{
            .flags = .{},
            .stage = .{ .vertex_bit = true },
            .module = self.vertex_shader_module,
            .p_name = "main",
            .p_specialization_info = null,
        },
        .{
            .flags = .{},
            .stage = .{ .fragment_bit = true },
            .module = self.fragment_shader_module,
            .p_name = "main",
            .p_specialization_info = null,
        },
    };

    // global descriptors
    const global_ubo_layout_bindings = [_]vk.DescriptorSetLayoutBinding{
        vk.DescriptorSetLayoutBinding{
            .binding = 0,
            .descriptor_count = 1,
            .descriptor_type = .uniform_buffer,
            .p_immutable_samplers = null,
            .stage_flags = .{ .vertex_bit = true },
        },
    };

    self.global_descriptor_set_layout = try context.device_api.createDescriptorSetLayout(
        context.device,
        &vk.DescriptorSetLayoutCreateInfo{
            .binding_count = global_ubo_layout_bindings.len,
            .p_bindings = &global_ubo_layout_bindings,
        },
        null,
    );
    errdefer context.device_api.destroyDescriptorSetLayout(context.device, self.global_descriptor_set_layout, null);

    const global_ubo_pool_sizes = [_]vk.DescriptorPoolSize{
        vk.DescriptorPoolSize{
            .type = .uniform_buffer,
            .descriptor_count = @intCast(context.swapchain.images.len),
        },
    };

    self.global_descriptor_pool = try context.device_api.createDescriptorPool(
        context.device,
        &vk.DescriptorPoolCreateInfo{
            .flags = .{},
            .pool_size_count = global_ubo_pool_sizes.len,
            .p_pool_sizes = &global_ubo_pool_sizes,
            .max_sets = @intCast(context.swapchain.images.len),
        },
        null,
    );
    errdefer context.device_api.destroyDescriptorPool(context.device, self.global_descriptor_pool, null);

    self.sampler_uses[0] = .map_diffuse;

    // local / material descriptors
    const descriptor_types = [descriptor_count]vk.DescriptorType{
        .uniform_buffer,
        .combined_image_sampler,
    };

    var material_ubo_layout_bindings: [descriptor_types.len]vk.DescriptorSetLayoutBinding = undefined;
    for (&material_ubo_layout_bindings, descriptor_types, 0..) |*binding, descriptor_type, i| {
        binding.* = vk.DescriptorSetLayoutBinding{
            .binding = @intCast(i),
            .descriptor_count = 1,
            .descriptor_type = descriptor_type,
            .p_immutable_samplers = null,
            .stage_flags = .{ .fragment_bit = true },
        };
    }

    self.material_descriptor_set_layout = try context.device_api.createDescriptorSetLayout(
        context.device,
        &vk.DescriptorSetLayoutCreateInfo{
            .binding_count = material_ubo_layout_bindings.len,
            .p_bindings = @ptrCast(&material_ubo_layout_bindings),
        },
        null,
    );
    errdefer context.device_api.destroyDescriptorSetLayout(context.device, self.material_descriptor_set_layout, null);

    const material_ubo_pool_sizes = [_]vk.DescriptorPoolSize{
        vk.DescriptorPoolSize{
            .type = .uniform_buffer,
            .descriptor_count = instance_max_count,
        },
        vk.DescriptorPoolSize{
            .type = .combined_image_sampler,
            .descriptor_count = sampler_count * instance_max_count,
        },
    };

    self.material_descriptor_pool = try context.device_api.createDescriptorPool(
        context.device,
        &vk.DescriptorPoolCreateInfo{
            .flags = .{ .free_descriptor_set_bit = true },
            .pool_size_count = material_ubo_pool_sizes.len,
            .p_pool_sizes = &material_ubo_pool_sizes,
            .max_sets = instance_max_count,
        },
        null,
    );
    errdefer context.device_api.destroyDescriptorPool(context.device, self.material_descriptor_pool, null);

    const layouts = [_]vk.DescriptorSetLayout{
        self.global_descriptor_set_layout,
        self.material_descriptor_set_layout,
    };

    const push_constant_range = vk.PushConstantRange{
        .stage_flags = .{ .vertex_bit = true },
        .offset = @sizeOf(math.Mat) * 0,
        .size = @sizeOf(math.Mat) * 2,
    };

    self.pipeline_layout = try context.device_api.createPipelineLayout(context.device, &.{
        .flags = .{},
        .set_layout_count = layouts.len,
        .p_set_layouts = &layouts,
        .push_constant_range_count = 1,
        .p_push_constant_ranges = @ptrCast(&push_constant_range),
    }, null);

    errdefer context.device_api.destroyPipelineLayout(context.device, self.pipeline_layout, null);

    const binding_description = vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(Vertex2D),
        .input_rate = .vertex,
    };

    const attribute_description = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Vertex2D, "position"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Vertex2D, "texcoord"),
        },
        .{
            .binding = 0,
            .location = 2,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(Vertex2D, "color"),
        },
    };

    const vertex_input_state = vk.PipelineVertexInputStateCreateInfo{
        .flags = .{},
        .vertex_binding_description_count = 1,
        .p_vertex_binding_descriptions = @ptrCast(&binding_description),
        .vertex_attribute_description_count = attribute_description.len,
        .p_vertex_attribute_descriptions = &attribute_description,
    };

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
        .stage_count = 2,
        .p_stages = &shader_stages,
        .p_viewport_state = &viewport_state,
        .p_vertex_input_state = &vertex_input_state,
        .p_input_assembly_state = &input_assembly_state,
        .p_tessellation_state = null,
        .p_rasterization_state = &rasterization_state,
        .p_multisample_state = &multisample_state,
        .p_depth_stencil_state = null,
        .p_color_blend_state = &color_blend_state,
        .p_dynamic_state = &dynamic_state,
        .layout = self.pipeline_layout,
        .render_pass = context.ui_render_pass.handle,
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
    errdefer context.device_api.destroyPipeline(context.device, self.pipeline, null);

    self.global_uniform_buffer = try Buffer.init(
        context,
        @as(usize, @sizeOf(GlobalUniformData)) * context.swapchain.images.len,
        .{ .transfer_dst_bit = true, .uniform_buffer_bit = true },
        .{
            .device_local_bit = context.physical_device.supports_local_host_visible,
            .host_visible_bit = true,
            .host_coherent_bit = true,
        },
        .{ .bind_on_create = true },
    );
    errdefer self.global_uniform_buffer.deinit();

    var global_ubo_layouts: [config.max_swapchain_image_count]vk.DescriptorSetLayout = undefined;
    for (0..context.swapchain.images.len) |i| {
        global_ubo_layouts[i] = self.global_descriptor_set_layout;
    }

    const global_ubo_descriptor_set_alloc_info = vk.DescriptorSetAllocateInfo{
        .descriptor_pool = self.global_descriptor_pool,
        .descriptor_set_count = context.swapchain.images.len,
        .p_set_layouts = &global_ubo_layouts,
    };

    self.global_descriptor_sets.len = context.swapchain.images.len;
    try context.device_api.allocateDescriptorSets(
        context.device,
        &global_ubo_descriptor_set_alloc_info,
        self.global_descriptor_sets.slice().ptr,
    );
    errdefer {
        context.device_api.freeDescriptorSets(
            context.device,
            self.material_descriptor_pool,
            context.swapchain.images.len,
            self.global_descriptor_sets.slice().ptr,
        ) catch {
            std.log.err("Could not free global descriptor set for material: {s}", .{shader_name});
        };
        self.global_descriptor_sets.len = 0;
    }

    self.material_uniform_buffer = try Buffer.init(
        context,
        @sizeOf(InstanceUniformData) * instance_max_count,
        .{ .transfer_dst_bit = true, .uniform_buffer_bit = true },
        .{
            .device_local_bit = context.physical_device.supports_local_host_visible,
            .host_visible_bit = true,
            .host_coherent_bit = true,
        },
        .{ .bind_on_create = true },
    );
    errdefer self.material_uniform_buffer.deinit();

    self.material_uniform_buffer_index = 0;

    return self;
}

pub fn deinit(self: *Shader) void {
    self.material_uniform_buffer.deinit();
    self.global_uniform_buffer.deinit();

    self.context.device_api.destroyPipeline(self.context.device, self.pipeline, null);
    self.context.device_api.destroyPipelineLayout(self.context.device, self.pipeline_layout, null);

    self.context.device_api.destroyDescriptorPool(self.context.device, self.material_descriptor_pool, null);
    self.context.device_api.destroyDescriptorSetLayout(self.context.device, self.material_descriptor_set_layout, null);

    self.context.device_api.destroyDescriptorPool(self.context.device, self.global_descriptor_pool, null);
    self.context.device_api.destroyDescriptorSetLayout(self.context.device, self.global_descriptor_set_layout, null);

    self.context.device_api.destroyShaderModule(self.context.device, self.fragment_shader_module, null);
    self.context.device_api.destroyShaderModule(self.context.device, self.vertex_shader_module, null);
}

pub fn bind(self: *const Shader, command_buffer: *const CommandBuffer) void {
    self.context.device_api.cmdBindPipeline(command_buffer.handle, self.bind_point, self.pipeline);
}

pub fn updateGlobalUniformData(self: *Shader) !void {
    const image_index = self.context.swapchain.image_index;
    const command_buffer = self.context.getCurrentCommandBuffer();
    const global_descriptor_set = self.global_descriptor_sets.slice()[image_index];

    const range: u32 = @sizeOf(GlobalUniformData);
    const offset: vk.DeviceSize = @sizeOf(GlobalUniformData) * image_index;

    try self.global_uniform_buffer.loadData(offset, range, .{}, &std.mem.toBytes(self.global_uniform_data));

    const global_ubo_buffer_info = vk.DescriptorBufferInfo{
        .buffer = self.global_uniform_buffer.handle,
        .offset = offset,
        .range = range,
    };

    const global_ubo_descriptor_write = vk.WriteDescriptorSet{
        .dst_set = global_descriptor_set,
        .dst_binding = 0,
        .dst_array_element = 0,
        .descriptor_type = .uniform_buffer,
        .descriptor_count = 1,
        .p_buffer_info = @ptrCast(&global_ubo_buffer_info),
        .p_image_info = undefined,
        .p_texel_buffer_view = undefined,
    };

    self.context.device_api.updateDescriptorSets(
        self.context.device,
        1,
        @ptrCast(&global_ubo_descriptor_write),
        0,
        null,
    );

    self.context.device_api.cmdBindDescriptorSets(
        command_buffer.handle,
        self.bind_point,
        self.pipeline_layout,
        0,
        1,
        @ptrCast(&global_descriptor_set),
        0,
        null,
    );
}

pub fn setModel(self: *Shader, model: math.Mat) void {
    const command_buffer = self.context.getCurrentCommandBuffer();

    self.context.device_api.cmdPushConstants(
        command_buffer.handle,
        self.pipeline_layout,
        .{ .vertex_bit = true },
        0,
        @sizeOf(math.Mat),
        @ptrCast(&model),
    );
}

pub fn applyMaterial(self: *Shader, material: MaterialHandle) !void {
    const image_index = self.context.swapchain.image_index;
    const command_buffer = self.context.getCurrentCommandBuffer();

    // if the material hasn't been loaded yet, use the default
    const material_handle = if (Engine.instance.material_system.materials.isLiveHandle(material)) //
        material
    else
        Engine.instance.material_system.getDefaultMaterial();

    const p_material = Engine.instance.material_system.materials.getColumnPtrAssumeLive(material_handle, .material);

    const p_material_state = &self.instance_states[p_material.internal_id.?];
    const material_descriptor_set = p_material_state.descriptor_sets.slice()[image_index];

    var descriptor_writes: [descriptor_count]vk.WriteDescriptorSet = undefined;
    var write_count: u32 = 0;
    var dst_binding: u32 = 0;

    // descriptor 0 - uniform buffer
    const descriptor_material_generation = &p_material_state.descriptor_states[dst_binding].generations.slice()[image_index];
    if (descriptor_material_generation.* == null or descriptor_material_generation.* != p_material.generation) {
        const range: u32 = @sizeOf(InstanceUniformData);
        const offset: vk.DeviceSize = @sizeOf(InstanceUniformData) * p_material.internal_id.?;

        const instance_uniform_data = InstanceUniformData{
            .diffuse_color = p_material.diffuse_color,
        };

        try self.material_uniform_buffer.loadData(offset, range, .{}, &std.mem.toBytes(instance_uniform_data));

        descriptor_writes[write_count] = vk.WriteDescriptorSet{
            .dst_set = material_descriptor_set,
            .dst_binding = dst_binding,
            .dst_array_element = 0,
            .descriptor_type = .uniform_buffer,
            .descriptor_count = 1,
            .p_buffer_info = @ptrCast(&vk.DescriptorBufferInfo{
                .buffer = self.material_uniform_buffer.handle,
                .offset = offset,
                .range = range,
            }),
            .p_image_info = undefined,
            .p_texel_buffer_view = undefined,
        };
        write_count += 1;

        descriptor_material_generation.* = p_material.generation;
    }
    dst_binding += 1;

    for (0..sampler_count) |sampler_index| {
        const descriptor_texture_handle = &p_material_state.descriptor_states[dst_binding].handles.slice()[image_index];
        const descriptor_texture_generation = &p_material_state.descriptor_states[dst_binding].generations.slice()[image_index];

        var texture_handle = switch (self.sampler_uses[sampler_index]) {
            .map_diffuse => p_material.diffuse_map.texture,
            else => return error.UnableToBindSamplerToUnknownUse,
        };

        // if the texture hasn't been loaded yet, use the default
        if (!Engine.instance.texture_system.textures.isLiveHandle(texture_handle)) {
            texture_handle = Engine.instance.texture_system.getDefaultTexture();
            descriptor_texture_generation.* = null; // reset if using the default
        }

        const texture = Engine.instance.texture_system.textures.getColumnPtrAssumeLive(texture_handle, .texture);

        if (descriptor_texture_handle.*.id != texture_handle.id // different texture
        or descriptor_texture_generation.* == null // default texture
        or descriptor_texture_generation.* != texture.generation // texture generation changed
        ) {
            const internal_data: *TextureData = @ptrCast(@alignCast(texture.internal_data));

            descriptor_writes[write_count] = vk.WriteDescriptorSet{
                .dst_set = material_descriptor_set,
                .dst_binding = dst_binding,
                .descriptor_type = .combined_image_sampler,
                .descriptor_count = 1,
                .dst_array_element = 0,
                .p_image_info = @ptrCast(&vk.DescriptorImageInfo{
                    .image_layout = .shader_read_only_optimal,
                    .image_view = internal_data.image.view,
                    .sampler = internal_data.sampler,
                }),
                .p_buffer_info = undefined,
                .p_texel_buffer_view = undefined,
            };
            write_count += 1;

            // NOTE: sync frame generation if not using a default texture
            if (texture.generation != null) {
                descriptor_texture_generation.* = texture.generation;
                descriptor_texture_handle.* = texture_handle;
            }
            dst_binding += 1;
        }
    }

    if (write_count > 0) {
        self.context.device_api.updateDescriptorSets(
            self.context.device,
            write_count,
            &descriptor_writes,
            0,
            null,
        );
    }

    self.context.device_api.cmdBindDescriptorSets(
        command_buffer.handle,
        self.bind_point,
        self.pipeline_layout,
        1,
        1,
        @ptrCast(&material_descriptor_set),
        0,
        null,
    );
}

pub fn acquireResources(self: *Shader, material: *Material) !void {
    material.internal_id = self.material_uniform_buffer_index;

    // TODO: wrapping this id is not ok. turn this into a proper pool
    self.material_uniform_buffer_index = if (self.material_uniform_buffer_index) |g| g +% 1 else 0;

    var instance_state = &self.instance_states[material.internal_id.?];

    // allocate descriptor sets
    var material_ubo_layouts: [config.max_swapchain_image_count]vk.DescriptorSetLayout = undefined;
    for (0..self.context.swapchain.images.len) |i| {
        material_ubo_layouts[i] = self.material_descriptor_set_layout;
    }

    const material_ubo_descriptor_set_alloc_info = vk.DescriptorSetAllocateInfo{
        .descriptor_pool = self.material_descriptor_pool,
        .descriptor_set_count = self.context.swapchain.images.len,
        .p_set_layouts = &material_ubo_layouts,
    };

    instance_state.descriptor_sets.len = self.context.swapchain.images.len;
    try self.context.device_api.allocateDescriptorSets(
        self.context.device,
        &material_ubo_descriptor_set_alloc_info,
        instance_state.descriptor_sets.slice().ptr,
    );

    // clear descriptor states
    for (&instance_state.descriptor_states) |*descriptor_state| {
        descriptor_state.generations.len = 0;
        descriptor_state.handles.len = 0;

        for (0..self.context.swapchain.images.len) |_| {
            descriptor_state.generations.appendAssumeCapacity(null);
            descriptor_state.handles.appendAssumeCapacity(TextureHandle.nil);
        }
    }
}

pub fn releaseResources(self: *Shader, material: *Material) void {
    const instance_state = &self.instance_states[material.internal_id.?];

    self.context.device_api.deviceWaitIdle(self.context.device) catch {
        std.log.err("Could not free descriptor set for material: {s}", .{material.name.slice()});
    };

    self.context.device_api.freeDescriptorSets(
        self.context.device,
        self.material_descriptor_pool,
        self.context.swapchain.images.len,
        instance_state.descriptor_sets.slice().ptr,
    ) catch {
        std.log.err("Could not free descriptor set for material: {s}", .{material.name.slice()});
    };
    instance_state.descriptor_sets.len = 0;

    // clear descriptor states
    for (&instance_state.descriptor_states) |*descriptor_state| {
        descriptor_state.generations.len = 0;
        descriptor_state.handles.len = 0;

        for (0..self.context.swapchain.images.len) |_| {
            descriptor_state.generations.appendAssumeCapacity(null);
            descriptor_state.handles.appendAssumeCapacity(TextureHandle.nil);
        }
    }

    material.internal_id = null;
}

// utils
fn createShaderModule(self: *const Shader, allocator: Allocator, path: []const u8) !vk.ShaderModule {
    var binary_resource = try BinaryResource.init(allocator, path);
    defer binary_resource.deinit();

    return try self.context.device_api.createShaderModule(
        self.context.device,
        &vk.ShaderModuleCreateInfo{
            .flags = .{},
            .code_size = binary_resource.bytes.len,
            .p_code = @ptrCast(@alignCast(binary_resource.bytes.ptr)),
        },
        null,
    );
}
