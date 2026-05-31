const objc = @import("objc.zig");

pub const ContentScale = extern struct {
    x_scale: f32,
    y_scale: f32,
};

pub const Pos = extern struct {
    x: i32,
    y: i32,
};

pub const Size = extern struct {
    width: u32,
    height: u32,
};

pub const VideoMode = extern struct {
    width: u32,
    height: u32,
    red_bits: u32,
    green_bits: u32,
    blue_bits: u32,
    refresh_rate: u32,
};

pub const WorkArea = extern struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,
};

pub fn init() bool {
    _ = objc.getClass("NSApplication").?.msgSend(objc.Object, "sharedApplication", .{});
    return true;
}

pub fn count() u32 {
    var display_count: u32 = 0;
    _ = CGGetOnlineDisplayList(0, null, &display_count);
    if (display_count == 0) return 1;
    return display_count;
}

pub fn get(index: u32) ?*anyopaque {
    var displays: [32]CGDirectDisplayID = undefined;
    var display_count: u32 = 0;
    _ = CGGetOnlineDisplayList(displays.len, &displays, &display_count);
    if (display_count == 0 and index == 0) return handleFromDisplayId(CGMainDisplayID());
    if (index >= display_count) return null;
    return handleFromDisplayId(displays[index]);
}

pub fn getPos(handle: *anyopaque) Pos {
    const frame = CGDisplayBounds(displayIdFromHandle(handle));
    return .{
        .x = @intFromFloat(frame.origin.x),
        .y = @intFromFloat(frame.origin.y),
    };
}

pub fn getWorkArea(handle: *anyopaque) WorkArea {
    const display_id = displayIdFromHandle(handle);
    if (screenFromDisplayId(display_id)) |screen| {
        const frame = screen.msgSend(CGRect, "visibleFrame", .{});
        return .{
            .x = @intFromFloat(frame.origin.x),
            .y = @intFromFloat(transformY(frame.origin.y + frame.size.height - 1.0)),
            .width = @intFromFloat(frame.size.width),
            .height = @intFromFloat(frame.size.height),
        };
    }

    const frame = CGDisplayBounds(display_id);
    return .{
        .x = @intFromFloat(frame.origin.x),
        .y = @intFromFloat(frame.origin.y),
        .width = @intFromFloat(frame.size.width),
        .height = @intFromFloat(frame.size.height),
    };
}

pub fn getContentScale(handle: *anyopaque) ContentScale {
    const screen = screenFromDisplayId(displayIdFromHandle(handle)) orelse return .{
        .x_scale = 1.0,
        .y_scale = 1.0,
    };
    const points = screen.msgSend(CGRect, "frame", .{});
    const pixels = screen.msgSend(CGRect, "convertRectToBacking:", .{points});
    return .{
        .x_scale = @floatCast(pixels.size.width / points.size.width),
        .y_scale = @floatCast(pixels.size.height / points.size.height),
    };
}

pub fn getPhysicalSize(handle: *anyopaque) Size {
    const size = CGDisplayScreenSize(displayIdFromHandle(handle));
    return .{
        .width = @intFromFloat(size.width),
        .height = @intFromFloat(size.height),
    };
}

pub fn getName(handle: *anyopaque) [*:0]const u8 {
    const screen = screenFromDisplayId(displayIdFromHandle(handle)) orelse return "Display";
    if (!screen.msgSend(bool, "respondsToSelector:", .{objc.sel("localizedName").value})) return "Display";
    const name = screen.msgSend(objc.Object, "localizedName", .{});
    if (name.value == null) return "Display";
    return name.msgSend([*:0]const u8, "UTF8String", .{});
}

pub fn getVideoMode(handle: *anyopaque) VideoMode {
    const mode = CGDisplayCopyDisplayMode(displayIdFromHandle(handle)) orelse return .{
        .width = 0,
        .height = 0,
        .red_bits = 0,
        .green_bits = 0,
        .blue_bits = 0,
        .refresh_rate = 0,
    };
    defer CGDisplayModeRelease(mode);

    var refresh_rate: u32 = @intFromFloat(@round(CGDisplayModeGetRefreshRate(mode)));
    if (refresh_rate == 0) refresh_rate = 60;
    return .{
        .width = @intCast(CGDisplayModeGetWidth(mode)),
        .height = @intCast(CGDisplayModeGetHeight(mode)),
        .red_bits = 8,
        .green_bits = 8,
        .blue_bits = 8,
        .refresh_rate = refresh_rate,
    };
}

pub fn getVideoModes(handle: *anyopaque, out_modes: [*]VideoMode, max_modes: u32) u32 {
    const modes = CGDisplayCopyAllDisplayModes(displayIdFromHandle(handle), null) orelse {
        if (max_modes == 0) return 0;
        out_modes[0] = getVideoMode(handle);
        return 1;
    };
    defer CFRelease(modes);

    var result_count: u32 = 0;
    const mode_count = CFArrayGetCount(modes);
    var i: CFIndex = 0;
    while (i < mode_count and result_count < max_modes) : (i += 1) {
        const mode: CGDisplayModeRef = @ptrCast(@alignCast(CFArrayGetValueAtIndex(modes, i) orelse continue));
        const flags = CGDisplayModeGetIOFlags(mode);
        if ((flags & kDisplayModeValidFlag) == 0 or (flags & kDisplayModeSafeFlag) == 0) continue;

        out_modes[result_count] = videoModeFromDisplayMode(mode);
        result_count += 1;
    }
    return result_count;
}

pub fn free(pointer: *anyopaque) void {
    _ = pointer;
}

const CGDirectDisplayID = u32;
const CFArrayRef = *opaque {};
const CFIndex = isize;
const CGDisplayModeRef = *const opaque {};
const kDisplayModeValidFlag: u32 = 0x00000001;
const kDisplayModeSafeFlag: u32 = 0x00000002;

const CGPoint = extern struct {
    x: f64,
    y: f64,
};

const CGSize = extern struct {
    width: f64,
    height: f64,
};

const CGRect = extern struct {
    origin: CGPoint,
    size: CGSize,
};

extern "c" fn CGMainDisplayID() CGDirectDisplayID;
extern "c" fn CGGetOnlineDisplayList(max_displays: u32, active_displays: ?[*]CGDirectDisplayID, display_count: *u32) c_int;
extern "c" fn CGDisplayBounds(display: CGDirectDisplayID) CGRect;
extern "c" fn CGDisplayScreenSize(display: CGDirectDisplayID) CGSize;
extern "c" fn CGDisplayCopyDisplayMode(display: CGDirectDisplayID) ?CGDisplayModeRef;
extern "c" fn CGDisplayModeRelease(mode: CGDisplayModeRef) void;
extern "c" fn CGDisplayModeGetWidth(mode: CGDisplayModeRef) usize;
extern "c" fn CGDisplayModeGetHeight(mode: CGDisplayModeRef) usize;
extern "c" fn CGDisplayModeGetRefreshRate(mode: CGDisplayModeRef) f64;
extern "c" fn CGDisplayModeGetIOFlags(mode: CGDisplayModeRef) u32;
extern "c" fn CGDisplayCopyAllDisplayModes(display: CGDirectDisplayID, options: ?*anyopaque) ?CFArrayRef;
extern "c" fn CFArrayGetCount(array: CFArrayRef) CFIndex;
extern "c" fn CFArrayGetValueAtIndex(array: CFArrayRef, index: CFIndex) ?*const anyopaque;
extern "c" fn CFRelease(object: *anyopaque) void;

fn transformY(y: f64) f64 {
    return CGDisplayBounds(CGMainDisplayID()).size.height - y - 1.0;
}

fn screenFromDisplayId(display_id: CGDirectDisplayID) ?objc.Object {
    const screens = objc.getClass("NSScreen").?.msgSend(objc.Object, "screens", .{});
    const screen_count = screens.msgSend(usize, "count", .{});
    var i: usize = 0;
    while (i < screen_count) : (i += 1) {
        const screen = screens.msgSend(objc.Object, "objectAtIndex:", .{i});
        const description = screen.msgSend(objc.Object, "deviceDescription", .{});
        const number = description.msgSend(objc.Object, "objectForKey:", .{nsString("NSScreenNumber").value});
        if (number.value != null and number.msgSend(u32, "unsignedIntValue", .{}) == display_id) {
            return screen;
        }
    }
    return null;
}

fn videoModeFromDisplayMode(mode: CGDisplayModeRef) VideoMode {
    var refresh_rate: u32 = @intFromFloat(@round(CGDisplayModeGetRefreshRate(mode)));
    if (refresh_rate == 0) refresh_rate = 60;
    return .{
        .width = @intCast(CGDisplayModeGetWidth(mode)),
        .height = @intCast(CGDisplayModeGetHeight(mode)),
        .red_bits = 8,
        .green_bits = 8,
        .blue_bits = 8,
        .refresh_rate = refresh_rate,
    };
}

fn nsString(value: [:0]const u8) objc.Object {
    return objc.getClass("NSString").?.msgSend(objc.Object, "stringWithUTF8String:", .{value.ptr});
}

fn handleFromDisplayId(display_id: CGDirectDisplayID) *anyopaque {
    return @ptrFromInt(@as(usize, display_id) + 1);
}

fn displayIdFromHandle(handle: *anyopaque) CGDirectDisplayID {
    return @intCast(@intFromPtr(handle) - 1);
}
