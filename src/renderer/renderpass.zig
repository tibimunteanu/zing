const std = @import("std");
const vk = @import("vk.zig");
const Engine = @import("../engine.zig");
const Context = @import("context.zig");
const CommandBuffer = @import("command_buffer.zig");

const Allocator = std.mem.Allocator;

const RenderPass = @This();

pub const Type = enum {
    world,
    ui,
};

const RenderArea = union(enum) {
    fixed: vk.Rect2D,
    swapchain: void,
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

handle: vk.RenderPass,
render_area: RenderArea,
clear_values: ClearValues,
clear_flags: ClearFlags,
has_prev: bool,
has_next: bool,

// public
pub fn init(
    options: struct {
        render_area: RenderArea = .swapchain,
        clear_flags: ClearFlags = .{},
        clear_values: ClearValues = undefined,
        has_prev: bool,
        has_next: bool,
    },
) !RenderPass {
    var self: RenderPass = undefined;

    const ctx = Engine.instance.renderer.context;

    self.render_area = options.render_area;
    self.clear_flags = options.clear_flags;
    self.clear_values = options.clear_values;
    self.has_prev = options.has_prev;
    self.has_next = options.has_next;

    const attachment_descriptions = [_]vk.AttachmentDescription{
        .{
            .format = ctx.swapchain.surface_format.format,
            .samples = .{ .@"1_bit" = true },
            .load_op = if (options.clear_flags.color) .clear else .load,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = if (options.has_prev) .color_attachment_optimal else .undefined,
            .final_layout = if (options.has_next) .color_attachment_optimal else .present_src_khr,
        },
        .{
            .format = ctx.physical_device.depth_format,
            .samples = .{ .@"1_bit" = true },
            .load_op = if (options.clear_flags.depth) .clear else .load,
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
        .p_color_attachments = @ptrCast(&vk.AttachmentReference{
            .attachment = 0,
            .layout = .color_attachment_optimal,
        }),
        .p_depth_stencil_attachment = if (options.clear_flags.depth) &vk.AttachmentReference{
            .attachment = 1,
            .layout = .depth_stencil_attachment_optimal,
        } else null,
        .input_attachment_count = 0,
        .p_input_attachments = null,
        .preserve_attachment_count = 0,
        .p_preserve_attachments = null,
        .p_resolve_attachments = null,
    };

    const dependencies = [_]vk.SubpassDependency{
        .{
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .src_stage_mask = .{ .color_attachment_output_bit = true },
            .src_access_mask = .{},
            .dst_subpass = 0,
            .dst_stage_mask = .{ .color_attachment_output_bit = true },
            .dst_access_mask = .{ .color_attachment_read_bit = true, .color_attachment_write_bit = true },
            .dependency_flags = .{},
        },
        // NOTE: ensure that previous use of the depth-buffer is complete
        .{
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .src_stage_mask = .{ .late_fragment_tests_bit = true }, // store op is always performed in late tests
            .src_access_mask = .{ .depth_stencil_attachment_write_bit = true }, // after subpass access
            .dst_subpass = 0,
            .dst_stage_mask = .{ .early_fragment_tests_bit = true }, // load op is always performed in early tests
            .dst_access_mask = .{ .depth_stencil_attachment_write_bit = true, .depth_stencil_attachment_read_bit = true }, // before subpass access
            .dependency_flags = .{},
        },
    };

    self.handle = try ctx.device_api.createRenderPass(
        ctx.device,
        &vk.RenderPassCreateInfo{
            .attachment_count = if (options.clear_flags.depth) attachment_descriptions.len else 1,
            .p_attachments = &attachment_descriptions,
            .subpass_count = 1,
            .p_subpasses = @ptrCast(&subpass),
            .dependency_count = if (options.clear_flags.depth) dependencies.len else 1,
            .p_dependencies = &dependencies,
        },
        null,
    );
    errdefer ctx.device_api.destroyRenderPass(ctx.device, self.handle, null);

    return self;
}

pub fn deinit(self: *RenderPass) void {
    const ctx = Engine.instance.renderer.context;

    if (self.handle != .null_handle) {
        ctx.device_api.destroyRenderPass(ctx.device, self.handle, null);
    }
    self.handle = .null_handle;
}

pub fn begin(self: *RenderPass, command_buffer: *const CommandBuffer, framebuffer: vk.Framebuffer) void {
    const ctx = Engine.instance.renderer.context;

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

    ctx.device_api.cmdBeginRenderPass(command_buffer.handle, &vk.RenderPassBeginInfo{
        .render_pass = self.handle,
        .framebuffer = framebuffer,
        .render_area = switch (self.render_area) {
            .fixed => |area| area,
            .swapchain => .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = ctx.swapchain.extent,
            },
        },
        .clear_value_count = clear_value_count,
        .p_clear_values = &clear_values,
    }, .@"inline");
}

pub fn end(self: *RenderPass, command_buffer: *const CommandBuffer) void {
    _ = self;

    const ctx = Engine.instance.renderer.context;

    ctx.device_api.cmdEndRenderPass(command_buffer.handle);
}
