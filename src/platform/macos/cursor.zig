const std = @import("std");

const objc = @import("objc.zig");
const types = @import("types.zig");

pub const Image = extern struct {
    width: u32,
    height: u32,
    pixels: [*]const u8,
};

pub fn create(image: *const Image, x_hot: i32, y_hot: i32) ?*anyopaque {
    const rep = objc.getClass("NSBitmapImageRep").?.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bitmapFormat:bytesPerRow:bitsPerPixel:", .{
        @as(?*anyopaque, null),
        @as(isize, @intCast(image.width)),
        @as(isize, @intCast(image.height)),
        @as(isize, 8),
        @as(isize, 4),
        true,
        false,
        NSCalibratedRGBColorSpace,
        @as(usize, 1 << 1),
        @as(isize, @intCast(image.width * 4)),
        @as(isize, 32),
    });
    if (rep.value == null) return null;
    defer rep.msgSend(void, "release", .{});

    const bitmap_data = rep.msgSend([*]u8, "bitmapData", .{});
    @memcpy(bitmap_data[0 .. image.width * image.height * 4], image.pixels[0 .. image.width * image.height * 4]);

    const ns_image = objc.getClass("NSImage").?.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "initWithSize:", .{CGSize{
        .width = @floatFromInt(image.width),
        .height = @floatFromInt(image.height),
    }});
    if (ns_image.value == null) return null;
    defer ns_image.msgSend(void, "release", .{});
    ns_image.msgSend(void, "addRepresentation:", .{rep.value});

    const cursor = objc.getClass("NSCursor").?.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "initWithImage:hotSpot:", .{
        ns_image.value,
        CGPoint{ .x = @floatFromInt(x_hot), .y = @floatFromInt(y_hot) },
    });
    if (cursor.value == null) return null;

    const result = std.heap.c_allocator.create(types.Cursor) catch {
        cursor.msgSend(void, "release", .{});
        return null;
    };
    result.* = .{ .cursor = cursor.value };
    return @ptrCast(result);
}

pub fn createStandard(shape: c_int) ?*anyopaque {
    const selector: [:0]const u8 = switch (shape) {
        0 => "arrowCursor",
        1 => "IBeamCursor",
        2 => "crosshairCursor",
        3 => "pointingHandCursor",
        4 => "resizeLeftRightCursor",
        5 => "resizeUpDownCursor",
        8 => "closedHandCursor",
        9 => "operationNotAllowedCursor",
        else => return null,
    };

    const cursor = objc.getClass("NSCursor").?.msgSend(objc.Object, selector, .{});
    if (cursor.value == null) return null;

    const result = std.heap.c_allocator.create(types.Cursor) catch return null;
    result.* = .{
        .cursor = cursor.msgSend(objc.Object, "retain", .{}).value,
    };
    return @ptrCast(result);
}

pub fn destroy(handle: *anyopaque) void {
    const native: *types.Cursor = @ptrCast(@alignCast(handle));
    objc.Object.fromId(native.cursor).msgSend(void, "release", .{});
    std.heap.c_allocator.destroy(native);
}

const CGPoint = extern struct {
    x: f64,
    y: f64,
};

const CGSize = extern struct {
    width: f64,
    height: f64,
};

extern "c" var NSCalibratedRGBColorSpace: objc.c.id;
