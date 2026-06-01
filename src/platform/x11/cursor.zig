const std = @import("std");

const x11 = @import("types.zig");

pub const Image = extern struct {
    width: u32,
    height: u32,
    pixels: [*]const u8,
};

const Cursor = struct {
    handle: x11.Cursor,
};

const XcursorImage = extern struct {
    version: c_uint = 1,
    size: c_uint = @sizeOf(XcursorImage),
    width: c_uint,
    height: c_uint,
    xhot: c_uint = 0,
    yhot: c_uint = 0,
    delay: c_uint = 0,
    pixels: [*]c_uint,
};

const Xcursor = struct {
    lib: std.DynLib,
    XcursorImageCreate: *const fn (c_int, c_int) callconv(.c) ?*XcursorImage,
    XcursorImageDestroy: *const fn (*XcursorImage) callconv(.c) void,
    XcursorImageLoadCursor: *const fn (*x11.Display, *XcursorImage) callconv(.c) x11.Cursor,
    XcursorGetTheme: *const fn (*x11.Display) callconv(.c) ?[*:0]const u8,
    XcursorGetDefaultSize: *const fn (*x11.Display) callconv(.c) c_int,
    XcursorLibraryLoadImage: *const fn ([*:0]const u8, [*:0]const u8, c_int) callconv(.c) ?*XcursorImage,
};

var xcursor: ?Xcursor = null;

const XC_left_ptr = 68;
const XC_crosshair = 34;
const XC_hand2 = 60;
const XC_xterm = 152;
const XC_sb_h_double_arrow = 108;
const XC_sb_v_double_arrow = 116;
const XC_fleur = 52;

pub fn create(image: *const Image, x_hot: i32, y_hot: i32) ?*anyopaque {
    const display = x11.display orelse return null;
    const handle = createNativeCursor(display, image, x_hot, y_hot) orelse return null;
    return wrapCursor(handle);
}

pub fn createStandard(shape: c_int) ?*anyopaque {
    const display = x11.display orelse return null;
    const xlib = &(x11.xlib orelse return null);

    if (loadXcursor()) |lib| {
        const theme = lib.XcursorGetTheme(display);
        if (theme) |theme_name| {
            const cursor_name = standardCursorName(shape);
            const size = lib.XcursorGetDefaultSize(display);
            if (cursor_name) |name| {
                if (lib.XcursorLibraryLoadImage(name, theme_name, size)) |image| {
                    defer lib.XcursorImageDestroy(image);
                    const handle = lib.XcursorImageLoadCursor(display, image);
                    if (handle != 0) return wrapCursor(handle);
                }
            }
        }
    }

    const cursor_shape: c_uint = switch (shape) {
        0 => XC_left_ptr,
        1 => XC_xterm,
        2 => XC_crosshair,
        3 => XC_hand2,
        4 => XC_sb_h_double_arrow,
        5 => XC_sb_v_double_arrow,
        8 => XC_fleur,
        else => return null,
    };
    const handle = xlib.XCreateFontCursor(display, cursor_shape);
    if (handle == 0) return null;

    return wrapCursor(handle);
}

pub fn destroy(handle: *anyopaque) void {
    const cursor: *Cursor = @ptrCast(@alignCast(handle));
    if (x11.display) |display| {
        if (x11.xlib) |lib| _ = lib.XFreeCursor(display, cursor.handle);
    }
    std.heap.c_allocator.destroy(cursor);
}

pub fn nativeCursor(handle: ?*anyopaque) x11.Cursor {
    if (handle) |value| {
        const cursor: *Cursor = @ptrCast(@alignCast(value));
        return cursor.handle;
    }
    return 0;
}

pub fn createNativeCursor(display: *x11.Display, image: *const Image, x_hot: i32, y_hot: i32) ?x11.Cursor {
    const lib = loadXcursor() orelse return null;
    const native = lib.XcursorImageCreate(@intCast(image.width), @intCast(image.height)) orelse return null;
    defer lib.XcursorImageDestroy(native);

    native.xhot = @intCast(@max(0, x_hot));
    native.yhot = @intCast(@max(0, y_hot));

    var i: usize = 0;
    while (i < image.width * image.height) : (i += 1) {
        const src = i * 4;
        const alpha: c_uint = image.pixels[src + 3];
        native.pixels[i] = (alpha << 24) |
            (((@as(c_uint, image.pixels[src + 0]) * alpha) / 255) << 16) |
            (((@as(c_uint, image.pixels[src + 1]) * alpha) / 255) << 8) |
            ((@as(c_uint, image.pixels[src + 2]) * alpha) / 255);
    }

    const handle = lib.XcursorImageLoadCursor(display, native);
    return if (handle != 0) handle else null;
}

fn wrapCursor(handle: x11.Cursor) ?*anyopaque {
    const display = x11.display orelse return null;
    const xlib = &(x11.xlib orelse return null);
    const cursor = std.heap.c_allocator.create(Cursor) catch {
        _ = xlib.XFreeCursor(display, handle);
        return null;
    };
    cursor.* = .{ .handle = handle };
    return @ptrCast(cursor);
}

fn standardCursorName(shape: c_int) ?[*:0]const u8 {
    return switch (shape) {
        0 => "default",
        1 => "text",
        2 => "crosshair",
        3 => "pointer",
        4 => "ew-resize",
        5 => "ns-resize",
        6 => "nwse-resize",
        7 => "nesw-resize",
        8 => "all-scroll",
        9 => "not-allowed",
        else => null,
    };
}

fn loadXcursor() ?*Xcursor {
    if (xcursor != null) return &xcursor.?;
    var lib = std.DynLib.open("libXcursor-1.so") catch
        std.DynLib.open("libXcursor.so") catch
        std.DynLib.open("libXcursor.so.1") catch return null;
    errdefer lib.close();

    xcursor = .{
        .lib = lib,
        .XcursorImageCreate = lookup(&lib, "XcursorImageCreate") orelse return null,
        .XcursorImageDestroy = lookup(&lib, "XcursorImageDestroy") orelse return null,
        .XcursorImageLoadCursor = lookup(&lib, "XcursorImageLoadCursor") orelse return null,
        .XcursorGetTheme = lookup(&lib, "XcursorGetTheme") orelse return null,
        .XcursorGetDefaultSize = lookup(&lib, "XcursorGetDefaultSize") orelse return null,
        .XcursorLibraryLoadImage = lookup(&lib, "XcursorLibraryLoadImage") orelse return null,
    };
    return &xcursor.?;
}

fn lookup(lib: *std.DynLib, comptime name: [:0]const u8) ?@TypeOf(@field(@as(Xcursor, undefined), name)) {
    return lib.lookup(@TypeOf(@field(@as(Xcursor, undefined), name)), name);
}
