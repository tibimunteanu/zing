const std = @import("std");
const vk = @import("vk.zig");
const Context = @import("context.zig").Context;
const RenderPass = @import("renderpass.zig").RenderPass;
const CommandBuffer = @import("command_buffer.zig").CommandBuffer;
const Allocator = std.mem.Allocator;

pub const Framebuffer = struct {
    const Self = @This();

    handle: vk.Framebuffer,
    allocator: Allocator,
    attachments: []vk.ImageView,
    render_pass: ?*const RenderPass,

    pub fn init(
        context: *const Context,
        allocator: Allocator,
        render_pass: *const RenderPass,
        width: u32,
        height: u32,
        attachments: []const vk.ImageView,
    ) !Self {
        var self: Self = undefined;

        self.allocator = allocator;
        self.render_pass = render_pass;
        self.attachments = try allocator.dupe(vk.ImageView, attachments);

        self.handle = try context.device_api.createFramebuffer(context.device, &vk.FramebufferCreateInfo{
            .render_pass = render_pass.handle,
            .attachment_count = @intCast(self.attachments.len),
            .p_attachments = self.attachments.ptr,
            .width = width,
            .height = height,
            .layers = 1,
        }, null);

        return self;
    }

    pub fn deinit(self: *Self, context: *const Context) void {
        if (self.handle != .null_handle) {
            context.device_api.destroyFramebuffer(context.device, self.handle, null);
        }

        if (self.attachments.len > 0) {
            self.allocator.free(self.attachments);
        }

        self.handle = .null_handle;
        self.render_pass = null;
    }
};
