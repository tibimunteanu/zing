const std = @import("std");
const vk = @import("vk.zig");
const Renderer = @import("renderer.zig");
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

    self.handle = try Renderer.device_api.createBuffer(Renderer.device, &vk.BufferCreateInfo{
        .flags = .{},
        .usage = usage,
        .size = size,
        .sharing_mode = .exclusive,
        .queue_family_index_count = 0,
        .p_queue_family_indices = null,
    }, null);
    errdefer Renderer.device_api.destroyBuffer(Renderer.device, self.handle, null);

    const memory_requirements = Renderer.device_api.getBufferMemoryRequirements(Renderer.device, self.handle);

    self.memory = try Renderer.allocate(memory_requirements, memory_property_flags);
    errdefer Renderer.device_api.freeMemory(Renderer.device, self.memory, null);

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

    if (self.handle != .null_handle) {
        Renderer.device_api.destroyBuffer(Renderer.device, self.handle, null);
        self.handle = .null_handle;
    }

    if (self.memory != .null_handle) {
        Renderer.device_api.freeMemory(Renderer.device, self.memory, null);
        self.memory = .null_handle;
    }

    self.total_size = 0;
    self.is_locked = false;
}

pub fn bind(self: *const Buffer, offset: vk.DeviceSize) !void {
    try Renderer.device_api.bindBufferMemory(Renderer.device, self.handle, self.memory, offset);
}

pub fn lock(self: *const Buffer, offset: vk.DeviceSize, size: vk.DeviceSize, flags: vk.MemoryMapFlags) ![*]u8 {
    return @as([*]u8, @ptrCast(try Renderer.device_api.mapMemory(
        Renderer.device,
        self.memory,
        offset,
        size,
        flags,
    )));
}

pub fn unlock(self: *const Buffer) void {
    Renderer.device_api.unmapMemory(Renderer.device, self.memory);
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
        Renderer.graphics_command_pool,
        Renderer.graphics_queue.handle,
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

    const new_buffer = try Buffer.init(
        Renderer,
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

    try Renderer.device_api.queueWaitIdle(queue);

    var command_buffer = try CommandBuffer.initAndBeginSingleUse(command_pool);

    Renderer.device_api.cmdCopyBuffer(command_buffer.handle, self.handle, dst.handle, 1, @ptrCast(&region));

    try command_buffer.endSingleUseAndDeinit(queue);
}
