const std = @import("std");
const vk = @import("vk.zig");
const math = @import("zmath");

const Engine = @import("../../engine.zig").Engine;
const Buffer = @import("buffer.zig").Buffer;
const CommandBuffer = @import("command_buffer.zig").CommandBuffer;
const TextureHandle = @import("../../systems/texture_system.zig").TextureHandle;

const renderer_types = @import("../types.zig");
const renderer_context = @import("context.zig");
const vulkan_types = @import("vulkan_types.zig");
const resources_material = @import("../../resources/material.zig");
const resources_texture = @import("../../resources/texture.zig");

const Context = renderer_context.Context;
const Vertex = renderer_context.Vertex;
const GlobalUniformData = renderer_types.GlobalUniformData;
const MaterialUniformData = renderer_types.MaterialUniformData;
const GeometryRenderData = renderer_types.GeometryRenderData;
const MaterialShaderInstanceState = vulkan_types.MaterialShaderInstanceState;
const TextureData = vulkan_types.TextureData;
const TextureUse = resources_texture.TextureUse;
const Material = resources_material.Material;
const Allocator = std.mem.Allocator;

const material_shader_descriptor_count = vulkan_types.material_shader_descriptor_count;
const material_shader_sampler_count = vulkan_types.material_shader_sampler_count;
const max_material_count = vulkan_types.max_material_count;

const shader_path_format = "assets/shaders/{s}.{s}.spv";
const material_shader_name = "material_shader";

pub const MaterialShader = struct {
    context: *const Context,
    allocator: Allocator, // TODO: replace this with a scratch arena

    vertex_shader_module: vk.ShaderModule,
    fragment_shader_module: vk.ShaderModule,

    pipeline: vk.Pipeline,
    pipeline_layout: vk.PipelineLayout,
    bind_point: vk.PipelineBindPoint,

    global_uniform_data: GlobalUniformData,
    global_descriptor_pool: vk.DescriptorPool,
    global_descriptor_set_layout: vk.DescriptorSetLayout,
    global_descriptor_sets: [3]vk.DescriptorSet,
    global_uniform_buffer: Buffer,

    material_descriptor_pool: vk.DescriptorPool,
    material_descriptor_set_layout: vk.DescriptorSetLayout,
    material_uniform_buffer: Buffer,
    material_uniform_buffer_index: ?u32,

    instance_states: [max_material_count]MaterialShaderInstanceState,

    sampler_uses: [material_shader_sampler_count]TextureUse,

    // public
    pub fn init(
        allocator: Allocator,
        context: *const Context,
    ) !MaterialShader {
        var self: MaterialShader = undefined;
        self.context = context;
        self.allocator = allocator;
        self.bind_point = .graphics;

        const vert_path = try std.fmt.allocPrint(allocator, shader_path_format, .{ material_shader_name, "vert" });
        defer allocator.free(vert_path);

        self.vertex_shader_module = try createShaderModule(self, vert_path);
        errdefer context.device_api.destroyShaderModule(context.device, self.vertex_shader_module, null);

        const frag_path = try std.fmt.allocPrint(allocator, shader_path_format, .{ material_shader_name, "frag" });
        defer allocator.free(frag_path);

        self.fragment_shader_module = try createShaderModule(self, frag_path);
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
        const descriptor_types = [material_shader_descriptor_count]vk.DescriptorType{
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
                .descriptor_count = @intCast(max_material_count),
            },
            vk.DescriptorPoolSize{
                .type = .combined_image_sampler,
                .descriptor_count = material_shader_sampler_count * @as(u32, @intCast(max_material_count)),
            },
        };

        self.material_descriptor_pool = try context.device_api.createDescriptorPool(
            context.device,
            &vk.DescriptorPoolCreateInfo{
                .flags = .{ .free_descriptor_set_bit = true },
                .pool_size_count = material_ubo_pool_sizes.len,
                .p_pool_sizes = &material_ubo_pool_sizes,
                .max_sets = @intCast(max_material_count),
            },
            null,
        );
        errdefer context.device_api.destroyDescriptorPool(context.device, self.material_descriptor_pool, null);

        const viewport_state = vk.PipelineViewportStateCreateInfo{
            .flags = .{},
            .viewport_count = 1,
            .p_viewports = undefined,
            .scissor_count = 1,
            .p_scissors = undefined,
        };

        const vertex_input_state = vk.PipelineVertexInputStateCreateInfo{
            .flags = .{},
            .vertex_binding_description_count = 1,
            .p_vertex_binding_descriptions = @ptrCast(&Vertex.binding_description),
            .vertex_attribute_description_count = Vertex.attribute_description.len,
            .p_vertex_attribute_descriptions = &Vertex.attribute_description,
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

        const dynamic_state_props = [_]vk.DynamicState{ .viewport, .scissor, .line_width };
        const dynamic_state = vk.PipelineDynamicStateCreateInfo{
            .flags = .{},
            .dynamic_state_count = dynamic_state_props.len,
            .p_dynamic_states = &dynamic_state_props,
        };

        // descriptor set layouts
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
            .p_depth_stencil_state = &depth_stencil_state,
            .p_color_blend_state = &color_blend_state,
            .p_dynamic_state = &dynamic_state,
            .layout = self.pipeline_layout,
            .render_pass = context.main_render_pass.handle,
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
            @sizeOf(GlobalUniformData) * 3,
            .{ .transfer_dst_bit = true, .uniform_buffer_bit = true },
            .{
                .device_local_bit = self.context.physical_device.supports_local_host_visible,
                .host_visible_bit = true,
                .host_coherent_bit = true,
            },
            .{ .bind_on_create = true },
        );
        errdefer self.global_uniform_buffer.deinit();

        const global_ubo_layouts = [_]vk.DescriptorSetLayout{
            self.global_descriptor_set_layout,
            self.global_descriptor_set_layout,
            self.global_descriptor_set_layout,
        };

        const global_ubo_descriptor_set_alloc_info = vk.DescriptorSetAllocateInfo{
            .descriptor_pool = self.global_descriptor_pool,
            .descriptor_set_count = 3,
            .p_set_layouts = &global_ubo_layouts,
        };

        try context.device_api.allocateDescriptorSets(
            context.device,
            &global_ubo_descriptor_set_alloc_info,
            &self.global_descriptor_sets,
        );

        self.material_uniform_buffer = try Buffer.init(
            context,
            @sizeOf(MaterialUniformData) * max_material_count * 3, // TODO: the * 3 may not be needed. think about it
            .{ .transfer_dst_bit = true, .uniform_buffer_bit = true },
            .{
                .device_local_bit = self.context.physical_device.supports_local_host_visible,
                .host_visible_bit = true,
                .host_coherent_bit = true,
            },
            .{ .bind_on_create = true },
        );
        errdefer self.material_uniform_buffer.deinit();

        self.material_uniform_buffer_index = 0;

        return self;
    }

    pub fn deinit(self: *MaterialShader) void {
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

    pub fn bind(self: MaterialShader, command_buffer: *const CommandBuffer) void {
        self.context.device_api.cmdBindPipeline(command_buffer.handle, self.bind_point, self.pipeline);
    }

    pub fn updateGlobalUniformData(self: *MaterialShader) !void {
        const image_index = self.context.swapchain.image_index;
        const command_buffer = self.context.getCurrentCommandBuffer();
        const global_descriptor_set = self.global_descriptor_sets[image_index];

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

    pub fn updateMaterialUniformData(self: *MaterialShader, data: GeometryRenderData) !void {
        const image_index = self.context.swapchain.image_index;
        const command_buffer = self.context.getCurrentCommandBuffer();

        self.context.device_api.cmdPushConstants(
            command_buffer.handle,
            self.pipeline_layout,
            .{ .vertex_bit = true },
            0,
            @sizeOf(math.Mat),
            @ptrCast(&data.model),
        );

        // obtain material data
        // if the material hasn't been loaded yet, use the default
        var materialHandle = data.material;
        if (!Engine.instance.material_system.materials.isLiveHandle(data.material)) {
            materialHandle = Engine.instance.material_system.getDefaultMaterial();
        }

        const material = Engine.instance.material_system.materials.getColumnPtrAssumeLive(materialHandle, .material);

        const material_state = &self.instance_states[material.internal_id.?];
        const material_descriptor_set = material_state.descriptor_sets[image_index];

        var descriptor_writes: [material_shader_descriptor_count]vk.WriteDescriptorSet = undefined;
        var write_count: u32 = 0;
        var dst_binding: u32 = 0;

        // descriptor 0 - uniform buffer
        const range: u32 = @sizeOf(MaterialUniformData);
        const offset: vk.DeviceSize = @sizeOf(MaterialUniformData) * material.internal_id.?;

        const material_uniform_data = MaterialUniformData{
            .diffuse_color = material.diffuse_color,
        };

        try self.material_uniform_buffer.loadData(offset, range, .{}, &std.mem.toBytes(material_uniform_data));

        // only do this if the descriptor has not yet been updated
        const material_ubo_generation = &material_state.descriptor_states[dst_binding].generations[image_index];
        if (material_ubo_generation.* == null or material_ubo_generation.* != material.generation) {
            const material_ubo_buffer_info = vk.DescriptorBufferInfo{
                .buffer = self.material_uniform_buffer.handle,
                .offset = offset,
                .range = range,
            };

            const material_ubo_descriptor_write = vk.WriteDescriptorSet{
                .dst_set = material_descriptor_set,
                .dst_binding = dst_binding,
                .dst_array_element = 0,
                .descriptor_type = .uniform_buffer,
                .descriptor_count = 1,
                .p_buffer_info = @ptrCast(&material_ubo_buffer_info),
                .p_image_info = undefined,
                .p_texel_buffer_view = undefined,
            };

            descriptor_writes[write_count] = material_ubo_descriptor_write;
            write_count += 1;

            material_ubo_generation.* = material.generation;
        }
        dst_binding += 1;

        const sampler_count: u32 = 1;
        var image_infos: [sampler_count]vk.DescriptorImageInfo = undefined;

        for (&image_infos, 0..sampler_count) |*image_info, sampler_index| {
            const descriptorTextureHandle = &material_state.descriptor_states[dst_binding].handles[image_index];
            const descriptorTextureGeneration = &material_state.descriptor_states[dst_binding].generations[image_index];

            const use = self.sampler_uses[sampler_index];
            var textureHandle = TextureHandle.nil;
            switch (use) {
                .map_diffuse => textureHandle = material.diffuse_map.texture,
                else => return error.UnableToBindSamplerToUnknownUse,
            }
            // if the texture hasn't been loaded yet, use the default
            if (!Engine.instance.texture_system.textures.isLiveHandle(textureHandle)) {
                textureHandle = Engine.instance.texture_system.getDefaultTexture();
                descriptorTextureGeneration.* = null; // reset if using the default
            }

            const texture = Engine.instance.texture_system.textures.getColumnPtrAssumeLive(textureHandle, .texture);

            if (descriptorTextureHandle.*.id != textureHandle.id // different texture
            or descriptorTextureGeneration.* == null // default texture
            or descriptorTextureGeneration.* != texture.generation // texture generation changed
            ) {
                const internal_data: *TextureData = @ptrCast(@alignCast(texture.internal_data));

                image_info.* = vk.DescriptorImageInfo{
                    .image_layout = .shader_read_only_optimal,
                    .image_view = internal_data.image.view,
                    .sampler = internal_data.sampler,
                };

                const material_sampler_descriptor_write = vk.WriteDescriptorSet{
                    .dst_set = material_descriptor_set,
                    .dst_binding = dst_binding,
                    .descriptor_type = .combined_image_sampler,
                    .descriptor_count = 1,
                    .dst_array_element = 0,
                    .p_image_info = @ptrCast(image_info),
                    .p_buffer_info = undefined,
                    .p_texel_buffer_view = undefined,
                };

                descriptor_writes[write_count] = material_sampler_descriptor_write;
                write_count += 1;

                // NOTE: sync frame generation if not using a default texture
                if (texture.generation != null) {
                    descriptorTextureGeneration.* = texture.generation;
                    descriptorTextureHandle.* = textureHandle;
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

    pub fn acquireResources(self: *MaterialShader, material: *Material) !void {
        material.internal_id = self.material_uniform_buffer_index;
        self.material_uniform_buffer_index = if (self.material_uniform_buffer_index) |g| g +% 1 else 0;

        var instance_state = &self.instance_states[material.internal_id.?];

        for (&instance_state.descriptor_states) |*descriptor_state| {
            for (0..3) |i| {
                descriptor_state.generations[i] = null;
                descriptor_state.handles[i] = TextureHandle.nil;
            }
        }

        // allocate descriptor sets
        const material_ubo_layouts = [_]vk.DescriptorSetLayout{
            self.material_descriptor_set_layout,
            self.material_descriptor_set_layout,
            self.material_descriptor_set_layout,
        };

        const material_ubo_descriptor_set_alloc_info = vk.DescriptorSetAllocateInfo{
            .descriptor_pool = self.material_descriptor_pool,
            .descriptor_set_count = 3,
            .p_set_layouts = &material_ubo_layouts,
        };

        try self.context.device_api.allocateDescriptorSets(
            self.context.device,
            &material_ubo_descriptor_set_alloc_info,
            &instance_state.descriptor_sets,
        );
    }

    pub fn releaseResources(self: *MaterialShader, material: *Material) void {
        const instance_state = &self.instance_states[material.internal_id.?];

        self.context.device_api.freeDescriptorSets(
            self.context.device,
            self.material_descriptor_pool,
            3,
            &instance_state.descriptor_sets,
        ) catch unreachable;

        for (&instance_state.descriptor_states) |*descriptor_state| {
            for (0..3) |i| {
                descriptor_state.generations[i] = null;
                descriptor_state.handles[i] = TextureHandle.nil;
            }
        }

        material.internal_id = null;
    }

    // utils
    fn createShaderModule(self: MaterialShader, path: []const u8) !vk.ShaderModule {
        const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
        defer file.close();

        const stat = try file.stat();
        const content = try file.readToEndAlloc(self.allocator, stat.size);
        defer self.allocator.free(content);

        const module = try self.context.device_api.createShaderModule(
            self.context.device,
            &vk.ShaderModuleCreateInfo{
                .flags = .{},
                .code_size = content.len,
                .p_code = @ptrCast(@alignCast(content.ptr)),
            },
            null,
        );

        return module;
    }
};
