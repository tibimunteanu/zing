const std = @import("std");

pub const Code = enum {
    not_initialized,
    no_current_context,
    invalid_enum,
    invalid_value,
    out_of_memory,
    api_unavailable,
    version_unavailable,
    platform_error,
    format_unavailable,
    no_window_context,
    cursor_unavailable,
    feature_unavailable,
    feature_unimplemented,
    platform_unavailable,
};

pub const Error = struct {
    code: Code,
    description: [:0]const u8,
};

pub const Callback = *const fn (Code, [:0]const u8) void;

var callback: ?Callback = null;
threadlocal var last_error: ?Error = null;

pub fn setCallback(new_callback: ?Callback) ?Callback {
    const previous = callback;
    callback = new_callback;
    return previous;
}

pub fn get() ?Error {
    const result = last_error;
    last_error = null;
    return result;
}

pub fn getString() ?[:0]const u8 {
    const result = get() orelse return null;
    return result.description;
}

pub fn clear() void {
    last_error = null;
}

pub fn report(code: Code, comptime format: []const u8, args: anytype) void {
    const description = formatStatic(format, args);
    last_error = .{
        .code = code,
        .description = description,
    };

    if (callback) |cb| {
        cb(code, description);
    }
}

fn formatStatic(comptime format: []const u8, args: anytype) [:0]const u8 {
    const Static = struct {
        threadlocal var buffer: [1024:0]u8 = undefined;
    };

    const text = std.fmt.bufPrintSentinel(&Static.buffer, format, args, 0) catch {
        const fallback = "error description too long";
        @memcpy(Static.buffer[0..fallback.len], fallback);
        Static.buffer[fallback.len] = 0;
        return Static.buffer[0..fallback.len :0];
    };
    return text;
}
