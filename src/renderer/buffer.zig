const std = @import("std");
const vk = @import("vk.zig");
const Engine = @import("../engine.zig");
const Context = @import("context.zig");
const CommandBuffer = @import("command_buffer.zig");
const FreeList = @import("../free_list.zig");

const Allocator = std.mem.Allocator;

const Buffer = @This();

allocator: ?Allocator,
handle: vk.Buffer,
usage: vk.BufferUsageFlags,
total_size: vk.DeviceSize,
memory_property_flags: vk.MemoryPropertyFlags,
memory: vk.DeviceMemory,
is_locked: bool,
free_list: ?FreeList,

// public
pub fn init(
    allocator: ?Allocator,
    size: usize,
    usage: vk.BufferUsageFlags,
    memory_property_flags: vk.MemoryPropertyFlags,
    options: struct {
        managed: bool = false,
        bind_on_create: bool = false,
    },
) !Buffer {
    var self: Buffer = undefined;
    self.allocator = allocator;

    self.usage = usage;
    self.total_size = size;
    self.memory_property_flags = memory_property_flags;

    const ctx = Engine.instance.renderer.context;

    self.handle = try ctx.device_api.createBuffer(ctx.device, &vk.BufferCreateInfo{
        .flags = .{},
        .usage = usage,
        .size = size,
        .sharing_mode = .exclusive,
        .queue_family_index_count = 0,
        .p_queue_family_indices = null,
    }, null);
    errdefer ctx.device_api.destroyBuffer(ctx.device, self.handle, null);

    const memory_requirements = ctx.device_api.getBufferMemoryRequirements(ctx.device, self.handle);

    self.memory = try ctx.allocate(memory_requirements, memory_property_flags);
    errdefer ctx.device_api.freeMemory(ctx.device, self.memory, null);

    if (options.bind_on_create) {
        try self.bind(0);
    }

    self.free_list = if (options.managed) try FreeList.init(self.allocator.?, size, .{}) else null;

    return self;
}

pub fn deinit(self: *Buffer) void {
    if (self.free_list) |*free_list| {
        free_list.deinit();
    }

    const ctx = Engine.instance.renderer.context;

    if (self.handle != .null_handle) {
        ctx.device_api.destroyBuffer(ctx.device, self.handle, null);
        self.handle = .null_handle;
    }

    if (self.memory != .null_handle) {
        ctx.device_api.freeMemory(ctx.device, self.memory, null);
        self.memory = .null_handle;
    }

    self.total_size = 0;
    self.is_locked = false;
}

pub fn bind(self: *const Buffer, offset: vk.DeviceSize) !void {
    const ctx = Engine.instance.renderer.context;

    try ctx.device_api.bindBufferMemory(ctx.device, self.handle, self.memory, offset);
}

pub fn lock(self: *const Buffer, offset: vk.DeviceSize, size: vk.DeviceSize, flags: vk.MemoryMapFlags) ![*]u8 {
    const ctx = Engine.instance.renderer.context;

    return @as([*]u8, @ptrCast(try ctx.device_api.mapMemory(
        ctx.device,
        self.memory,
        offset,
        size,
        flags,
    )));
}

pub fn unlock(self: *const Buffer) void {
    const ctx = Engine.instance.renderer.context;

    ctx.device_api.unmapMemory(ctx.device, self.memory);
}

pub fn alloc(self: *Buffer, size: u64) !u64 {
    return if (self.free_list) |*free_list| try free_list.alloc(size) else error.CannotAllocUnmanagedBuffer;
}

pub fn free(self: *Buffer, offset: u64, size: u64) !void {
    if (self.free_list) |*free_list| try free_list.free(offset, size) else return error.CannotFreeUnmanagedBuffer;
}

pub fn allocAndUpload(self: *Buffer, data: []const u8) !u64 {
    const offset = try self.alloc(data.len);

    try self.upload(offset, data);

    return offset;
}

pub fn upload(self: *Buffer, offset: u64, data: []const u8) !void {
    const ctx = Engine.instance.renderer.context;

    var staging_buffer = try Buffer.init(
        null,
        self.total_size,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        .{ .bind_on_create = true },
    );
    defer staging_buffer.deinit();

    try staging_buffer.loadData(0, self.total_size, .{}, data);

    try staging_buffer.copyTo(
        self,
        Engine.instance.renderer.graphics_command_pool,
        ctx.graphics_queue.handle,
        vk.BufferCopy{
            .src_offset = 0,
            .dst_offset = offset,
            .size = data.len,
        },
    );
}

pub fn loadData(
    self: *const Buffer,
    offset: vk.DeviceSize,
    size: vk.DeviceSize,
    flags: vk.MemoryMapFlags,
    data: []const u8,
) !void {
    const dst = try self.lock(offset, size, flags);

    @memcpy(dst, data);

    self.unlock();
}

pub fn resize(self: *Buffer, new_size: usize, command_pool: vk.CommandPool, queue: vk.Queue) !void {
    if (new_size < self.total_size) {
        return error.CannotResizeBufferToSmallerSize;
    }

    const ctx = Engine.instance.renderer.context;

    const new_buffer = try Buffer.init(
        ctx,
        new_size,
        self.usage,
        self.memory_property_flags,
        .{ .bind_on_create = true },
    );
    errdefer new_buffer.deinit();

    try self.copyTo(&new_buffer, command_pool, queue, .{
        .src_offset = 0,
        .dst_offset = 0,
        .size = self.total_size,
    });

    self.deinit();
    self.* = new_buffer;
}

pub fn copyTo(
    self: *const Buffer,
    dst: *Buffer,
    command_pool: vk.CommandPool,
    queue: vk.Queue,
    region: vk.BufferCopy,
) !void {
    if (self.free_list != null and dst.free_list != null) {
        try self.free_list.?.copyTo(&dst.free_list.?);
    }

    const ctx = Engine.instance.renderer.context;

    try ctx.device_api.queueWaitIdle(queue);

    var command_buffer = try CommandBuffer.initAndBeginSingleUse(ctx, command_pool);

    ctx.device_api.cmdCopyBuffer(command_buffer.handle, self.handle, dst.handle, 1, @ptrCast(&region));

    try command_buffer.endSingleUseAndDeinit(queue);
}
