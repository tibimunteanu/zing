const std = @import("std");
const x11 = @import("types.zig");

pub const ContentScale = extern struct { x_scale: f32, y_scale: f32 };
pub const Pos = extern struct { x: i32, y: i32 };
pub const Size = extern struct { width: u32, height: u32 };
pub const VideoMode = extern struct { width: u32, height: u32, red_bits: u32, green_bits: u32, blue_bits: u32, refresh_rate: u32 };
pub const WorkArea = extern struct { x: i32, y: i32, width: u32, height: u32 };

const RR_Connected = 0;
const RR_Rotate_90 = 2;
const RR_Rotate_270 = 8;
const RR_Interlace = 1 << 4;
const RRNotify = 1;
const RROutputChangeNotifyMask = 1 << 2;
const max_monitors = 16;

const RROutput = c_ulong;
const RRCrtc = c_ulong;
const RRMode = c_ulong;
const Rotation = c_ushort;

const XRRModeInfo = extern struct {
    id: RRMode,
    width: c_uint,
    height: c_uint,
    dot_clock: c_ulong,
    h_sync_start: c_uint,
    h_sync_end: c_uint,
    h_total: c_uint,
    h_skew: c_uint,
    v_sync_start: c_uint,
    v_sync_end: c_uint,
    v_total: c_uint,
    name: ?[*]u8,
    name_length: c_uint,
    mode_flags: c_ulong,
};

const XRRScreenResources = extern struct {
    timestamp: x11.Time,
    config_timestamp: x11.Time,
    ncrtc: c_int,
    crtcs: [*]RRCrtc,
    noutput: c_int,
    outputs: [*]RROutput,
    nmode: c_int,
    modes: [*]XRRModeInfo,
};

const XRROutputInfo = extern struct {
    timestamp: x11.Time,
    crtc: RRCrtc,
    name: [*]u8,
    name_len: c_int,
    mm_width: c_ulong,
    mm_height: c_ulong,
    connection: c_int,
    subpixel_order: c_int,
    ncrtc: c_int,
    crtcs: [*]RRCrtc,
    nclone: c_int,
    clones: [*]RROutput,
    nmode: c_int,
    npreferred: c_int,
    modes: [*]RRMode,
};

const XRRCrtcInfo = extern struct {
    timestamp: x11.Time,
    x: c_int,
    y: c_int,
    width: c_uint,
    height: c_uint,
    mode: RRMode,
    rotation: Rotation,
    noutput: c_int,
    outputs: [*]RROutput,
    rotations: Rotation,
    npossible: c_int,
    possible: [*]RROutput,
};

const XRandR = struct {
    lib: std.DynLib,
    configured: bool = false,
    available: bool = false,
    monitor_broken: bool = false,
    event_base: c_int = 0,
    error_base: c_int = 0,
    major: c_int = 0,
    minor: c_int = 0,
    XRRGetScreenResourcesCurrent: *const fn (*x11.Display, x11.Window) callconv(.c) ?*XRRScreenResources,
    XRRFreeScreenResources: *const fn (*XRRScreenResources) callconv(.c) void,
    XRRGetOutputInfo: *const fn (*x11.Display, *XRRScreenResources, RROutput) callconv(.c) ?*XRROutputInfo,
    XRRFreeOutputInfo: *const fn (*XRROutputInfo) callconv(.c) void,
    XRRGetCrtcInfo: *const fn (*x11.Display, *XRRScreenResources, RRCrtc) callconv(.c) ?*XRRCrtcInfo,
    XRRFreeCrtcInfo: *const fn (*XRRCrtcInfo) callconv(.c) void,
    XRRGetOutputPrimary: *const fn (*x11.Display, x11.Window) callconv(.c) RROutput,
    XRRQueryExtension: *const fn (*x11.Display, *c_int, *c_int) callconv(.c) x11.Bool,
    XRRQueryVersion: *const fn (*x11.Display, *c_int, *c_int) callconv(.c) x11.Status,
    XRRSelectInput: *const fn (*x11.Display, x11.Window, c_int) callconv(.c) void,
    XRRSetCrtcConfig: *const fn (*x11.Display, *XRRScreenResources, RRCrtc, x11.Time, c_int, c_int, RRMode, Rotation, [*]RROutput, c_int) callconv(.c) c_int,
    XRRUpdateConfiguration: *const fn (*x11.XEvent) callconv(.c) c_int,
};

const XineramaScreenInfo = extern struct {
    screen_number: c_int,
    x_org: c_short,
    y_org: c_short,
    width: c_short,
    height: c_short,
};

const Xinerama = struct {
    lib: std.DynLib,
    configured: bool = false,
    available: bool = false,
    major: c_int = 0,
    minor: c_int = 0,
    XineramaIsActive: *const fn (*x11.Display) callconv(.c) x11.Bool,
    XineramaQueryExtension: *const fn (*x11.Display, *c_int, *c_int) callconv(.c) x11.Bool,
    XineramaQueryScreens: *const fn (*x11.Display, *c_int) callconv(.c) ?[*]XineramaScreenInfo,
};

const XineramaScreens = struct {
    ptr: ?[*]XineramaScreenInfo = null,
    items: []const XineramaScreenInfo = &.{},
};

const Monitor = struct {
    connected: bool = false,
    output: RROutput = 0,
    crtc: RRCrtc = 0,
    rotation: Rotation = 0,
    name: [128:0]u8 = initName(),
    pos: Pos = .{ .x = 0, .y = 0 },
    size: Size = .{ .width = 0, .height = 0 },
    physical: Size = .{ .width = 0, .height = 0 },
    mode: VideoMode = .{ .width = 0, .height = 0, .red_bits = 8, .green_bits = 8, .blue_bits = 8, .refresh_rate = 60 },
    old_mode: RRMode = 0,
    old_x: c_int = 0,
    old_y: c_int = 0,
    old_rotation: Rotation = 0,
    window: ?*anyopaque = null,
    xinerama_index: c_int = 0,
};

var xrandr: ?XRandR = null;
var xinerama: ?Xinerama = null;
var monitors: [max_monitors]Monitor = @splat(.{});
var monitor_order: [max_monitors]usize = @splat(0);
var monitor_count: u32 = 0;

pub fn init() bool {
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
    return @ptrCast(&monitors[monitor_order[index]]);
}

pub fn indexOf(handle: *anyopaque) u32 {
    const monitor = native(handle);
    var index: u32 = 0;
    while (index < monitor_count) : (index += 1) {
        if (&monitors[monitor_order[index]] == monitor) return index;
    }
    return 0;
}

pub fn fullscreenIndex(handle: *anyopaque) c_int {
    return native(handle).xinerama_index;
}

pub fn adapter(handle: *anyopaque) usize {
    return @intCast(native(handle).crtc);
}

pub fn monitorOutput(handle: *anyopaque) usize {
    return @intCast(native(handle).output);
}

pub fn xineramaAvailable() bool {
    const lib = loadXinerama() orelse return false;
    configureXinerama(lib);
    return lib.available;
}

pub fn window(handle: *anyopaque) ?*anyopaque {
    return native(handle).window;
}

pub fn setWindow(handle: *anyopaque, value: ?*anyopaque) void {
    native(handle).window = value;
}

pub fn getPos(handle: *anyopaque) Pos {
    const monitor = native(handle);
    const display = x11.display orelse return monitor.pos;
    const lib = loadRandr() orelse return monitor.pos;
    configureRandr(lib);
    if (!lib.available or lib.monitor_broken or monitor.crtc == 0) return monitor.pos;

    const resources = lib.XRRGetScreenResourcesCurrent(display, x11.root) orelse return monitor.pos;
    defer lib.XRRFreeScreenResources(resources);
    const crtc_info = lib.XRRGetCrtcInfo(display, resources, monitor.crtc) orelse return monitor.pos;
    defer lib.XRRFreeCrtcInfo(crtc_info);

    monitor.pos = .{ .x = crtc_info.x, .y = crtc_info.y };
    return monitor.pos;
}

pub fn getWorkArea(handle: *anyopaque) WorkArea {
    const pos = getPos(handle);
    const mode = getVideoMode(handle);
    var area_x = pos.x;
    var area_y = pos.y;
    var area_width: i32 = @intCast(mode.width);
    var area_height: i32 = @intCast(mode.height);

    const display = x11.display orelse return makeWorkArea(area_x, area_y, area_width, area_height);
    const xlib = &(x11.xlib orelse return makeWorkArea(area_x, area_y, area_width, area_height));

    if (x11.net_workarea != 0 and x11.net_current_desktop != 0) {
        var actual_type: x11.Atom = 0;
        var actual_format: c_int = 0;
        var extent_count: c_ulong = 0;
        var bytes_after: c_ulong = 0;
        var extents: ?[*]u8 = null;
        _ = xlib.XGetWindowProperty(
            display,
            x11.root,
            x11.net_workarea,
            0,
            std.math.maxInt(c_long),
            0,
            x11.XA_CARDINAL,
            &actual_type,
            &actual_format,
            &extent_count,
            &bytes_after,
            &extents,
        );
        defer {
            if (extents) |ptr| _ = xlib.XFree(@ptrCast(ptr));
        }

        var desktop_type: x11.Atom = 0;
        var desktop_format: c_int = 0;
        var desktop_count: c_ulong = 0;
        var desktop_bytes_after: c_ulong = 0;
        var desktop_data: ?[*]u8 = null;
        _ = xlib.XGetWindowProperty(
            display,
            x11.root,
            x11.net_current_desktop,
            0,
            1,
            0,
            x11.XA_CARDINAL,
            &desktop_type,
            &desktop_format,
            &desktop_count,
            &desktop_bytes_after,
            &desktop_data,
        );
        defer {
            if (desktop_data) |ptr| _ = xlib.XFree(@ptrCast(ptr));
        }

        if (extents != null and desktop_data != null and
            actual_type == x11.XA_CARDINAL and actual_format == 32 and extent_count >= 4 and
            desktop_type == x11.XA_CARDINAL and desktop_format == 32 and desktop_count > 0)
        {
            const desktop: [*]c_ulong = @ptrCast(@alignCast(desktop_data.?));
            const desktop_index: usize = @intCast(desktop[0]);
            if (desktop_index < extent_count / 4) {
                const values: [*]c_ulong = @ptrCast(@alignCast(extents.?));
                const offset = desktop_index * 4;
                const global_x: i32 = @intCast(values[offset + 0]);
                const global_y: i32 = @intCast(values[offset + 1]);
                const global_width: i32 = @intCast(values[offset + 2]);
                const global_height: i32 = @intCast(values[offset + 3]);

                if (area_x < global_x) {
                    area_width -= global_x - area_x;
                    area_x = global_x;
                }

                if (area_y < global_y) {
                    area_height -= global_y - area_y;
                    area_y = global_y;
                }

                if (area_x + area_width > global_x + global_width) {
                    area_width = global_x - area_x + global_width;
                }

                if (area_y + area_height > global_y + global_height) {
                    area_height = global_y - area_y + global_height;
                }
            }
        }
    }

    return makeWorkArea(area_x, area_y, area_width, area_height);
}

pub fn getContentScale(_: *anyopaque) ContentScale {
    return .{ .x_scale = x11.content_scale_x, .y_scale = x11.content_scale_y };
}

fn makeWorkArea(x: i32, y: i32, width: i32, height: i32) WorkArea {
    return .{
        .x = x,
        .y = y,
        .width = @intCast(@max(0, width)),
        .height = @intCast(@max(0, height)),
    };
}

pub fn getPhysicalSize(handle: *anyopaque) Size {
    return native(handle).physical;
}

pub fn getName(handle: *anyopaque) [*:0]const u8 {
    return &native(handle).name;
}

pub fn getVideoMode(handle: *anyopaque) VideoMode {
    const monitor = native(handle);
    const display = x11.display orelse return monitor.mode;
    const lib = loadRandr() orelse return fallbackVideoMode(monitor);
    configureRandr(lib);
    if (!lib.available or lib.monitor_broken or monitor.crtc == 0) return fallbackVideoMode(monitor);

    const resources = lib.XRRGetScreenResourcesCurrent(display, x11.root) orelse return monitor.mode;
    defer lib.XRRFreeScreenResources(resources);
    const crtc_info = lib.XRRGetCrtcInfo(display, resources, monitor.crtc) orelse return monitor.mode;
    defer lib.XRRFreeCrtcInfo(crtc_info);
    const mode_info = getModeInfo(resources, crtc_info.mode) orelse return monitor.mode;

    monitor.mode = videoModeFromMode(mode_info, crtc_info.rotation);
    return monitor.mode;
}

pub fn getVideoModes(handle: *anyopaque, out_modes: [*]VideoMode, max_modes: u32) u32 {
    if (max_modes == 0) return 0;
    const monitor = native(handle);
    const display = x11.display orelse {
        out_modes[0] = fallbackVideoMode(monitor);
        return 1;
    };
    const lib = loadRandr() orelse {
        out_modes[0] = fallbackVideoMode(monitor);
        return 1;
    };
    configureRandr(lib);
    if (!lib.available or lib.monitor_broken) {
        out_modes[0] = fallbackVideoMode(monitor);
        return 1;
    }
    if (monitor.output == 0 or monitor.crtc == 0) {
        out_modes[0] = fallbackVideoMode(monitor);
        return 1;
    }

    const resources = lib.XRRGetScreenResourcesCurrent(display, x11.root) orelse return 0;
    defer lib.XRRFreeScreenResources(resources);
    const crtc_info = lib.XRRGetCrtcInfo(display, resources, monitor.crtc) orelse return 0;
    defer lib.XRRFreeCrtcInfo(crtc_info);
    const output_info = lib.XRRGetOutputInfo(display, resources, monitor.output) orelse return 0;
    defer lib.XRRFreeOutputInfo(output_info);

    var count_out: u32 = 0;
    for (output_info.modes[0..@intCast(output_info.nmode)]) |mode_id| {
        const mode_info = getModeInfo(resources, mode_id) orelse continue;
        if (!modeIsGood(mode_info)) continue;
        const mode = videoModeFromMode(mode_info, crtc_info.rotation);
        if (containsMode(out_modes[0..count_out], mode)) continue;
        out_modes[count_out] = mode;
        count_out += 1;
        if (count_out == max_modes) break;
    }
    return count_out;
}

pub fn free(_: *anyopaque) void {}

pub fn setVideoMode(handle: *anyopaque, desired: VideoMode) bool {
    const monitor = native(handle);
    const display = x11.display orelse return false;
    const lib = loadRandr() orelse return false;
    configureRandr(lib);
    if (!lib.available or lib.monitor_broken) return true;
    if (monitor.output == 0 or monitor.crtc == 0) return true;

    const resources = lib.XRRGetScreenResourcesCurrent(display, x11.root) orelse return false;
    defer lib.XRRFreeScreenResources(resources);
    const crtc_info = lib.XRRGetCrtcInfo(display, resources, monitor.crtc) orelse return false;
    defer lib.XRRFreeCrtcInfo(crtc_info);
    const output_info = lib.XRRGetOutputInfo(display, resources, monitor.output) orelse return false;
    defer lib.XRRFreeOutputInfo(output_info);

    var native_mode: RRMode = 0;
    const selected_mode = chooseVideoMode(resources, crtc_info, output_info, desired) orelse return false;
    const current_mode = videoModeFromMode(getModeInfo(resources, crtc_info.mode) orelse return false, crtc_info.rotation);
    if (compareVideoModes(current_mode, selected_mode) == .eq) return true;

    for (output_info.modes[0..@intCast(output_info.nmode)]) |mode_id| {
        const mode_info = getModeInfo(resources, mode_id) orelse continue;
        if (!modeIsGood(mode_info)) continue;
        const mode = videoModeFromMode(mode_info, crtc_info.rotation);
        if (compareVideoModes(selected_mode, mode) == .eq) {
            native_mode = mode_info.id;
            break;
        }
    }
    if (native_mode == 0) return false;

    if (monitor.old_mode == 0) {
        monitor.old_mode = crtc_info.mode;
        monitor.old_x = crtc_info.x;
        monitor.old_y = crtc_info.y;
        monitor.old_rotation = crtc_info.rotation;
    }

    const status = lib.XRRSetCrtcConfig(
        display,
        resources,
        monitor.crtc,
        x11.CurrentTime,
        crtc_info.x,
        crtc_info.y,
        native_mode,
        crtc_info.rotation,
        crtc_info.outputs,
        crtc_info.noutput,
    );
    if (status != 0) return false;
    monitor.mode = selected_mode;
    return true;
}

pub fn restoreVideoMode(handle: *anyopaque) void {
    const monitor = native(handle);
    if (monitor.old_mode == 0) return;
    const display = x11.display orelse return;
    const lib = loadRandr() orelse return;
    const resources = lib.XRRGetScreenResourcesCurrent(display, x11.root) orelse return;
    defer lib.XRRFreeScreenResources(resources);
    const crtc_info = lib.XRRGetCrtcInfo(display, resources, monitor.crtc) orelse return;
    defer lib.XRRFreeCrtcInfo(crtc_info);

    _ = lib.XRRSetCrtcConfig(
        display,
        resources,
        monitor.crtc,
        x11.CurrentTime,
        monitor.old_x,
        monitor.old_y,
        monitor.old_mode,
        monitor.old_rotation,
        crtc_info.outputs,
        crtc_info.noutput,
    );
    monitor.old_mode = 0;
}

pub fn refresh() void {
    for (&monitors) |*monitor| monitor.connected = false;
    monitor_count = 0;
    if (!refreshRandr()) refreshFallback();
}

pub fn handleEvent(event: *x11.XEvent) bool {
    const lib = loadRandr() orelse return false;
    configureRandr(lib);
    if (!lib.available or lib.monitor_broken) return false;
    if (event.type != lib.event_base + RRNotify) return false;

    _ = lib.XRRUpdateConfiguration(event);
    refresh();
    return true;
}

fn refreshRandr() bool {
    const display = x11.display orelse return false;
    const lib = loadRandr() orelse return false;
    configureRandr(lib);
    if (!lib.available or lib.monitor_broken) return false;

    const resources = lib.XRRGetScreenResourcesCurrent(display, x11.root) orelse return false;
    defer lib.XRRFreeScreenResources(resources);
    const primary = lib.XRRGetOutputPrimary(display, x11.root);
    const screens = queryXineramaScreens();
    defer freeXineramaScreens(screens.ptr);

    var primary_index: ?usize = null;
    for (resources.outputs[0..@intCast(resources.noutput)]) |output| {
        const output_info = lib.XRRGetOutputInfo(display, resources, output) orelse continue;
        defer lib.XRRFreeOutputInfo(output_info);
        if (output_info.connection != RR_Connected or output_info.crtc == 0) continue;

        const crtc_info = lib.XRRGetCrtcInfo(display, resources, output_info.crtc) orelse continue;
        defer lib.XRRFreeCrtcInfo(crtc_info);

        const monitor_index = updateMonitorFromRandr(resources, output, output_info, crtc_info, screens.items) orelse continue;
        if (output == primary) {
            primary_index = monitor_index;
        } else {
            appendMonitorIndex(monitor_index);
        }
    }

    if (primary_index) |index| {
        if (monitor_count < max_monitors) {
            std.mem.copyBackwards(usize, monitor_order[1 .. monitor_count + 1], monitor_order[0..monitor_count]);
            monitor_order[0] = index;
            monitor_count += 1;
        }
    }

    return monitor_count != 0;
}

fn queryXineramaScreens() XineramaScreens {
    const display = x11.display orelse return .{};
    const lib = loadXinerama() orelse return .{};
    configureXinerama(lib);
    if (!lib.available) return .{};

    var screen_count: c_int = 0;
    const screens = lib.XineramaQueryScreens(display, &screen_count) orelse return .{};
    if (screen_count <= 0) {
        freeXineramaScreens(screens);
        return .{};
    }

    return .{
        .ptr = screens,
        .items = screens[0..@intCast(screen_count)],
    };
}

fn freeXineramaScreens(screens: ?[*]XineramaScreenInfo) void {
    if (screens) |ptr| {
        if (x11.xlib) |lib| _ = lib.XFree(@ptrCast(ptr));
    }
}

fn updateMonitorFromRandr(resources: *XRRScreenResources, output: RROutput, output_info: *XRROutputInfo, crtc_info: *XRRCrtcInfo, screens: []const XineramaScreenInfo) ?usize {
    const index = findMonitorSlot(output) orelse return null;
    const old_mode = monitors[index].old_mode;
    const old_x = monitors[index].old_x;
    const old_y = monitors[index].old_y;
    const old_rotation = monitors[index].old_rotation;
    const old_window = monitors[index].window;
    monitors[index] = monitorFromRandr(resources, output, output_info, crtc_info, screens);
    monitors[index].connected = true;
    monitors[index].old_mode = old_mode;
    monitors[index].old_x = old_x;
    monitors[index].old_y = old_y;
    monitors[index].old_rotation = old_rotation;
    monitors[index].window = old_window;
    return index;
}

fn findMonitorSlot(output: RROutput) ?usize {
    for (&monitors, 0..) |*monitor, index| {
        if (monitor.output == output) return index;
    }
    for (&monitors, 0..) |*monitor, index| {
        if (!monitor.connected) return index;
    }
    return null;
}

fn monitorFromRandr(resources: *XRRScreenResources, output: RROutput, output_info: *XRROutputInfo, crtc_info: *XRRCrtcInfo, screens: []const XineramaScreenInfo) Monitor {
    var monitor = Monitor{
        .connected = true,
        .output = output,
        .crtc = output_info.crtc,
        .rotation = crtc_info.rotation,
        .pos = .{ .x = crtc_info.x, .y = crtc_info.y },
        .size = .{ .width = crtc_info.width, .height = crtc_info.height },
    };

    for (screens, 0..) |screen, index| {
        if (screen.x_org == crtc_info.x and
            screen.y_org == crtc_info.y and
            @as(c_int, screen.width) == @as(c_int, @intCast(crtc_info.width)) and
            @as(c_int, screen.height) == @as(c_int, @intCast(crtc_info.height)))
        {
            monitor.xinerama_index = @intCast(index);
            break;
        }
    }

    const name_len: usize = @min(@as(usize, @intCast(output_info.name_len)), monitor.name.len - 1);
    @memset(&monitor.name, 0);
    @memcpy(monitor.name[0..name_len], output_info.name[0..name_len]);

    const rotated = crtc_info.rotation == RR_Rotate_90 or crtc_info.rotation == RR_Rotate_270;
    const width_mm = if (rotated) output_info.mm_height else output_info.mm_width;
    const height_mm = if (rotated) output_info.mm_width else output_info.mm_height;
    monitor.physical = if (width_mm > 0 and height_mm > 0) .{
        .width = @intCast(width_mm),
        .height = @intCast(height_mm),
    } else .{
        .width = @intFromFloat(@as(f32, @floatFromInt(crtc_info.width)) * 25.4 / 96.0),
        .height = @intFromFloat(@as(f32, @floatFromInt(crtc_info.height)) * 25.4 / 96.0),
    };

    if (getModeInfo(resources, crtc_info.mode)) |mode_info| {
        monitor.mode = videoModeFromMode(mode_info, crtc_info.rotation);
    } else {
        const bpp = splitDefaultBpp();
        monitor.mode = .{
            .width = crtc_info.width,
            .height = crtc_info.height,
            .red_bits = bpp.red,
            .green_bits = bpp.green,
            .blue_bits = bpp.blue,
            .refresh_rate = 0,
        };
    }

    return monitor;
}

fn refreshFallback() void {
    const display = x11.display orelse return;
    const xlib = &(x11.xlib orelse return);
    var monitor = Monitor{};
    monitor.connected = true;
    monitor.size = .{
        .width = @intCast(@max(1, xlib.XDisplayWidth(display, x11.screen))),
        .height = @intCast(@max(1, xlib.XDisplayHeight(display, x11.screen))),
    };
    monitor.physical = .{
        .width = @intCast(@max(1, xlib.XDisplayWidthMM(display, x11.screen))),
        .height = @intCast(@max(1, xlib.XDisplayHeightMM(display, x11.screen))),
    };
    monitor.mode = fallbackVideoMode(&monitor);
    monitors[0] = monitor;
    monitor_order[0] = 0;
    monitor_count = 1;
}

fn appendMonitorIndex(index: usize) void {
    if (monitor_count >= max_monitors) return;
    monitor_order[monitor_count] = index;
    monitor_count += 1;
}

fn getModeInfo(resources: *XRRScreenResources, id: RRMode) ?*XRRModeInfo {
    for (resources.modes[0..@intCast(resources.nmode)]) |*mode| {
        if (mode.id == id) return mode;
    }
    return null;
}

fn fallbackVideoMode(monitor: *const Monitor) VideoMode {
    const display = x11.display orelse {
        const bpp = splitDefaultBpp();
        return .{ .width = monitor.size.width, .height = monitor.size.height, .red_bits = bpp.red, .green_bits = bpp.green, .blue_bits = bpp.blue, .refresh_rate = 0 };
    };
    const xlib = &(x11.xlib orelse {
        const bpp = splitDefaultBpp();
        return .{ .width = monitor.size.width, .height = monitor.size.height, .red_bits = bpp.red, .green_bits = bpp.green, .blue_bits = bpp.blue, .refresh_rate = 0 };
    });
    const bpp = splitDefaultBpp();
    return .{
        .width = @intCast(@max(1, xlib.XDisplayWidth(display, x11.screen))),
        .height = @intCast(@max(1, xlib.XDisplayHeight(display, x11.screen))),
        .red_bits = bpp.red,
        .green_bits = bpp.green,
        .blue_bits = bpp.blue,
        .refresh_rate = 0,
    };
}

fn videoModeFromMode(mode: *const XRRModeInfo, rotation: Rotation) VideoMode {
    const rotated = rotation == RR_Rotate_90 or rotation == RR_Rotate_270;
    const bpp = splitDefaultBpp();
    return .{
        .width = if (rotated) mode.height else mode.width,
        .height = if (rotated) mode.width else mode.height,
        .red_bits = bpp.red,
        .green_bits = bpp.green,
        .blue_bits = bpp.blue,
        .refresh_rate = calculateRefreshRate(mode),
    };
}

fn calculateRefreshRate(mode: *const XRRModeInfo) u32 {
    if ((mode.mode_flags & RR_Interlace) != 0) return 0;
    if (mode.h_total == 0 or mode.v_total == 0) return 0;
    const rate = @as(f64, @floatFromInt(mode.dot_clock)) / (@as(f64, @floatFromInt(mode.h_total)) * @as(f64, @floatFromInt(mode.v_total)));
    return @intFromFloat(@round(rate));
}

fn modeIsGood(mode: *const XRRModeInfo) bool {
    return (mode.mode_flags & RR_Interlace) == 0;
}

fn containsMode(modes: []const VideoMode, mode: VideoMode) bool {
    for (modes) |candidate| {
        if (candidate.width == mode.width and
            candidate.height == mode.height and
            candidate.red_bits == mode.red_bits and
            candidate.green_bits == mode.green_bits and
            candidate.blue_bits == mode.blue_bits and
            candidate.refresh_rate == mode.refresh_rate)
        {
            return true;
        }
    }
    return false;
}

fn chooseVideoMode(resources: *XRRScreenResources, crtc_info: *XRRCrtcInfo, output_info: *XRROutputInfo, desired: VideoMode) ?VideoMode {
    var closest: ?VideoMode = null;
    var least_size_diff: u64 = std.math.maxInt(u64);
    var least_rate_diff: u64 = std.math.maxInt(u64);
    var least_color_diff: u64 = std.math.maxInt(u64);

    for (output_info.modes[0..@intCast(output_info.nmode)]) |mode_id| {
        const mode_info = getModeInfo(resources, mode_id) orelse continue;
        if (!modeIsGood(mode_info)) continue;
        const mode = videoModeFromMode(mode_info, crtc_info.rotation);

        const color_diff =
            absDiff(mode.red_bits, desired.red_bits) +
            absDiff(mode.green_bits, desired.green_bits) +
            absDiff(mode.blue_bits, desired.blue_bits);
        const width_diff = absDiff(mode.width, desired.width);
        const height_diff = absDiff(mode.height, desired.height);
        const size_diff = width_diff * width_diff + height_diff * height_diff;
        const rate_diff = if (desired.refresh_rate != 0)
            absDiff(mode.refresh_rate, desired.refresh_rate)
        else
            @as(u64, std.math.maxInt(u32) - mode.refresh_rate);

        if (color_diff < least_color_diff or
            (color_diff == least_color_diff and size_diff < least_size_diff) or
            (color_diff == least_color_diff and size_diff == least_size_diff and rate_diff < least_rate_diff))
        {
            closest = mode;
            least_size_diff = size_diff;
            least_rate_diff = rate_diff;
            least_color_diff = color_diff;
        }
    }

    return closest;
}

fn compareVideoModes(lhs: VideoMode, rhs: VideoMode) std.math.Order {
    const lhs_bpp = lhs.red_bits + lhs.green_bits + lhs.blue_bits;
    const rhs_bpp = rhs.red_bits + rhs.green_bits + rhs.blue_bits;
    if (lhs_bpp != rhs_bpp) return std.math.order(lhs_bpp, rhs_bpp);

    const lhs_area = lhs.width * lhs.height;
    const rhs_area = rhs.width * rhs.height;
    if (lhs_area != rhs_area) return std.math.order(lhs_area, rhs_area);

    if (lhs.width != rhs.width) return std.math.order(lhs.width, rhs.width);
    return std.math.order(lhs.refresh_rate, rhs.refresh_rate);
}

fn absDiff(lhs: u32, rhs: u32) u64 {
    return if (lhs > rhs) lhs - rhs else rhs - lhs;
}

const Bpp = struct { red: u32, green: u32, blue: u32 };

fn splitDefaultBpp() Bpp {
    const display = x11.display orelse return .{ .red = 8, .green = 8, .blue = 8 };
    const xlib = &(x11.xlib orelse return .{ .red = 8, .green = 8, .blue = 8 });
    var bpp: u32 = @intCast(@max(0, xlib.XDefaultDepth(display, x11.screen)));
    if (bpp == 32) bpp = 24;

    var red = bpp / 3;
    var green = red;
    const blue = red;
    const delta = bpp - red * 3;
    if (delta >= 1) green += 1;
    if (delta == 2) red += 1;
    return .{ .red = red, .green = green, .blue = blue };
}

fn native(handle: *anyopaque) *Monitor {
    return @ptrCast(@alignCast(handle));
}

fn initName() [128:0]u8 {
    var name: [128:0]u8 = @splat(0);
    @memcpy(name[0.."Display".len], "Display");
    return name;
}

fn loadRandr() ?*XRandR {
    if (xrandr != null) return &xrandr.?;
    var lib = std.DynLib.open("libXrandr.so.2") catch std.DynLib.open("libXrandr.so") catch return null;
    errdefer lib.close();
    xrandr = .{
        .lib = lib,
        .XRRGetScreenResourcesCurrent = lookupRandr(&lib, "XRRGetScreenResourcesCurrent") orelse return null,
        .XRRFreeScreenResources = lookupRandr(&lib, "XRRFreeScreenResources") orelse return null,
        .XRRGetOutputInfo = lookupRandr(&lib, "XRRGetOutputInfo") orelse return null,
        .XRRFreeOutputInfo = lookupRandr(&lib, "XRRFreeOutputInfo") orelse return null,
        .XRRGetCrtcInfo = lookupRandr(&lib, "XRRGetCrtcInfo") orelse return null,
        .XRRFreeCrtcInfo = lookupRandr(&lib, "XRRFreeCrtcInfo") orelse return null,
        .XRRGetOutputPrimary = lookupRandr(&lib, "XRRGetOutputPrimary") orelse return null,
        .XRRQueryExtension = lookupRandr(&lib, "XRRQueryExtension") orelse return null,
        .XRRQueryVersion = lookupRandr(&lib, "XRRQueryVersion") orelse return null,
        .XRRSelectInput = lookupRandr(&lib, "XRRSelectInput") orelse return null,
        .XRRSetCrtcConfig = lookupRandr(&lib, "XRRSetCrtcConfig") orelse return null,
        .XRRUpdateConfiguration = lookupRandr(&lib, "XRRUpdateConfiguration") orelse return null,
    };
    return &xrandr.?;
}

fn loadXinerama() ?*Xinerama {
    if (xinerama != null) return &xinerama.?;
    var lib = std.DynLib.open("libXinerama-1.so") catch
        std.DynLib.open("libXinerama.so") catch
        std.DynLib.open("libXinerama.so.1") catch return null;
    errdefer lib.close();
    xinerama = .{
        .lib = lib,
        .XineramaIsActive = lookupXinerama(&lib, "XineramaIsActive") orelse return null,
        .XineramaQueryExtension = lookupXinerama(&lib, "XineramaQueryExtension") orelse return null,
        .XineramaQueryScreens = lookupXinerama(&lib, "XineramaQueryScreens") orelse return null,
    };
    return &xinerama.?;
}

fn configureRandr(lib: *XRandR) void {
    if (lib.configured) return;
    lib.configured = true;

    const display = x11.display orelse return;
    if (lib.XRRQueryExtension(display, &lib.event_base, &lib.error_base) == 0) return;
    if (lib.XRRQueryVersion(display, &lib.major, &lib.minor) == 0) return;

    lib.available = lib.major > 1 or (lib.major == 1 and lib.minor >= 3);
    if (!lib.available) return;

    const resources = lib.XRRGetScreenResourcesCurrent(display, x11.root) orelse {
        lib.monitor_broken = true;
        return;
    };
    defer lib.XRRFreeScreenResources(resources);

    if (resources.ncrtc == 0) {
        lib.monitor_broken = true;
        return;
    }

    lib.XRRSelectInput(display, x11.root, RROutputChangeNotifyMask);
}

fn configureXinerama(lib: *Xinerama) void {
    if (lib.configured) return;
    lib.configured = true;

    const display = x11.display orelse return;
    if (lib.XineramaQueryExtension(display, &lib.major, &lib.minor) == 0) return;
    lib.available = lib.XineramaIsActive(display) != 0;
}

fn lookupRandr(lib: *std.DynLib, comptime name: [:0]const u8) ?@TypeOf(@field(@as(XRandR, undefined), name)) {
    return lib.lookup(@TypeOf(@field(@as(XRandR, undefined), name)), name);
}

fn lookupXinerama(lib: *std.DynLib, comptime name: [:0]const u8) ?@TypeOf(@field(@as(Xinerama, undefined), name)) {
    return lib.lookup(@TypeOf(@field(@as(Xinerama, undefined), name)), name);
}
