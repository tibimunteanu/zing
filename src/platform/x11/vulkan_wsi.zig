const x11 = @import("types.zig");

pub const RequiredExtensions = [_][*:0]const u8{
    "VK_KHR_surface",
    "VK_KHR_xlib_surface",
};

pub fn getNativeDisplay() ?*anyopaque {
    return @ptrCast(x11.display orelse return null);
}

pub fn getNativeWindow(handle: *anyopaque) usize {
    const window = @import("window.zig").native(handle);
    return @intCast(window.handle);
}

pub fn getVisualId() usize {
    const display = x11.display orelse return 0;
    const lib = &(x11.xlib orelse return 0);
    const visual = lib.XDefaultVisual(display, x11.screen) orelse return 0;
    return @intCast(lib.XVisualIDFromVisual(visual));
}
