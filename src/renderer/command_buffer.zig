const std = @import("std");
const vk = @import("vk.zig");
const Context = @import("context.zig");

const CommandBuffer = @This();

context: *const Context,
handle: vk.CommandBuffer = .null_handle,
pool: vk.CommandPool,

// public
pub fn init(context: *const Context, pool: vk.CommandPool, options: struct { is_primary: bool = true }) !CommandBuffer {
    var self: CommandBuffer = undefined;
    self.context = context;
    self.pool = pool;

    try context.device_api.allocateCommandBuffers(
        context.device,
        &vk.CommandBufferAllocateInfo{
            .command_pool = pool,
            .command_buffer_count = 1,
            .level = if (options.is_primary) .primary else .secondary,
        },
        @ptrCast(&self.handle),
    );

    return self;
}

pub fn deinit(self: *CommandBuffer) void {
    if (self.handle != .null_handle) {
        self.context.device_api.freeCommandBuffers(self.context.device, self.pool, 1, @ptrCast(&self.handle));
    }
    self.handle = .null_handle;
    self.pool = .null_handle;
}

pub fn begin(self: *const CommandBuffer, flags: vk.CommandBufferUsageFlags) !void {
    try self.context.device_api.beginCommandBuffer(self.handle, &vk.CommandBufferBeginInfo{ .flags = flags });
}

pub fn end(self: *const CommandBuffer) !void {
    try self.context.device_api.endCommandBuffer(self.handle);
}

pub fn initAndBeginSingleUse(context: *const Context, pool: vk.CommandPool) !CommandBuffer {
    var self = try CommandBuffer.init(context, pool, .{});
    errdefer self.deinit();

    try self.begin(.{ .one_time_submit_bit = true });
    return self;
}

pub fn endSingleUseAndDeinit(self: *CommandBuffer, queue: vk.Queue) !void {
    defer self.deinit();

    try self.end();

    try self.context.device_api.queueSubmit(
        queue,
        1,
        @ptrCast(&vk.SubmitInfo{
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&self.handle),
        }),
        .null_handle,
    );

    try self.context.device_api.queueWaitIdle(queue);
}
