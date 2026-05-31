const types = @import("types.zig");

pub fn getCocoaWindow(handle: *anyopaque) ?*anyopaque {
    const window: *types.Window = @ptrCast(@alignCast(handle));
    return window.window;
}

pub fn getCocoaView(handle: *anyopaque) ?*anyopaque {
    const window: *types.Window = @ptrCast(@alignCast(handle));
    return window.view;
}
