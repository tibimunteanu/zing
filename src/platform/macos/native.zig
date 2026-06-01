const types = @import("types.zig");
const monitor = @import("monitor.zig");

pub fn getCocoaWindow(handle: *anyopaque) ?*anyopaque {
    const window: *types.Window = @ptrCast(@alignCast(handle));
    return window.window;
}

pub fn getCocoaView(handle: *anyopaque) ?*anyopaque {
    const window: *types.Window = @ptrCast(@alignCast(handle));
    return window.view;
}

pub fn getCocoaMonitor(handle: *anyopaque) u32 {
    return monitor.getDisplayId(handle);
}
