const std = @import("std");
const vk = @import("vk.zig");
const Context = @import("context.zig").Context;
const Vertex = @import("context.zig").Vertex;
const Buffer = @import("buffer.zig").Buffer;
const CommandBuffer = @import("command_buffer.zig").CommandBuffer;
const GlobalUniformData = @import("../types.zig").GlobalUniformData;
const Allocator = std.mem.Allocator;
const zm = @import("zmath");

pub const Shader = struct {
    const Self = @This();

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

    // public
    pub fn init(
        allocator: Allocator,
        context: *const Context,
        name: []const u8,
        bind_point: vk.PipelineBindPoint,
    ) !Self {
        var self: Self = undefined;
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
        const global_ubo_layout_binding = vk.DescriptorSetLayoutBinding{
            .binding = 0,
            .descriptor_count = 1,
            .descriptor_type = .uniform_buffer,
            .p_immutable_samplers = null,
            .stage_flags = .{ .vertex_bit = true },
        };

        const global_ubo_layout_info = vk.DescriptorSetLayoutCreateInfo{
            .binding_count = 1,
            .p_bindings = @ptrCast(&global_ubo_layout_binding),
        };

        self.global_descriptor_set_layout = try context.device_api.createDescriptorSetLayout(
            context.device,
            &global_ubo_layout_info,
            null,
        );
        // TODO: errdefer

        const global_ubo_pool_size = vk.DescriptorPoolSize{
            .type = .uniform_buffer,
            .descriptor_count = @intCast(context.swapchain.images.len),
        };

        const global_ubo_pool_info = vk.DescriptorPoolCreateInfo{
            .flags = .{},
            .pool_size_count = 1,
            .p_pool_sizes = @ptrCast(&global_ubo_pool_size),
            .max_sets = @intCast(context.swapchain.images.len),
        };

        self.global_descriptor_pool = try context.device_api.createDescriptorPool(
            context.device,
            &global_ubo_pool_info,
            null,
        );
        // TODO: errdefer

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
        };

        const push_constant_range = vk.PushConstantRange{
            .stage_flags = .{ .vertex_bit = true },
            .offset = @sizeOf(zm.Mat) * 0,
            .size = @sizeOf(zm.Mat) * 2,
        };

        self.pipeline_layout = try self.context.device_api.createPipelineLayout(self.context.device, &.{
            .flags = .{},
            .set_layout_count = layouts.len,
            .p_set_layouts = &layouts,
            .push_constant_range_count = 1,
            .p_push_constant_ranges = @ptrCast(&push_constant_range),
        }, null);
        errdefer self.context.device_api.destroyPipelineLayout(self.context.device, self.pipeline_layout, null);

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
            .render_pass = self.context.main_render_pass.handle,
            .subpass = 0,
            .base_pipeline_handle = .null_handle,
            .base_pipeline_index = -1,
        };

        _ = try self.context.device_api.createGraphicsPipelines(
            self.context.device,
            .null_handle,
            1,
            @ptrCast(&pipeline_create_info),
            null,
            @ptrCast(&self.pipeline),
        );

        self.global_uniform_buffer = try Buffer.init(
            context,
            .{ .transfer_dst_bit = true, .uniform_buffer_bit = true },
            @sizeOf(GlobalUniformData) * 3,
            .{ .device_local_bit = true, .host_visible_bit = true, .host_coherent_bit = true },
            .{ .bind_on_create = true },
        );
        // TODO: errdefer

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

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.global_uniform_buffer.deinit();

        self.context.device_api.destroyPipeline(self.context.device, self.pipeline, null);
        self.context.device_api.destroyPipelineLayout(self.context.device, self.pipeline_layout, null);

        self.context.device_api.destroyDescriptorPool(self.context.device, self.global_descriptor_pool, null);
        self.context.device_api.destroyDescriptorSetLayout(self.context.device, self.global_descriptor_set_layout, null);

        self.context.device_api.destroyShaderModule(self.context.device, self.fragment_shader_module, null);
        self.context.device_api.destroyShaderModule(self.context.device, self.vertex_shader_module, null);
    }

    pub fn bind(self: Self, command_buffer: *const CommandBuffer) void {
        self.context.device_api.cmdBindPipeline(command_buffer.handle, self.bind_point, self.pipeline);
    }

    pub fn updateGlobalUniformData(self: *Self) !void {
        const image_index = self.context.swapchain.image_index;
        const command_buffer = self.context.getCurrentCommandBuffer();
        const global_descriptor = self.global_descriptor_sets[image_index];

        const range: u32 = @sizeOf(GlobalUniformData);
        const offset: vk.DeviceSize = @sizeOf(GlobalUniformData) * image_index;

        try self.global_uniform_buffer.loadData(offset, range, .{}, &std.mem.toBytes(self.global_uniform_data));

        const global_ubo_buffer_info = vk.DescriptorBufferInfo{
            .buffer = self.global_uniform_buffer.handle,
            .offset = offset,
            .range = range,
        };

        const global_ubo_descriptor_write = vk.WriteDescriptorSet{
            .dst_set = global_descriptor,
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
            @ptrCast(&global_descriptor),
            0,
            null,
        );
    }

    pub fn updateObjectUniformData(self: *Self, model: zm.Mat) void {
        const command_buffer = self.context.getCurrentCommandBuffer();

        self.context.device_api.cmdPushConstants(
            command_buffer.handle,
            self.pipeline_layout,
            .{ .vertex_bit = true },
            0,
            @sizeOf(zm.Mat),
            @ptrCast(&model),
        );
    }

    // utils
    fn createShaderModule(self: Self, path: []const u8) !vk.ShaderModule {
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
