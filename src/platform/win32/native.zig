const types = @import("types.zig");

pub fn getWin32Window(handle: *anyopaque) ?*anyopaque {
    const window: *types.Window = @ptrCast(@alignCast(handle));
    return @ptrCast(window.handle);
}

pub fn getWin32Instance() ?*anyopaque {
    return @ptrCast(types.instance);
}
