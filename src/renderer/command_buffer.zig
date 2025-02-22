const std = @import("std");
const vk = @import("vk.zig");

const Renderer = @import("renderer.zig");

const CommandBuffer = @This();

handle: vk.CommandBuffer = .null_handle,
pool: vk.CommandPool,

// public
pub fn init(pool: vk.CommandPool, options: struct { is_primary: bool = true }) !CommandBuffer {
    var self: CommandBuffer = undefined;
    self.pool = pool;

    try Renderer.device_api.allocateCommandBuffers(
        Renderer.device,
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
        Renderer.device_api.freeCommandBuffers(Renderer.device, self.pool, 1, @ptrCast(&self.handle));
    }
    self.handle = .null_handle;
    self.pool = .null_handle;
}

pub fn begin(self: *const CommandBuffer, flags: vk.CommandBufferUsageFlags) !void {
    try Renderer.device_api.beginCommandBuffer(self.handle, &vk.CommandBufferBeginInfo{ .flags = flags });
}

pub fn end(self: *const CommandBuffer) !void {
    try Renderer.device_api.endCommandBuffer(self.handle);
}

pub fn initAndBeginSingleUse(pool: vk.CommandPool) !CommandBuffer {
    var self = try CommandBuffer.init(pool, .{});
    errdefer self.deinit();

    try self.begin(.{ .one_time_submit_bit = true });
    return self;
}

pub fn endSingleUseAndDeinit(self: *CommandBuffer, queue: vk.Queue) !void {
    defer self.deinit();

    try self.end();

    try Renderer.device_api.queueSubmit(
        queue,
        1,
        @ptrCast(&vk.SubmitInfo{
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&self.handle),
        }),
        .null_handle,
    );

    try Renderer.device_api.queueWaitIdle(queue);
}
