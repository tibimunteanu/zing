const std = @import("std");

const Window = @import("window.zig");
const Monitor = @import("monitor.zig").Monitor;
const MonitorModule = @import("monitor.zig");
const platform = @import("platform.zig");

pub const CocoaWindow = opaque {};
pub const CocoaView = opaque {};
pub const Win32Window = opaque {};
pub const X11Display = opaque {};
pub const X11Window = usize;
pub const X11Adapter = usize;
pub const X11Monitor = usize;

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
    if (platform.os_tag != .linux) return error.PlatformUnavailable;
    return @ptrCast(platform.Native.getX11Display() orelse return error.PlatformError);
}

pub fn getX11Window(window: Window) !X11Window {
    if (platform.os_tag != .linux) return error.PlatformUnavailable;
    return platform.Native.getX11Window(try window.nativeHandle());
}

pub fn getX11Adapter(monitor: Monitor) !X11Adapter {
    if (platform.os_tag != .linux) return error.PlatformUnavailable;
    return platform.Native.getX11Adapter(try MonitorModule.nativeHandle(monitor));
}

pub fn getX11Monitor(monitor: Monitor) !X11Monitor {
    if (platform.os_tag != .linux) return error.PlatformUnavailable;
    return platform.Native.getX11Monitor(try MonitorModule.nativeHandle(monitor));
}

pub fn setX11SelectionString(value: [:0]const u8) !void {
    return switch (platform.os_tag) {
        .linux => platform.Native.setX11SelectionString(value.ptr),
        else => error.PlatformUnavailable,
    };
}

pub fn getX11SelectionString() ![:0]const u8 {
    return switch (platform.os_tag) {
        .linux => blk: {
            const value = platform.Native.getX11SelectionString() orelse return error.PlatformError;
            break :blk std.mem.span(value);
        },
        else => error.PlatformUnavailable,
    };
}

pub fn getMonitorNativeHandle(monitor: Monitor) !*anyopaque {
    return try MonitorModule.nativeHandle(monitor);
}
