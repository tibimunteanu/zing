const std = @import("std");
const win = @import("types.zig");

pub const Image = extern struct {
    width: u32,
    height: u32,
    pixels: [*]const u8,
};

pub fn create(image: *const Image, x_hot: i32, y_hot: i32) ?*anyopaque {
    var header = win.BITMAPV5HEADER{
        .bV5Width = @intCast(image.width),
        .bV5Height = -@as(win.LONG, @intCast(image.height)),
    };
    var bits: ?*anyopaque = null;
    const dc = win.GetDC(null);
    const color = win.CreateDIBSection(dc, &header, win.DIB_RGB_COLORS, &bits, null, 0);
    _ = win.ReleaseDC(null, dc);
    if (color == null or bits == null) return null;
    defer _ = win.DeleteObject(@ptrCast(color));

    const pixel_count = image.width * image.height;
    const dst: [*]u8 = @ptrCast(bits.?);
    for (0..pixel_count) |i| {
        dst[i * 4 + 0] = image.pixels[i * 4 + 2];
        dst[i * 4 + 1] = image.pixels[i * 4 + 1];
        dst[i * 4 + 2] = image.pixels[i * 4 + 0];
        dst[i * 4 + 3] = image.pixels[i * 4 + 3];
    }

    const mask = win.CreateBitmap(@intCast(image.width), @intCast(image.height), 1, 1, null);
    if (mask == null) return null;
    defer _ = win.DeleteObject(@ptrCast(mask));

    var icon_info = win.ICONINFO{
        .fIcon = 0,
        .xHotspot = @bitCast(x_hot),
        .yHotspot = @bitCast(y_hot),
        .hbmMask = mask,
        .hbmColor = color,
    };
    const cursor = win.CreateIconIndirect(&icon_info) orelse return null;
    return allocCursor(cursor, true);
}

pub fn createStandard(shape: c_int) ?*anyopaque {
    const name = switch (shape) {
        0 => win.IDC_ARROW,
        1 => win.IDC_IBEAM,
        2 => win.IDC_CROSS,
        3 => win.IDC_HAND,
        4 => win.IDC_SIZEWE,
        5 => win.IDC_SIZENS,
        6 => win.IDC_SIZENWSE,
        7 => win.IDC_SIZENESW,
        8 => win.IDC_SIZEALL,
        9 => win.IDC_NO,
        else => return null,
    };
    const cursor: win.HCURSOR = @ptrCast(win.LoadImageW(null, name, win.IMAGE_CURSOR, 0, 0, win.LR_DEFAULTSIZE | win.LR_SHARED) orelse return null);
    return allocCursor(cursor, false);
}

pub fn destroy(handle: *anyopaque) void {
    const cursor: *Cursor = @ptrCast(@alignCast(handle));
    if (cursor.owned and cursor.handle != null) _ = win.DestroyIcon(@ptrCast(cursor.handle));
    std.heap.c_allocator.destroy(cursor);
}

fn allocCursor(handle: win.HCURSOR, owned: bool) ?*anyopaque {
    const cursor = std.heap.c_allocator.create(Cursor) catch return null;
    cursor.* = .{ .handle = handle, .owned = owned };
    return @ptrCast(cursor);
}

pub const Cursor = extern struct {
    handle: win.HCURSOR,
    owned: bool,
};
