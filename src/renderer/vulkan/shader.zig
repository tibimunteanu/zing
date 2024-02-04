const std = @import("std");
const vk = @import("vk.zig");
const Context = @import("context.zig").Context;
const Vertex = @import("context.zig").Vertex;
const Buffer = @import("buffer.zig").Buffer;
const CommandBuffer = @import("command_buffer.zig").CommandBuffer;
const GlobalUniformData = @import("../types.zig").GlobalUniformData;
const ObjectUniformData = @import("../types.zig").ObjectUniformData;
const GeometryRenderData = @import("../types.zig").GeometryRenderData;
const ObjectShaderObjectState = @import("vulkan_types.zig").ObjectShaderObjectState;
const TextureData = @import("vulkan_types.zig").TextureData;
const ID = @import("../../utils.zig").ID;
const Allocator = std.mem.Allocator;
const zm = @import("zmath");

const max_object_count = @import("vulkan_types.zig").max_object_count;
const object_shader_descriptor_count = @import("vulkan_types.zig").object_shader_descriptor_count;
var accumulator: f32 = 0.0;

pub const Shader = struct {
    context: *const Context,
    allocator: Allocator,

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

    object_descriptor_pool: vk.DescriptorPool,
    object_descriptor_set_layout: vk.DescriptorSetLayout,
    object_uniform_buffer: Buffer,
    object_uniform_buffer_index: ID,
    object_states: [max_object_count]ObjectShaderObjectState,

    // public
    pub fn init(
        allocator: Allocator,
        context: *const Context,
        name: []const u8,
        bind_point: vk.PipelineBindPoint,
    ) !Shader {
        var self: Shader = undefined;
        self.context = context;
        self.allocator = allocator;

        self.bind_point = bind_point;

        const base_path = "assets/shaders";

        const vert_path = try std.fmt.allocPrint(allocator, "{s}/{s}_vert.spv", .{ base_path, name });
        defer allocator.free(vert_path);

        self.vertex_shader_module = try createShaderModule(self, vert_path);
        errdefer context.device_api.destroyShaderModule(context.device, self.vertex_shader_module, null);

        const frag_path = try std.fmt.allocPrint(allocator, "{s}/{s}_frag.spv", .{ base_path, name });
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

        // local / object descriptors
        const local_sampler_count: u32 = 1;
        const descriptor_types = [object_shader_descriptor_count]vk.DescriptorType{
            .uniform_buffer,
            .combined_image_sampler,
        };

        var object_ubo_layout_bindings: [descriptor_types.len]vk.DescriptorSetLayoutBinding = undefined;
        for (&object_ubo_layout_bindings, descriptor_types, 0..) |*binding, descriptor_type, i| {
            binding.* = vk.DescriptorSetLayoutBinding{
                .binding = @intCast(i),
                .descriptor_count = 1,
                .descriptor_type = descriptor_type,
                .p_immutable_samplers = null,
                .stage_flags = .{ .fragment_bit = true },
            };
        }

        self.object_descriptor_set_layout = try context.device_api.createDescriptorSetLayout(
            context.device,
            &vk.DescriptorSetLayoutCreateInfo{
                .binding_count = object_ubo_layout_bindings.len,
                .p_bindings = @ptrCast(&object_ubo_layout_bindings),
            },
            null,
        );
        errdefer context.device_api.destroyDescriptorSetLayout(context.device, self.object_descriptor_set_layout, null);

        const object_ubo_pool_sizes = [_]vk.DescriptorPoolSize{
            vk.DescriptorPoolSize{
                .type = .uniform_buffer,
                .descriptor_count = @intCast(max_object_count),
            },
            vk.DescriptorPoolSize{
                .type = .combined_image_sampler,
                .descriptor_count = local_sampler_count * @as(u32, @intCast(max_object_count)),
            },
        };

        self.object_descriptor_pool = try context.device_api.createDescriptorPool(
            context.device,
            &vk.DescriptorPoolCreateInfo{
                .flags = .{},
                .pool_size_count = object_ubo_pool_sizes.len,
                .p_pool_sizes = &object_ubo_pool_sizes,
                .max_sets = @intCast(max_object_count),
            },
            null,
        );
        errdefer context.device_api.destroyDescriptorPool(context.device, self.object_descriptor_pool, null);

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
            self.object_descriptor_set_layout,
        };

        const push_constant_range = vk.PushConstantRange{
            .stage_flags = .{ .vertex_bit = true },
            .offset = @sizeOf(zm.Mat) * 0,
            .size = @sizeOf(zm.Mat) * 2,
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
            .{ .device_local_bit = true, .host_visible_bit = true, .host_coherent_bit = true },
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

        self.object_uniform_buffer = try Buffer.init(
            context,
            @sizeOf(ObjectUniformData) * max_object_count * 3,
            .{ .transfer_dst_bit = true, .uniform_buffer_bit = true },
            .{ .device_local_bit = true, .host_visible_bit = true, .host_coherent_bit = true },
            .{ .bind_on_create = true },
        );
        errdefer self.object_uniform_buffer.deinit();

        self.object_uniform_buffer_index = @enumFromInt(0);

        return self;
    }

    pub fn deinit(self: *Shader) void {
        self.object_uniform_buffer.deinit();
        self.global_uniform_buffer.deinit();

        self.context.device_api.destroyPipeline(self.context.device, self.pipeline, null);
        self.context.device_api.destroyPipelineLayout(self.context.device, self.pipeline_layout, null);

        self.context.device_api.destroyDescriptorPool(self.context.device, self.object_descriptor_pool, null);
        self.context.device_api.destroyDescriptorSetLayout(self.context.device, self.object_descriptor_set_layout, null);

        self.context.device_api.destroyDescriptorPool(self.context.device, self.global_descriptor_pool, null);
        self.context.device_api.destroyDescriptorSetLayout(self.context.device, self.global_descriptor_set_layout, null);

        self.context.device_api.destroyShaderModule(self.context.device, self.fragment_shader_module, null);
        self.context.device_api.destroyShaderModule(self.context.device, self.vertex_shader_module, null);
    }

    pub fn bind(self: Shader, command_buffer: *const CommandBuffer) void {
        self.context.device_api.cmdBindPipeline(command_buffer.handle, self.bind_point, self.pipeline);
    }

    pub fn updateGlobalUniformData(self: *Shader) !void {
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

    pub fn updateObjectUniformData(self: *Shader, data: GeometryRenderData) !void {
        const image_index = self.context.swapchain.image_index;
        const command_buffer = self.context.getCurrentCommandBuffer();

        self.context.device_api.cmdPushConstants(
            command_buffer.handle,
            self.pipeline_layout,
            .{ .vertex_bit = true },
            0,
            @sizeOf(zm.Mat),
            @ptrCast(&data.model),
        );

        // obtain material data
        const object_state = &self.object_states[@intFromEnum(data.object_id)];
        const object_descriptor_set = object_state.descriptor_sets[image_index];

        var descriptor_writes: [object_shader_descriptor_count]vk.WriteDescriptorSet = undefined;
        var write_count: u32 = 0;
        var dst_binding: u32 = 0;

        // descriptor 0 - uniform buffer
        const range: u32 = @sizeOf(ObjectUniformData);
        const offset: vk.DeviceSize = @sizeOf(ObjectUniformData) * @intFromEnum(data.object_id);

        accumulator += self.context.delta_time;
        const s: f32 = (@sin(accumulator) + 1.0) * 0.5;

        const object_uniform_data = ObjectUniformData{
            .diffuse_color = zm.Vec{ s, s, s, 1.0 },
        };

        try self.object_uniform_buffer.loadData(offset, range, .{}, &std.mem.toBytes(object_uniform_data));

        // only do this if the descriptor has not yet been updated
        if (object_state.descriptor_states[dst_binding].generations[image_index] == .null_handle) {
            const object_ubo_buffer_info = vk.DescriptorBufferInfo{
                .buffer = self.object_uniform_buffer.handle,
                .offset = offset,
                .range = range,
            };

            const object_ubo_descriptor_write = vk.WriteDescriptorSet{
                .dst_set = object_descriptor_set,
                .dst_binding = dst_binding,
                .dst_array_element = 0,
                .descriptor_type = .uniform_buffer,
                .descriptor_count = 1,
                .p_buffer_info = @ptrCast(&object_ubo_buffer_info),
                .p_image_info = undefined,
                .p_texel_buffer_view = undefined,
            };

            descriptor_writes[write_count] = object_ubo_descriptor_write;
            write_count += 1;

            object_state.descriptor_states[dst_binding].generations[image_index] = @enumFromInt(1);
        }
        dst_binding += 1;

        const sampler_count: u32 = 1;
        var image_infos: [sampler_count]vk.DescriptorImageInfo = undefined;
        for (&image_infos, 0..sampler_count) |*image_info, sampler_index| {
            const texture = data.textures[sampler_index];
            const generation = &object_state.descriptor_states[dst_binding].generations[image_index];

            if (texture != null and (generation.* != texture.?.generation or generation.* == .null_handle)) {
                const internal_data: *TextureData = @ptrCast(texture.?.internal_data);

                image_info.* = vk.DescriptorImageInfo{
                    .image_layout = .shader_read_only_optimal,
                    .image_view = internal_data.image.view,
                    .sampler = internal_data.sampler,
                };

                const object_sampler_descriptor_write = vk.WriteDescriptorSet{
                    .dst_set = object_descriptor_set,
                    .dst_binding = dst_binding,
                    .descriptor_type = .combined_image_sampler,
                    .descriptor_count = 1,
                    .dst_array_element = 0,
                    .p_image_info = @ptrCast(image_info),
                    .p_buffer_info = undefined,
                    .p_texel_buffer_view = undefined,
                };

                descriptor_writes[write_count] = object_sampler_descriptor_write;
                write_count += 1;

                if (texture.?.generation != .null_handle) {
                    generation.* = texture.?.generation;
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
            @ptrCast(&object_descriptor_set),
            0,
            null,
        );
    }

    pub fn acquireResources(self: *Shader) !ID {
        const object_id = self.object_uniform_buffer_index;
        self.object_uniform_buffer_index.increment();

        var object_state = &self.object_states[@intFromEnum(object_id)];

        for (&object_state.descriptor_states) |*descriptor_state| {
            for (0..3) |i| {
                descriptor_state.generations[i] = .null_handle;
            }
        }

        // allocate descriptor sets
        const object_ubo_layouts = [_]vk.DescriptorSetLayout{
            self.object_descriptor_set_layout,
            self.object_descriptor_set_layout,
            self.object_descriptor_set_layout,
        };

        const object_ubo_descriptor_set_alloc_info = vk.DescriptorSetAllocateInfo{
            .descriptor_pool = self.object_descriptor_pool,
            .descriptor_set_count = 3,
            .p_set_layouts = &object_ubo_layouts,
        };

        try self.context.device_api.allocateDescriptorSets(
            self.context.device,
            &object_ubo_descriptor_set_alloc_info,
            &object_state.descriptor_sets,
        );

        return object_id;
    }

    pub fn releaseResources(self: *Shader, object_id: ID) void {
        const object_state = &self.object_states[object_id];

        try self.context.device_api.freeDescriptorSets(
            self.context.device,
            self.object_descriptor_pool,
            3,
            &object_state.descriptor_sets,
        );

        for (object_state.descriptor_states) |*descriptor_state| {
            for (0..3) |i| {
                descriptor_state.generations[i] = .null_handle;
            }
        }
    }

    // utils
    fn createShaderModule(self: Shader, path: []const u8) !vk.ShaderModule {
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
