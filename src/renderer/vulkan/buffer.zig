const std = @import("std");
const Context = @import("context.zig").Context;
const CommandBuffer = @import("command_buffer.zig").CommandBuffer;
const vk = @import("vk.zig");

pub const Buffer = struct {
    const Self = @This();

    context: *const Context,

    handle: vk.Buffer,
    usage: vk.BufferUsageFlags,
    total_size: vk.DeviceSize,
    memory_property_flags: vk.MemoryPropertyFlags,
    memory: vk.DeviceMemory,
    is_locked: bool,

    pub fn init(
        context: *const Context,
        usage: vk.BufferUsageFlags,
        size: usize,
        memory_property_flags: vk.MemoryPropertyFlags,
        options: struct {
            bind_on_create: bool = false,
        },
    ) !Self {
        var self: Self = undefined;
        self.context = context;

        self.usage = usage;
        self.total_size = size;
        self.memory_property_flags = memory_property_flags;

        self.handle = try context.device_api.createBuffer(context.device, &vk.BufferCreateInfo{
            .flags = .{},
            .usage = usage,
            .size = size,
            .sharing_mode = .exclusive,
            .queue_family_index_count = 0,
            .p_queue_family_indices = null,
        }, null);
        errdefer context.device_api.destroyBuffer(context.device, self.handle, null);

        const memory_requirements = context.device_api.getBufferMemoryRequirements(context.device, self.handle);

        self.memory = try self.context.allocate(memory_requirements, memory_property_flags);
        errdefer context.device_api.freeMemory(context.device, self.memory, null);

        if (options.bind_on_create) {
            try self.bind(0);
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.handle != .null_handle) {
            self.context.device_api.destroyBuffer(self.context.device, self.handle, null);
            self.handle = .null_handle;
        }

        if (self.memory != .null_handle) {
            self.context.device_api.freeMemory(self.context.device, self.memory, null);
            self.memory = .null_handle;
        }

        self.total_size = 0;
        self.is_locked = false;
    }

    pub fn bind(self: Self, offset: vk.DeviceSize) !void {
        try self.context.device_api.bindBufferMemory(self.context.device, self.handle, self.memory, offset);
    }

    pub fn lock(self: Self, offset: vk.DeviceSize, size: vk.DeviceSize, flags: vk.MemoryMapFlags) !?*anyopaque {
        return try self.context.device_api.mapMemory(
            self.context.device,
            self.memory,
            offset,
            size,
            flags,
        );
    }

    pub fn unlock(self: Self) void {
        self.context.device_api.unmapMemory(self.context.device, self.memory);
    }

    pub fn loadData(
        self: Self,
        offset: vk.DeviceSize,
        size: vk.DeviceSize,
        flags: vk.MemoryMapFlags,
        data: []const u8,
    ) !void {
        const dst = try self.lock(offset, size, flags);

        @memcpy(@as([*]u8, @ptrCast(dst)), data);

        self.unlock();
    }

    pub fn resize(self: *Self, new_size: usize, command_pool: vk.CommandPool, queue: vk.Queue) !void {
        const new_buffer = try Buffer.init(
            self.context,
            self.usage,
            new_size,
            self.memory_property_flags,
            .{ .bind_on_create = true },
        );
        errdefer new_buffer.deinit();

        self.copyTo(&new_buffer, command_pool, queue, .{
            .src_offset = 0,
            .dst_offset = 0,
            .size = self.total_size,
        });

        // TODO: is it necessary to wait upon the device or could we get away with just queueWaitIdle?
        self.context.device_api.deviceWaitIdle(self.context.device);

        self.deinit();

        self.* = new_buffer;
    }

    pub fn copyTo(
        self: Self,
        dst: *Buffer,
        command_pool: vk.CommandPool,
        queue: vk.Queue,
        region: vk.BufferCopy,
    ) !void {
        try self.context.device_api.queueWaitIdle(queue);

        var temp_cmd_buffer = try CommandBuffer.initAndBeginSingleUse(self.context, command_pool);

        self.context.device_api.cmdCopyBuffer(temp_cmd_buffer.handle, self.handle, dst.handle, 1, @ptrCast(&region));

        try temp_cmd_buffer.endSingleUseAndDeinit(queue);
    }
};
