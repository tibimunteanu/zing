const std = @import("std");
const vk = @import("vk.zig");
const Context = @import("context.zig").Context;

pub const CommandBuffer = struct {
    const Self = @This();

    pub const State = enum {
        invalid,
        initial,
        recording,
        in_render_pass,
        executable,
        pending,
    };

    state: State = .invalid,
    handle: vk.CommandBuffer = .null_handle,

    pub fn init(context: *const Context, pool: vk.CommandPool, is_primary: bool) !Self {
        var self: Self = undefined;

        self.state = .invalid;

        try context.device_api.allocateCommandBuffers(context.device, &vk.CommandBufferAllocateInfo{
            .command_pool = pool,
            .command_buffer_count = 1,
            .level = if (is_primary) .primary else .secondary,
        }, @ptrCast(&self.handle));

        self.state = .initial;

        return self;
    }

    pub fn deinit(self: *Self, context: *const Context, pool: vk.CommandPool) void {
        if (self.handle != .null_handle) {
            context.device_api.freeCommandBuffers(context.device, pool, 1, @ptrCast(&self.handle));
        }
        self.handle = .null_handle;
        self.state = .invalid;
    }

    pub fn begin(self: *Self, context: *const Context, flags: vk.CommandBufferUsageFlags) !void {
        try context.device_api.beginCommandBuffer(self.handle, &vk.CommandBufferBeginInfo{
            .flags = flags,
        });

        self.state = .recording;
    }

    pub fn end(self: *Self, context: *const Context) !void {
        try context.device_api.endCommandBuffer(self.handle);

        self.state = .executable;
    }

    pub fn set_initial(self: *Self) void {
        self.state = .initial;
    }

    pub fn set_pending(self: *Self) void {
        self.state = .pending;
    }

    pub fn initAndBeginSingleUse(context: *const Context, pool: vk.CommandPool) !Self {
        var self = try CommandBuffer.init(context, pool, true);
        try self.begin(context, .{ .one_time_submit_bit = true });
        return self;
    }

    pub fn endSingleUseAndDeinit(self: *Self, context: *const Context, pool: vk.CommandPool, queue: vk.Queue) void {
        try self.end(context);

        try context.device_api.queueSubmit(queue, 1, &vk.SubmitInfo{
            .command_buffer_count = 1,
            .p_command_buffers = &self.handle,
        }, null);

        try context.device_api.queueWaitIdle();

        self.deinit(context, pool);
    }
};
