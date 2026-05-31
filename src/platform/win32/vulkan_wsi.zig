const win = @import("types.zig");

pub const RequiredExtensions = [_][*:0]const u8{
    "VK_KHR_surface",
    "VK_KHR_win32_surface",
};

pub fn getNativeWindow(handle: *anyopaque) ?*anyopaque {
    const window: *win.Window = @ptrCast(@alignCast(handle));
    return @ptrCast(window.handle);
}

pub fn getNativeInstance() ?*anyopaque {
    return @ptrCast(win.instance);
}
