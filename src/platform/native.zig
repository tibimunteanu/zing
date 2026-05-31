const Window = @import("window.zig");
const Monitor = @import("monitor.zig").Monitor;
const MonitorModule = @import("monitor.zig");
const platform = @import("platform.zig");

pub const CocoaWindow = opaque {};
pub const CocoaView = opaque {};
pub const Win32Window = opaque {};
pub const X11Display = opaque {};
pub const X11Window = usize;

pub fn getCocoaWindow(window: Window) !*CocoaWindow {
    if (platform.os_tag != .macos) return error.PlatformUnavailable;
    return @ptrCast(platform.Native.getCocoaWindow(try window.nativeHandle()) orelse return error.PlatformError);
}

pub fn getCocoaView(window: Window) !*CocoaView {
    if (platform.os_tag != .macos) return error.PlatformUnavailable;
    return @ptrCast(platform.Native.getCocoaView(try window.nativeHandle()) orelse return error.PlatformError);
}

pub fn getWin32Window(window: Window) !*Win32Window {
    if (platform.os_tag != .windows) return error.PlatformUnavailable;
    return @ptrCast(platform.Native.getWin32Window(try window.nativeHandle()) orelse return error.PlatformError);
}

pub fn getX11Display() !*X11Display {
    return error.PlatformUnavailable;
}

pub fn getX11Window(window: Window) !X11Window {
    _ = window;
    return error.PlatformUnavailable;
}

pub fn getMonitorNativeHandle(monitor: Monitor) !*anyopaque {
    return try MonitorModule.nativeHandle(monitor);
}
