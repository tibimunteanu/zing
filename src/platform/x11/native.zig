const x11 = @import("types.zig");

pub fn getCocoaWindow(handle: *anyopaque) ?*anyopaque {
    _ = handle;
    return null;
}

pub fn getCocoaView(handle: *anyopaque) ?*anyopaque {
    _ = handle;
    return null;
}

pub fn getWin32Window(handle: *anyopaque) ?*anyopaque {
    _ = handle;
    return null;
}

pub fn getX11Display() ?*anyopaque {
    return @ptrCast(x11.display orelse return null);
}

pub fn getX11Window(handle: *anyopaque) usize {
    const window = @import("window.zig").native(handle);
    return @intCast(window.handle);
}

pub fn getX11Adapter(handle: *anyopaque) usize {
    return @import("monitor.zig").adapter(handle);
}

pub fn getX11Monitor(handle: *anyopaque) usize {
    return @import("monitor.zig").monitorOutput(handle);
}

pub fn setX11SelectionString(value: [*:0]const u8) void {
    @import("window.zig").setX11SelectionString(value);
}

pub fn getX11SelectionString() ?[*:0]const u8 {
    return @import("window.zig").getX11SelectionString();
}
