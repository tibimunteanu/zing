const std = @import("std");
const Errors = @import("errors.zig");
const platform = @import("platform.zig");

pub const Monitor = struct {
    id: usize,

    pub fn getPos(self: Monitor) !Pos {
        const pos = platform.Monitor.getPos(try native(self));
        return .{ .x = pos.x, .y = pos.y };
    }

    pub fn getWorkArea(self: Monitor) !WorkArea {
        const area = platform.Monitor.getWorkArea(try native(self));
        return .{ .x = area.x, .y = area.y, .width = area.width, .height = area.height };
    }

    pub fn getPhysicalSize(self: Monitor) !PhysicalSize {
        const size = platform.Monitor.getPhysicalSize(try native(self));
        return .{ .width_mm = size.width, .height_mm = size.height };
    }

    pub fn getContentScale(self: Monitor) !ContentScale {
        const scale = platform.Monitor.getContentScale(try native(self));
        return .{ .x_scale = scale.x_scale, .y_scale = scale.y_scale };
    }

    pub fn getName(self: Monitor) ![:0]const u8 {
        _ = try native(self);
        return std.mem.sliceTo(&names[self.id], 0);
    }

    pub fn setUserPointer(self: Monitor, pointer: ?*anyopaque) !void {
        _ = try native(self);
        user_pointers[self.id] = pointer;
    }

    pub fn getUserPointer(self: Monitor) !?*anyopaque {
        _ = try native(self);
        return user_pointers[self.id];
    }

    pub fn getVideoModes(self: Monitor, allocator: std.mem.Allocator) ![]VideoMode {
        const handle = try native(self);
        var buffer: [256]platform.Monitor.VideoMode = undefined;
        const count = platform.Monitor.getVideoModes(handle, &buffer, buffer.len);
        var scratch: [256]VideoMode = undefined;
        var unique_count: usize = 0;
        for (buffer[0..count]) |mode| {
            const converted = fromNativeVideoMode(mode);
            for (scratch[0..unique_count]) |existing| {
                if (orderVideoModes(converted, existing) == .eq) break;
            } else {
                scratch[unique_count] = converted;
                unique_count += 1;
            }
        }
        std.mem.sort(VideoMode, scratch[0..unique_count], {}, lessThanVideoMode);

        const result = try allocator.alloc(VideoMode, unique_count);
        @memcpy(result, scratch[0..unique_count]);
        return result;
    }

    pub fn getVideoMode(self: Monitor) !VideoMode {
        return fromNativeVideoMode(platform.Monitor.getVideoMode(try native(self)));
    }
};

pub const Pos = struct {
    x: i32,
    y: i32,
};

pub const WorkArea = struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,
};

pub const PhysicalSize = struct {
    width_mm: u32,
    height_mm: u32,
};

pub const ContentScale = struct {
    x_scale: f32,
    y_scale: f32,
};

pub const VideoMode = struct {
    width: u32,
    height: u32,
    red_bits: u32,
    green_bits: u32,
    blue_bits: u32,
    refresh_rate: u32,
};

pub const Event = enum {
    connected,
    disconnected,
};

pub const Callback = *const fn (Monitor, Event) void;

const max_monitors = 16;
var initialized = false;
var handles: [max_monitors]?*anyopaque = @splat(null);
var names: [max_monitors][128:0]u8 = @splat(@splat(0));
var user_pointers: [max_monitors]?*anyopaque = @splat(null);
var monitor_count: usize = 0;
var callback: ?Callback = null;

pub fn initSystem(allocator: std.mem.Allocator) !void {
    _ = allocator;
    if (initialized) return;
    if (!platform.Monitor.init()) return error.PlatformError;
    refresh();
    initialized = true;
}

pub fn deinitSystem() void {
    initialized = false;
    monitor_count = 0;
    handles = @splat(null);
}

pub fn getMonitors(allocator: std.mem.Allocator) ![]Monitor {
    try requireInit();
    const result = try allocator.alloc(Monitor, monitor_count);
    for (result, 0..) |*monitor, i| monitor.* = .{ .id = i };
    return result;
}

pub fn getPrimary() !Monitor {
    try requireInit();
    if (monitor_count == 0) return error.PlatformError;
    return .{ .id = 0 };
}

pub fn setCallback(new_callback: ?Callback) !?Callback {
    try requireInit();
    const previous = callback;
    callback = new_callback;
    return previous;
}

pub fn poll() !void {
    try requireInit();
    refresh();
}

pub fn nativeHandle(monitor: Monitor) !*anyopaque {
    return try native(monitor);
}

fn requireInit() !void {
    if (!initialized) {
        Errors.report(.not_initialized, "monitor system is not initialized", .{});
        return error.NotInitialized;
    }
}

fn refresh() void {
    var old_handles = handles;
    const old_names = names;
    const old_user_pointers = user_pointers;
    const old_count = monitor_count;

    handles = @splat(null);
    names = @splat(@splat(0));
    user_pointers = @splat(null);

    monitor_count = @min(platform.Monitor.count(), max_monitors);
    for (0..monitor_count) |i| {
        const handle = platform.Monitor.get(@intCast(i));
        handles[i] = handle;
        if (handle) |native_monitor| {
            if (findHandle(old_handles[0..old_count], native_monitor)) |old_index| {
                names[i] = old_names[old_index];
                user_pointers[i] = old_user_pointers[old_index];
                old_handles[old_index] = null;
            } else {
                copyName(i, native_monitor);
                if (callback) |cb| cb(.{ .id = i }, .connected);
            }
        }
    }

    for (old_handles[0..old_count], 0..) |maybe_handle, i| {
        if (maybe_handle != null) {
            if (callback) |cb| cb(.{ .id = i }, .disconnected);
        }
    }
}

fn findHandle(existing: []const ?*anyopaque, handle: *anyopaque) ?usize {
    for (existing, 0..) |maybe_existing, i| {
        if (maybe_existing) |existing_handle| {
            if (existing_handle == handle) return i;
        }
    }
    return null;
}

fn copyName(index: usize, handle: *anyopaque) void {
    const name = std.mem.sliceTo(platform.Monitor.getName(handle), 0);
    const len = @min(name.len, names[index].len - 1);
    @memset(&names[index], 0);
    @memcpy(names[index][0..len], name[0..len]);
}

fn native(monitor: Monitor) !*anyopaque {
    try requireInit();
    if (monitor.id >= monitor_count) return error.InvalidValue;
    return handles[monitor.id] orelse error.InvalidValue;
}

fn fromNativeVideoMode(mode: platform.Monitor.VideoMode) VideoMode {
    return .{
        .width = mode.width,
        .height = mode.height,
        .red_bits = mode.red_bits,
        .green_bits = mode.green_bits,
        .blue_bits = mode.blue_bits,
        .refresh_rate = mode.refresh_rate,
    };
}

fn lessThanVideoMode(_: void, lhs: VideoMode, rhs: VideoMode) bool {
    return orderVideoModes(lhs, rhs) == .lt;
}

fn orderVideoModes(lhs: VideoMode, rhs: VideoMode) std.math.Order {
    const lhs_bpp = lhs.red_bits + lhs.green_bits + lhs.blue_bits;
    const rhs_bpp = rhs.red_bits + rhs.green_bits + rhs.blue_bits;
    if (lhs_bpp != rhs_bpp) return std.math.order(lhs_bpp, rhs_bpp);

    const lhs_area = lhs.width * lhs.height;
    const rhs_area = rhs.width * rhs.height;
    if (lhs_area != rhs_area) return std.math.order(lhs_area, rhs_area);

    if (lhs.width != rhs.width) return std.math.order(lhs.width, rhs.width);
    return std.math.order(lhs.refresh_rate, rhs.refresh_rate);
}
