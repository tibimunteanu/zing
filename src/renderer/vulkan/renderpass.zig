const std = @import("std");
const vk = @import("vk.zig");
const Context = @import("context.zig").Context;
const CommandBuffer = @import("command_buffer.zig").CommandBuffer;
const Allocator = std.mem.Allocator;

pub const RenderPass = struct {
    pub const State = enum {
        invalid,
        initial,
        recording,
        executable,
        pending,
    };

    const RenderArea = union(enum) {
        fixed_area: vk.Rect2D,
        swapchain_area: void,
    };

    pub const ClearFlags = packed struct(u3) {
        color: bool = false,
        depth: bool = false,
        stencil: bool = false,
    };

    pub const ClearValues = struct {
        color: [4]f32,
        depth: f32,
        stencil: u32,
    };

    context: *const Context,
    handle: vk.RenderPass,
    state: State,
    render_area: RenderArea,
    clear_values: ClearValues,
    clear_flags: ClearFlags,
    has_prev: bool,
    has_next: bool,

    // public
    pub fn init(
        context: *const Context,
        render_area: RenderArea,
        clear_values: ClearValues,
        clear_flags: ClearFlags,
        has_prev: bool,
        has_next: bool,
    ) !RenderPass {
        var self: RenderPass = undefined;
        self.context = context;

        self.state = .invalid;

        self.render_area = render_area;
        self.clear_values = clear_values;
        self.clear_flags = clear_flags;
        self.has_prev = has_prev;
        self.has_next = has_next;

        const attachment_descriptions = [_]vk.AttachmentDescription{
            .{
                .format = context.swapchain.surface_format.format,
                .samples = .{ .@"1_bit" = true },
                .load_op = if (clear_flags.color) .clear else .load,
                .store_op = .store,
                .stencil_load_op = .dont_care,
                .stencil_store_op = .dont_care,
                .initial_layout = if (has_prev) .attachment_optimal else .undefined,
                .final_layout = if (has_next) .attachment_optimal else .present_src_khr,
            },
            .{
                .format = context.physical_device.depth_format,
                .samples = .{ .@"1_bit" = true },
                .load_op = if (clear_flags.depth) .clear else .load,
                .store_op = .dont_care,
                .stencil_load_op = .dont_care,
                .stencil_store_op = .dont_care,
                .initial_layout = .undefined,
                .final_layout = .depth_stencil_attachment_optimal,
            },
        };

        const subpass = vk.SubpassDescription{
            .pipeline_bind_point = .graphics,
            .color_attachment_count = 1,
            .p_color_attachments = &[_]vk.AttachmentReference{
                .{
                    .attachment = 0,
                    .layout = .color_attachment_optimal,
                },
            },
            .p_depth_stencil_attachment = if (clear_flags.depth) &.{
                .attachment = 1,
                .layout = .depth_stencil_attachment_optimal,
            } else null,
            .input_attachment_count = 0,
            .p_input_attachments = null,
            .preserve_attachment_count = 0,
            .p_preserve_attachments = null,
            .p_resolve_attachments = null,
        };

        const subpasses = [_]vk.SubpassDescription{subpass};

        const dependencies = [_]vk.SubpassDependency{
            .{
                .src_subpass = vk.SUBPASS_EXTERNAL,
                .dst_subpass = 0,
                .src_stage_mask = .{ .color_attachment_output_bit = true },
                .src_access_mask = .{},
                .dst_stage_mask = .{ .color_attachment_output_bit = true },
                .dst_access_mask = .{ .color_attachment_read_bit = true, .color_attachment_write_bit = true },
                .dependency_flags = .{},
            },
            // NOTE: Use an incoming subpass-dependency to ensure:
            // * Previous use of the depth-buffer is complete (execution dependency).
            // * WAW hazard is resolved (e.g. caches are flushed and invalidated so old and new writes are not re-ordered).
            // * Transition from UNDEFINED -> VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL happens-after previous `EARLY/LATE_FRAGMENT_TESTS` use.
            // * Changes made to the image by the transition are accounted for by setting the appropriate dstAccessMask.
            .{
                .src_subpass = vk.SUBPASS_EXTERNAL,
                .dst_subpass = 0,
                .src_stage_mask = .{ .late_fragment_tests_bit = true }, // store op is always performed in late tests
                .src_access_mask = .{ .depth_stencil_attachment_write_bit = true }, // after subpass access
                .dst_stage_mask = .{ .early_fragment_tests_bit = true }, // load op is always performed in early tests
                .dst_access_mask = .{ .depth_stencil_attachment_write_bit = true, .depth_stencil_attachment_read_bit = true }, // before subpass access
                .dependency_flags = .{},
            },
        };

        self.handle = try context.device_api.createRenderPass(context.device, &vk.RenderPassCreateInfo{
            .attachment_count = if (clear_flags.depth) attachment_descriptions.len else 1,
            .p_attachments = &attachment_descriptions,
            .subpass_count = subpasses.len,
            .p_subpasses = &subpasses,
            .dependency_count = if (clear_flags.depth) dependencies.len else 1,
            .p_dependencies = &dependencies,
        }, null);
        errdefer context.device_api.destroyRenderPass(context.device, self.handle, null);

        self.state = .initial;

        return self;
    }

    pub fn deinit(self: *RenderPass) void {
        if (self.handle != .null_handle) {
            self.context.device_api.destroyRenderPass(self.context.device, self.handle, null);
        }
        self.handle = .null_handle;
        self.state = .invalid;
    }

    pub fn begin(self: *RenderPass, command_buffer: *CommandBuffer, framebuffer: vk.Framebuffer) void {
        var clear_value_count: u32 = 0;
        var clear_values: [2]vk.ClearValue = undefined;

        if (self.clear_flags.color) {
            clear_values[clear_value_count] = vk.ClearValue{
                .color = .{ .float_32 = self.clear_values.color },
            };
            clear_value_count += 1;
        }

        if (self.clear_flags.depth) {
            clear_values[clear_value_count] = vk.ClearValue{
                .depth_stencil = .{
                    .depth = self.clear_values.depth,
                    .stencil = self.clear_values.stencil,
                },
            };
            clear_value_count += 1;
        }

        self.context.device_api.cmdBeginRenderPass(command_buffer.handle, &vk.RenderPassBeginInfo{
            .render_pass = self.handle,
            .framebuffer = framebuffer,
            .render_area = switch (self.render_area) {
                .fixed_area => |area| area,
                .swapchain_area => .{
                    .offset = .{ .x = 0, .y = 0 },
                    .extent = self.context.swapchain.extent,
                },
            },
            .clear_value_count = clear_value_count,
            .p_clear_values = &clear_values,
        }, .@"inline");

        command_buffer.state = .recording_in_render_pass;
        self.state = .recording;
    }

    pub fn end(self: *RenderPass, command_buffer: *CommandBuffer) void {
        self.context.device_api.cmdEndRenderPass(command_buffer.handle);
        command_buffer.state = .recording;
        self.state = .executable;
    }
};
