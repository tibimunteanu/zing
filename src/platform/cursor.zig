const Errors = @import("errors.zig");
const Window = @import("window.zig");
const platform = @import("platform.zig");

pub const Cursor = struct {
    id: usize,

    pub fn destroy(self: Cursor) !void {
        const native = try remove(self);
        Window.clearCursor(self);
        platform.Cursor.destroy(native);
    }

    pub fn nativeHandle(self: Cursor) !*anyopaque {
        return try get(self);
    }
};

const max_cursors = 256;
var cursors: [max_cursors]?*anyopaque = @splat(null);

pub const Shape = enum {
    arrow,
    ibeam,
    crosshair,
    pointing_hand,
    resize_ew,
    resize_ns,
    resize_nwse,
    resize_nesw,
    resize_all,
    not_allowed,
};

pub const Image = struct {
    width: u32,
    height: u32,
    pixels: []const u8,
};

pub fn create(image: Image, x_hot: i32, y_hot: i32) !Cursor {
    if (image.width == 0 or image.height == 0) {
        Errors.report(.invalid_value, "invalid cursor image dimensions", .{});
        return error.InvalidValue;
    }
    if (image.pixels.len < image.width * image.height * 4) {
        Errors.report(.invalid_value, "cursor image pixel buffer is too small", .{});
        return error.InvalidValue;
    }

    const native = blk: {
        const native_image = platform.Cursor.Image{
            .width = image.width,
            .height = image.height,
            .pixels = image.pixels.ptr,
        };
        break :blk platform.Cursor.create(&native_image, x_hot, y_hot) orelse {
            Errors.report(.platform_error, "Cocoa: failed to create cursor", .{});
            return error.PlatformError;
        };
    };

    return .{ .id = try insert(native) };
}

pub fn createStandard(shape: Shape) !Cursor {
    const native = platform.Cursor.createStandard(@intFromEnum(shape)) orelse {
        Errors.report(.cursor_unavailable, "standard cursor unavailable", .{});
        return error.CursorUnavailable;
    };

    return .{ .id = try insert(native) };
}

fn insert(native: *anyopaque) !usize {
    for (&cursors, 0..) |*slot, i| {
        if (slot.* == null) {
            slot.* = native;
            return i;
        }
    }
    return error.OutOfMemory;
}

fn get(cursor: Cursor) !*anyopaque {
    if (cursor.id >= cursors.len) return error.InvalidValue;
    return cursors[cursor.id] orelse error.InvalidValue;
}

fn remove(cursor: Cursor) !*anyopaque {
    const native = try get(cursor);
    cursors[cursor.id] = null;
    return native;
}
