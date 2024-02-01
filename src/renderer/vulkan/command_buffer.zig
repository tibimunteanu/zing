const std = @import("std");
const vk = @import("vk.zig");
const Context = @import("context.zig").Context;

pub const CommandBuffer = struct {
    pub const State = enum {
        invalid,
        initial,
        recording,
        recording_in_render_pass,
        executable,
        pending,
    };

    context: *const Context,
    handle: vk.CommandBuffer = .null_handle,
    pool: vk.CommandPool,
    state: State = .invalid,

    // public
    pub fn init(context: *const Context, pool: vk.CommandPool, is_primary: bool) !CommandBuffer {
        var self: CommandBuffer = undefined;
        self.context = context;
        self.pool = pool;

        self.state = .invalid;

        try context.device_api.allocateCommandBuffers(context.device, &vk.CommandBufferAllocateInfo{
            .command_pool = pool,
            .command_buffer_count = 1,
            .level = if (is_primary) .primary else .secondary,
        }, @ptrCast(&self.handle));
        errdefer context.device_api.freeCommandBuffers(context.device, pool, 1, @ptrCast(&self.handle));

        self.state = .initial;

        return self;
    }

    pub fn deinit(self: *CommandBuffer) void {
        if (self.handle != .null_handle) {
            self.context.device_api.freeCommandBuffers(self.context.device, self.pool, 1, @ptrCast(&self.handle));
        }
        self.handle = .null_handle;
        self.state = .invalid;
    }

    pub fn begin(self: *CommandBuffer, flags: vk.CommandBufferUsageFlags) !void {
        try self.context.device_api.beginCommandBuffer(self.handle, &vk.CommandBufferBeginInfo{
            .flags = flags,
        });

        self.state = .recording;
    }

    pub fn end(self: *CommandBuffer) !void {
        try self.context.device_api.endCommandBuffer(self.handle);

        self.state = .executable;
    }

    pub fn initAndBeginSingleUse(context: *const Context, pool: vk.CommandPool) !CommandBuffer {
        var self = try CommandBuffer.init(context, pool, true);
        errdefer self.deinit();

        try self.begin(.{ .one_time_submit_bit = true });
        return self;
    }

    pub fn endSingleUseAndDeinit(self: *CommandBuffer, queue: vk.Queue) !void {
        defer self.deinit();

        try self.end();

        try self.context.device_api.queueSubmit(queue, 1, &[_]vk.SubmitInfo{.{
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&self.handle),
        }}, .null_handle);

        try self.context.device_api.queueWaitIdle(queue);
    }
};
