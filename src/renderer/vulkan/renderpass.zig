const std = @import("std");
const vk = @import("vk.zig");
const Context = @import("context.zig").Context;
const CommandBuffer = @import("command_buffer.zig").CommandBuffer;
const Allocator = std.mem.Allocator;

pub const RenderPass = struct {
    const Self = @This();

    pub const State = enum {
        not_allocated,
        ready,
        recording,
        in_render_pass,
        recording_ended,
        submitted,
    };

    pub const ClearValues = struct {
        color: [4]f32,
        depth: f32,
        stencil: u32,
    };

    state: State,
    handle: vk.RenderPass,
    render_area: vk.Rect2D,
    clear_values: ClearValues,

    pub fn init(context: *const Context, render_area: vk.Rect2D, clear_values: ClearValues) !Self {
        var self: Self = undefined;

        self.render_area = render_area;
        self.clear_values = clear_values;

        const attachment_descriptions = [_]vk.AttachmentDescription{
            .{
                .format = context.swapchain.surface_format.format,
                .samples = .{ .@"1_bit" = true },
                .load_op = .clear,
                .store_op = .store,
                .stencil_load_op = .dont_care,
                .stencil_store_op = .dont_care,
                .initial_layout = .undefined,
                .final_layout = .present_src_khr,
            },
            .{
                .format = context.physical_device.depth_format,
                .samples = .{ .@"1_bit" = true },
                .load_op = .clear,
                .store_op = .dont_care,
                .stencil_load_op = .dont_care,
                .stencil_store_op = .dont_care,
                .initial_layout = .undefined,
                .final_layout = .depth_stencil_attachment_optimal,
            },
        };

        const sub_pass = vk.SubpassDescription{
            .pipeline_bind_point = .graphics,
            .color_attachment_count = 1,
            .p_color_attachments = &[_]vk.AttachmentReference{
                .{
                    .attachment = 0,
                    .layout = .color_attachment_optimal,
                },
            },
            .p_depth_stencil_attachment = &.{
                .attachment = 1,
                .layout = .depth_stencil_attachment_optimal,
            },
            .input_attachment_count = 0,
            .p_input_attachments = undefined,
            .p_resolve_attachments = undefined,
            .preserve_attachment_count = 0,
            .p_preserve_attachments = undefined,
        };

        const dependency = vk.SubpassDependency{
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = 0,
            .src_stage_mask = .{ .color_attachment_output_bit = true },
            .src_access_mask = .{},
            .dst_stage_mask = .{ .color_attachment_output_bit = true },
            .dst_access_mask = .{ .color_attachment_read_bit = true, .color_attachment_write_bit = true },
            .dependency_flags = .{},
        };

        self.handle = try context.device_api.createRenderPass(context.device, &vk.RenderPassCreateInfo{
            .attachment_count = attachment_descriptions.len,
            .p_attachments = &attachment_descriptions,
            .subpass_count = 1,
            .p_subpasses = &[_]vk.SubpassDescription{sub_pass},
            .dependency_count = 1,
            .p_dependencies = &[_]vk.SubpassDependency{dependency},
        }, null);

        return self;
    }

    pub fn deinit(self: Self, context: *const Context) void {
        context.device_api.destroyRenderPass(context.device, self.handle, null);
    }

    pub fn begin(self: *Self, context: *const Context, command_buffer: CommandBuffer, framebuffer: vk.Framebuffer) void {
        context.device_api.cmdBeginRenderPass(command_buffer.handle, &vk.RenderPassBeginInfo{
            .render_pass = self.handle,
            .framebuffer = framebuffer,
            .render_area = self.render_area,
            .clear_value_count = 2,
            .p_clear_values = [_]vk.ClearValue{
                .{
                    .color = .{ .float_32 = self.clear_values.color },
                },
                .{
                    .depth_stencil = .{
                        .depth = self.clear_values.depth,
                        .stencil = self.clear_values.stencil,
                    },
                },
            },
        }, .@"inline");

        self.state = .in_render_pass;
    }

    pub fn end(self: Self, context: *const Context, command_buffer: *CommandBuffer) void {
        context.device_api.cmdEndRenderPass(context.device, command_buffer.handle);
        command_buffer.state = .recording;
        _ = self;
    }
};
