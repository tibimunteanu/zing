const std = @import("std");
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

const Monitor = struct {
    display_id: CGDirectDisplayID,
    unit_number: u32,
    screen: objc.c.id,
    previous_mode: ?CGDisplayModeRef = null,
    fallback_refresh_rate: f64 = 60.0,
};

var monitors: [32]Monitor = undefined;
var monitor_count: u32 = 0;

pub fn init() bool {
    _ = objc.getClass("NSApplication").?.msgSend(objc.Object, "sharedApplication", .{});
    refresh();
    return true;
}

pub fn count() u32 {
    refresh();
    return monitor_count;
}

pub fn get(index: u32) ?*anyopaque {
    refresh();
    if (index >= monitor_count) return null;
    return @ptrCast(&monitors[index]);
}

pub fn getPos(handle: *anyopaque) Pos {
    const frame = CGDisplayBounds(native(handle).display_id);
    return .{
        .x = @intFromFloat(frame.origin.x),
        .y = @intFromFloat(frame.origin.y),
    };
}

pub fn getWorkArea(handle: *anyopaque) WorkArea {
    const display_id = native(handle).display_id;
    if (native(handle).screen) |screen_id| {
        const screen = objc.Object.fromId(screen_id);
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
    const screen = if (native(handle).screen) |screen_id| objc.Object.fromId(screen_id) else return .{
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
    const size = CGDisplayScreenSize(native(handle).display_id);
    return .{
        .width = @intFromFloat(size.width),
        .height = @intFromFloat(size.height),
    };
}

pub fn getName(handle: *anyopaque) [*:0]const u8 {
    const screen = if (native(handle).screen) |screen_id| objc.Object.fromId(screen_id) else return "Display";
    if (!screen.msgSend(bool, "respondsToSelector:", .{objc.sel("localizedName").value})) return "Display";
    const name = screen.msgSend(objc.Object, "localizedName", .{});
    if (name.value == null) return "Display";
    return name.msgSend([*:0]const u8, "UTF8String", .{});
}

pub fn getVideoMode(handle: *anyopaque) VideoMode {
    const monitor = native(handle);
    const mode = CGDisplayCopyDisplayMode(monitor.display_id) orelse return .{
        .width = 0,
        .height = 0,
        .red_bits = 0,
        .green_bits = 0,
        .blue_bits = 0,
        .refresh_rate = 0,
    };
    defer CGDisplayModeRelease(mode);

    return videoModeFromDisplayMode(mode, monitor.fallback_refresh_rate);
}

pub fn getVideoModes(handle: *anyopaque, out_modes: [*]VideoMode, max_modes: u32) u32 {
    const monitor = native(handle);
    const modes = CGDisplayCopyAllDisplayModes(monitor.display_id, null) orelse {
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
        if (!modeIsGood(mode)) continue;

        const converted = videoModeFromDisplayMode(mode, monitor.fallback_refresh_rate);
        var duplicate = false;
        for (out_modes[0..result_count]) |existing| {
            if (compareVideoModes(existing, converted) == .eq) {
                duplicate = true;
                break;
            }
        }
        if (duplicate) continue;

        out_modes[result_count] = converted;
        result_count += 1;
    }
    return result_count;
}

pub fn free(pointer: *anyopaque) void {
    _ = pointer;
}

pub fn setVideoMode(handle: *anyopaque, requested: VideoMode) bool {
    const monitor = native(handle);
    const best = chooseVideoMode(handle, requested) orelse return false;
    const current = getVideoMode(handle);
    if (compareVideoModes(current, best) == .eq) return true;

    const modes = CGDisplayCopyAllDisplayModes(monitor.display_id, null) orelse return false;
    defer CFRelease(modes);

    var selected: ?CGDisplayModeRef = null;
    const mode_count = CFArrayGetCount(modes);
    var i: CFIndex = 0;
    while (i < mode_count) : (i += 1) {
        const mode: CGDisplayModeRef = @ptrCast(@alignCast(CFArrayGetValueAtIndex(modes, i) orelse continue));
        if (!modeIsGood(mode)) continue;
        if (compareVideoModes(best, videoModeFromDisplayMode(mode, monitor.fallback_refresh_rate)) == .eq) {
            selected = mode;
            break;
        }
    }

    if (selected) |mode| {
        if (monitor.previous_mode == null) monitor.previous_mode = CGDisplayCopyDisplayMode(monitor.display_id);
        const token = beginFadeReservation();
        _ = CGDisplaySetDisplayMode(monitor.display_id, mode, null);
        endFadeReservation(token);
        return true;
    }
    return false;
}

pub fn restoreVideoMode(handle: *anyopaque) void {
    const monitor = native(handle);
    if (monitor.previous_mode) |previous| {
        const token = beginFadeReservation();
        _ = CGDisplaySetDisplayMode(monitor.display_id, previous, null);
        endFadeReservation(token);
        CGDisplayModeRelease(previous);
        monitor.previous_mode = null;
    }
}

pub fn getDisplayBounds(handle: *anyopaque) CGRect {
    return CGDisplayBounds(native(handle).display_id);
}

const CGDirectDisplayID = u32;
const CFArrayRef = *opaque {};
const CFIndex = isize;
const CGDisplayModeRef = *const opaque {};
const kDisplayModeValidFlag: u32 = 0x00000001;
const kDisplayModeSafeFlag: u32 = 0x00000002;
const kDisplayModeInterlacedFlag: u32 = 0x00000040;
const kDisplayModeStretchedFlag: u32 = 0x00000800;
const kCGDisplayFadeReservationInvalidToken: u32 = 0;
const kCGDisplayBlendNormal: c_uint = 0;
const kCGDisplayBlendSolidColor: c_uint = 1;
const kCGErrorSuccess: c_int = 0;

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
extern "c" fn CGDisplayIsAsleep(display: CGDirectDisplayID) bool;
extern "c" fn CGDisplayUnitNumber(display: CGDirectDisplayID) u32;
extern "c" fn CGDisplayBounds(display: CGDirectDisplayID) CGRect;
extern "c" fn CGDisplayScreenSize(display: CGDirectDisplayID) CGSize;
extern "c" fn CGDisplayCopyDisplayMode(display: CGDirectDisplayID) ?CGDisplayModeRef;
extern "c" fn CGDisplayModeRelease(mode: CGDisplayModeRef) void;
extern "c" fn CGDisplayModeGetWidth(mode: CGDisplayModeRef) usize;
extern "c" fn CGDisplayModeGetHeight(mode: CGDisplayModeRef) usize;
extern "c" fn CGDisplayModeGetRefreshRate(mode: CGDisplayModeRef) f64;
extern "c" fn CGDisplayModeGetIOFlags(mode: CGDisplayModeRef) u32;
extern "c" fn CGDisplayCopyAllDisplayModes(display: CGDirectDisplayID, options: ?*anyopaque) ?CFArrayRef;
extern "c" fn CGDisplaySetDisplayMode(display: CGDirectDisplayID, mode: CGDisplayModeRef, options: ?*anyopaque) c_int;
extern "c" fn CGAcquireDisplayFadeReservation(seconds: f64, token: *u32) c_int;
extern "c" fn CGDisplayFade(token: u32, duration: f64, start_blend: c_uint, end_blend: c_uint, red: f64, green: f64, blue: f64, synchronous: bool) c_int;
extern "c" fn CGReleaseDisplayFadeReservation(token: u32) c_int;
extern "c" fn CFArrayGetCount(array: CFArrayRef) CFIndex;
extern "c" fn CFArrayGetValueAtIndex(array: CFArrayRef, index: CFIndex) ?*const anyopaque;
extern "c" fn CFRelease(object: *anyopaque) void;

fn transformY(y: f64) f64 {
    return CGDisplayBounds(CGMainDisplayID()).size.height - y - 1.0;
}

fn screenFromDisplayId(display_id: CGDirectDisplayID) ?objc.Object {
    const screens = objc.getClass("NSScreen").?.msgSend(objc.Object, "screens", .{});
    const screen_count = screens.msgSend(usize, "count", .{});
    const unit_number = CGDisplayUnitNumber(display_id);
    var i: usize = 0;
    while (i < screen_count) : (i += 1) {
        const screen = screens.msgSend(objc.Object, "objectAtIndex:", .{i});
        const description = screen.msgSend(objc.Object, "deviceDescription", .{});
        const number = description.msgSend(objc.Object, "objectForKey:", .{nsString("NSScreenNumber").value});
        if (number.value != null and CGDisplayUnitNumber(number.msgSend(u32, "unsignedIntValue", .{})) == unit_number) {
            return screen;
        }
    }
    return null;
}

fn videoModeFromDisplayMode(mode: CGDisplayModeRef, fallback_refresh_rate: f64) VideoMode {
    var refresh_rate: u32 = @intFromFloat(@round(CGDisplayModeGetRefreshRate(mode)));
    if (refresh_rate == 0) refresh_rate = @intFromFloat(@round(fallback_refresh_rate));
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

fn native(handle: *anyopaque) *Monitor {
    return @ptrCast(@alignCast(handle));
}

fn refresh() void {
    var display_count: u32 = 0;
    _ = CGGetOnlineDisplayList(0, null, &display_count);
    var displays: [32]CGDirectDisplayID = undefined;
    _ = CGGetOnlineDisplayList(displays.len, &displays, &display_count);

    var new_monitors: [32]Monitor = undefined;
    var new_count: u32 = 0;
    var i: u32 = 0;
    while (i < display_count and new_count < new_monitors.len) : (i += 1) {
        const display_id = displays[i];
        if (CGDisplayIsAsleep(display_id)) continue;

        const unit_number = CGDisplayUnitNumber(display_id);
        const screen = screenFromDisplayId(display_id);
        new_monitors[new_count] = .{
            .display_id = display_id,
            .unit_number = unit_number,
            .screen = if (screen) |value| value.value else null,
            .fallback_refresh_rate = 60.0,
        };
        if (findPreviousMode(unit_number)) |previous| {
            new_monitors[new_count].previous_mode = previous;
        }
        if (CGDisplayCopyDisplayMode(display_id)) |mode| {
            if (CGDisplayModeGetRefreshRate(mode) == 0.0) new_monitors[new_count].fallback_refresh_rate = 60.0;
            CGDisplayModeRelease(mode);
        }
        new_count += 1;
    }

    if (new_count == 0) {
        new_monitors[0] = .{
            .display_id = CGMainDisplayID(),
            .unit_number = CGDisplayUnitNumber(CGMainDisplayID()),
            .screen = if (screenFromDisplayId(CGMainDisplayID())) |value| value.value else null,
        };
        new_count = 1;
    }

    monitors = new_monitors;
    monitor_count = new_count;
}

fn findPreviousMode(unit_number: u32) ?CGDisplayModeRef {
    var i: u32 = 0;
    while (i < monitor_count) : (i += 1) {
        if (monitors[i].unit_number == unit_number) return monitors[i].previous_mode;
    }
    return null;
}

fn modeIsGood(mode: CGDisplayModeRef) bool {
    const flags = CGDisplayModeGetIOFlags(mode);
    if ((flags & kDisplayModeValidFlag) == 0 or (flags & kDisplayModeSafeFlag) == 0) return false;
    if ((flags & kDisplayModeInterlacedFlag) != 0) return false;
    if ((flags & kDisplayModeStretchedFlag) != 0) return false;
    return true;
}

fn beginFadeReservation() u32 {
    var token: u32 = kCGDisplayFadeReservationInvalidToken;
    if (CGAcquireDisplayFadeReservation(5.0, &token) == kCGErrorSuccess) {
        _ = CGDisplayFade(token, 0.3, kCGDisplayBlendNormal, kCGDisplayBlendSolidColor, 0.0, 0.0, 0.0, true);
    }
    return token;
}

fn endFadeReservation(token: u32) void {
    if (token != kCGDisplayFadeReservationInvalidToken) {
        _ = CGDisplayFade(token, 0.5, kCGDisplayBlendSolidColor, kCGDisplayBlendNormal, 0.0, 0.0, 0.0, false);
        _ = CGReleaseDisplayFadeReservation(token);
    }
}

fn chooseVideoMode(handle: *anyopaque, desired: VideoMode) ?VideoMode {
    var modes: [256]VideoMode = undefined;
    const mode_count = getVideoModes(handle, &modes, modes.len);
    if (mode_count == 0) return null;

    var best = modes[0];
    var best_score = videoModeScore(best, desired);
    for (modes[1..mode_count]) |candidate| {
        const score = videoModeScore(candidate, desired);
        if (score < best_score) {
            best = candidate;
            best_score = score;
        }
    }
    return best;
}

fn videoModeScore(candidate: VideoMode, desired: VideoMode) u64 {
    const color_diff = absDiff(candidate.red_bits, desired.red_bits) +
        absDiff(candidate.green_bits, desired.green_bits) +
        absDiff(candidate.blue_bits, desired.blue_bits);
    const size_diff = absDiff(candidate.width, desired.width) +
        absDiff(candidate.height, desired.height);
    const refresh_diff = if (desired.refresh_rate == 0) 0 else absDiff(candidate.refresh_rate, desired.refresh_rate);
    return @as(u64, color_diff) * 1_000_000_000 + @as(u64, size_diff) * 1_000 + refresh_diff;
}

fn absDiff(a: u32, b: u32) u32 {
    return if (a > b) a - b else b - a;
}

fn compareVideoModes(lhs: VideoMode, rhs: VideoMode) std.math.Order {
    var order = std.math.order(lhs.width, rhs.width);
    if (order != .eq) return order;
    order = std.math.order(lhs.height, rhs.height);
    if (order != .eq) return order;
    order = std.math.order(lhs.red_bits, rhs.red_bits);
    if (order != .eq) return order;
    order = std.math.order(lhs.green_bits, rhs.green_bits);
    if (order != .eq) return order;
    order = std.math.order(lhs.blue_bits, rhs.blue_bits);
    if (order != .eq) return order;
    return std.math.order(lhs.refresh_rate, rhs.refresh_rate);
}
