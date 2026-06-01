const std = @import("std");
const win = @import("types.zig");

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
    handle: win.HMONITOR,
    device_name: [32:0]win.WCHAR,
    display_name: [32:0]win.WCHAR = @splat(0),
    public_name: [128:0]u8,
    pos: Pos,
    size: Size,
    modes_pruned: bool = false,
    mode_changed: bool = false,
};

const BppSplit = struct {
    red: u32,
    green: u32,
    blue: u32,
};

var monitors: [32]Monitor = undefined;
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
    return @ptrCast(&monitors[index]);
}

pub fn getPos(handle: *anyopaque) Pos {
    const monitor = native(handle);
    if (monitor.handle == null) return monitor.pos;
    var info: win.MONITORINFO = .{};
    if (win.GetMonitorInfoW(monitor.handle, &info) != 0)
        return .{ .x = info.rcMonitor.left, .y = info.rcMonitor.top };
    return monitor.pos;
}

pub fn getWorkArea(handle: *anyopaque) WorkArea {
    const monitor = native(handle);
    if (monitor.handle == null) {
        return .{ .x = monitor.pos.x, .y = monitor.pos.y, .width = monitor.size.width, .height = monitor.size.height };
    }
    var info: win.MONITORINFO = .{};
    if (win.GetMonitorInfoW(monitor.handle, &info) != 0) {
        return .{
            .x = info.rcWork.left,
            .y = info.rcWork.top,
            .width = @intCast(info.rcWork.right - info.rcWork.left),
            .height = @intCast(info.rcWork.bottom - info.rcWork.top),
        };
    }
    return .{ .x = monitor.pos.x, .y = monitor.pos.y, .width = monitor.size.width, .height = monitor.size.height };
}

pub fn getContentScale(handle: *anyopaque) ContentScale {
    const monitor = native(handle);
    var xdpi: win.UINT = 0;
    var ydpi: win.UINT = 0;

    if (monitor.handle != null) {
        if (win.get_dpi_for_monitor) |get_dpi| {
            if (get_dpi(monitor.handle, win.MDT_EFFECTIVE_DPI, &xdpi, &ydpi) == win.S_OK) {
                return .{
                    .x_scale = @as(f32, @floatFromInt(xdpi)) / @as(f32, @floatFromInt(win.USER_DEFAULT_SCREEN_DPI)),
                    .y_scale = @as(f32, @floatFromInt(ydpi)) / @as(f32, @floatFromInt(win.USER_DEFAULT_SCREEN_DPI)),
                };
            }
        }
    }

    const dc = win.GetDC(null);
    defer _ = win.ReleaseDC(null, dc);
    xdpi = @intCast(win.GetDeviceCaps(dc, win.LOGPIXELSX));
    ydpi = @intCast(win.GetDeviceCaps(dc, win.LOGPIXELSY));
    return .{
        .x_scale = @as(f32, @floatFromInt(xdpi)) / @as(f32, @floatFromInt(win.USER_DEFAULT_SCREEN_DPI)),
        .y_scale = @as(f32, @floatFromInt(ydpi)) / @as(f32, @floatFromInt(win.USER_DEFAULT_SCREEN_DPI)),
    };
}

pub fn getPhysicalSize(handle: *anyopaque) Size {
    const monitor = native(handle);
    const dc = win.CreateDCW(std.unicode.utf8ToUtf16LeStringLiteral("DISPLAY").ptr, deviceNameOrNull(monitor), null, null);
    defer {
        if (dc != null) _ = win.DeleteDC(dc);
    }

    if (dc == null) return monitor.size;

    return .{
        .width = @intCast(@max(0, win.GetDeviceCaps(dc, win.HORZSIZE))),
        .height = @intCast(@max(0, win.GetDeviceCaps(dc, win.VERTSIZE))),
    };
}

pub fn getName(handle: *anyopaque) [*:0]const u8 {
    return &native(handle).public_name;
}

pub fn getVideoMode(handle: *anyopaque) VideoMode {
    const monitor = native(handle);
    var mode: win.DEVMODEW = .{};
    if (win.EnumDisplaySettingsW(deviceNameOrNull(monitor), win.ENUM_CURRENT_SETTINGS, &mode) == 0) {
        return .{ .width = 0, .height = 0, .red_bits = 0, .green_bits = 0, .blue_bits = 0, .refresh_rate = 0 };
    }
    return videoModeFromDevMode(mode);
}

pub fn getVideoModes(handle: *anyopaque, out_modes: [*]VideoMode, max_modes: u32) u32 {
    const monitor = native(handle);
    var result_count: u32 = 0;
    var mode_index: u32 = 0;
    while (result_count < max_modes) : (mode_index += 1) {
        var mode: win.DEVMODEW = .{};
        if (win.EnumDisplaySettingsW(deviceNameOrNull(monitor), mode_index, &mode) == 0) break;
        if (mode.dmBitsPerPel < 15) continue;

        const converted = videoModeFromDevMode(mode);
        var duplicate = false;
        for (out_modes[0..result_count]) |existing| {
            if (compareVideoModes(existing, converted) == .eq) {
                duplicate = true;
                break;
            }
        }
        if (duplicate) continue;

        if (monitor.modes_pruned and
            win.ChangeDisplaySettingsExW(deviceNameOrNull(monitor), &mode, null, win.CDS_TEST, null) != win.DISP_CHANGE_SUCCESSFUL)
        {
            continue;
        }

        out_modes[result_count] = converted;
        result_count += 1;
    }
    if (result_count == 0 and max_modes > 0) {
        out_modes[0] = getVideoMode(handle);
        return 1;
    }
    return result_count;
}

pub fn free(_: *anyopaque) void {}

pub fn setVideoMode(handle: *anyopaque, requested: VideoMode) bool {
    const monitor = native(handle);
    const best = chooseVideoMode(handle, requested) orelse return false;
    const current = getVideoMode(handle);
    if (compareVideoModes(current, best) == .eq) return true;

    var mode: win.DEVMODEW = .{};
    mode.dmFields = win.DM_PELSWIDTH | win.DM_PELSHEIGHT | win.DM_BITSPERPEL | win.DM_DISPLAYFREQUENCY;
    mode.dmPelsWidth = best.width;
    mode.dmPelsHeight = best.height;
    mode.dmBitsPerPel = best.red_bits + best.green_bits + best.blue_bits;
    mode.dmDisplayFrequency = best.refresh_rate;
    if (mode.dmBitsPerPel < 15 or mode.dmBitsPerPel >= 24) mode.dmBitsPerPel = 32;

    if (win.ChangeDisplaySettingsExW(deviceNameOrNull(monitor), &mode, null, win.CDS_FULLSCREEN, null) == win.DISP_CHANGE_SUCCESSFUL) {
        monitor.mode_changed = true;
        return true;
    }
    return false;
}

pub fn restoreVideoMode(handle: *anyopaque) void {
    const monitor = native(handle);
    if (!monitor.mode_changed) return;
    _ = win.ChangeDisplaySettingsExW(deviceNameOrNull(monitor), null, null, win.CDS_FULLSCREEN, null);
    monitor.mode_changed = false;
}

fn refresh() void {
    monitor_count = 0;

    var adapter_index: u32 = 0;
    while (monitor_count < monitors.len) : (adapter_index += 1) {
        var adapter: win.DISPLAY_DEVICEW = .{};
        if (win.EnumDisplayDevicesW(null, adapter_index, &adapter, 0) == 0) break;
        if ((adapter.StateFlags & win.DISPLAY_DEVICE_ACTIVE) == 0) continue;

        var display_index: u32 = 0;
        var added_display = false;
        while (monitor_count < monitors.len) : (display_index += 1) {
            var display: win.DISPLAY_DEVICEW = .{};
            if (win.EnumDisplayDevicesW(&adapter.DeviceName, display_index, &display, 0) == 0) break;
            if ((display.StateFlags & win.DISPLAY_DEVICE_ACTIVE) == 0) continue;
            addMonitor(&adapter, &display, (adapter.StateFlags & win.DISPLAY_DEVICE_PRIMARY_DEVICE) != 0 and !added_display);
            added_display = true;
        }

        if (!added_display) addMonitor(&adapter, null, (adapter.StateFlags & win.DISPLAY_DEVICE_PRIMARY_DEVICE) != 0);
    }

    if (monitor_count == 0) addFallbackMonitor();
}

fn addMonitor(adapter: *const win.DISPLAY_DEVICEW, display: ?*const win.DISPLAY_DEVICEW, insert_first: bool) void {
    if (monitor_count >= monitors.len) return;

    var mode: win.DEVMODEW = .{};
    _ = win.EnumDisplaySettingsW(&adapter.DeviceName, win.ENUM_CURRENT_SETTINGS, &mode);
    if (mode.dmPelsWidth == 0 or mode.dmPelsHeight == 0) {
        mode.dmPelsWidth = @intCast(@max(1, win.GetSystemMetrics(win.SM_CXSCREEN)));
        mode.dmPelsHeight = @intCast(@max(1, win.GetSystemMetrics(win.SM_CYSCREEN)));
    }

    var monitor = Monitor{
        .handle = null,
        .device_name = adapter.DeviceName,
        .display_name = if (display) |value| value.DeviceName else @splat(0),
        .public_name = publicName(adapter, display),
        .pos = .{ .x = mode.u1.s2.dmPosition.x, .y = mode.u1.s2.dmPosition.y },
        .size = .{ .width = mode.dmPelsWidth, .height = mode.dmPelsHeight },
        .modes_pruned = (adapter.StateFlags & win.DISPLAY_DEVICE_MODESPRUNED) != 0,
    };

    var rect = win.RECT{
        .left = mode.u1.s2.dmPosition.x,
        .top = mode.u1.s2.dmPosition.y,
        .right = mode.u1.s2.dmPosition.x + @as(win.LONG, @intCast(mode.dmPelsWidth)),
        .bottom = mode.u1.s2.dmPosition.y + @as(win.LONG, @intCast(mode.dmPelsHeight)),
    };
    _ = win.EnumDisplayMonitors(null, &rect, findMonitorCallback, @intCast(@intFromPtr(&monitor)));

    const insert_index: usize = if (insert_first) 0 else monitor_count;
    if (insert_index == 0 and monitor_count > 0) {
        var i: usize = monitor_count;
        while (i > 0) : (i -= 1) monitors[i] = monitors[i - 1];
    }
    monitors[insert_index] = monitor;
    monitor_count += 1;
}

fn findMonitorCallback(handle: win.HMONITOR, _: win.HDC, _: *win.RECT, data: win.LPARAM) callconv(.winapi) win.BOOL {
    const monitor: *Monitor = @ptrFromInt(@as(usize, @intCast(data)));
    var info: win.MONITORINFOEXW = .{};
    if (win.GetMonitorInfoW(handle, @ptrCast(&info)) == 0) return 1;
    if (std.mem.eql(win.WCHAR, std.mem.sliceTo(&info.szDevice, 0), std.mem.sliceTo(&monitor.device_name, 0))) {
        monitor.handle = handle;
        return 0;
    }
    return 1;
}

fn publicName(adapter: *const win.DISPLAY_DEVICEW, display: ?*const win.DISPLAY_DEVICEW) [128:0]u8 {
    var public_name: [128:0]u8 = @splat(0);
    const source = if (display) |d| &d.DeviceString else &adapter.DeviceString;
    const name = std.unicode.wtf16LeToWtf8(public_name[0 .. public_name.len - 1], std.mem.sliceTo(source, 0));
    public_name[name] = 0;
    if (public_name[0] == 0) {
        const fallback = "Generic PnP Monitor";
        @memcpy(public_name[0..fallback.len], fallback);
        public_name[fallback.len] = 0;
    }
    return public_name;
}

fn addFallbackMonitor() void {
    var public_name: [128:0]u8 = @splat(0);
    const fallback = "Win32 Display";
    @memcpy(public_name[0..fallback.len], fallback);
    public_name[fallback.len] = 0;

    monitors[0] = .{
        .handle = null,
        .device_name = @splat(0),
        .public_name = public_name,
        .pos = .{ .x = 0, .y = 0 },
        .size = .{
            .width = @intCast(@max(1, win.GetSystemMetrics(win.SM_CXSCREEN))),
            .height = @intCast(@max(1, win.GetSystemMetrics(win.SM_CYSCREEN))),
        },
    };
    monitor_count = 1;
}

fn deviceNameOrNull(monitor: *const Monitor) ?win.LPCWSTR {
    if (monitor.device_name[0] == 0) return null;
    return &monitor.device_name;
}

fn videoModeFromDevMode(mode: win.DEVMODEW) VideoMode {
    const bits = if (mode.dmBitsPerPel == 0) 24 else mode.dmBitsPerPel;
    const split = splitBpp(bits);
    return .{
        .width = mode.dmPelsWidth,
        .height = mode.dmPelsHeight,
        .red_bits = split.red,
        .green_bits = split.green,
        .blue_bits = split.blue,
        .refresh_rate = if (mode.dmDisplayFrequency == 0) 60 else mode.dmDisplayFrequency,
    };
}

fn chooseVideoMode(handle: *anyopaque, desired: VideoMode) ?VideoMode {
    var modes_buffer: [512]VideoMode = undefined;
    const mode_count = getVideoModes(handle, &modes_buffer, modes_buffer.len);
    if (mode_count == 0) return null;

    var best = modes_buffer[0];
    var least_color_diff: u32 = std.math.maxInt(u32);
    var least_size_diff: u32 = std.math.maxInt(u32);
    var least_rate_diff: u32 = std.math.maxInt(u32);

    for (modes_buffer[0..mode_count]) |mode| {
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
            std.math.maxInt(u32) - mode.refresh_rate;

        if (color_diff < least_color_diff or
            (color_diff == least_color_diff and size_diff < least_size_diff) or
            (color_diff == least_color_diff and size_diff == least_size_diff and rate_diff < least_rate_diff))
        {
            best = mode;
            least_color_diff = color_diff;
            least_size_diff = size_diff;
            least_rate_diff = rate_diff;
        }
    }

    return best;
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

fn splitBpp(value: u32) BppSplit {
    var bpp = value;
    if (bpp == 32) bpp = 24;

    var result = BppSplit{
        .red = bpp / 3,
        .green = bpp / 3,
        .blue = bpp / 3,
    };
    const delta = bpp - result.red * 3;
    if (delta >= 1) result.green += 1;
    if (delta == 2) result.red += 1;
    return result;
}

fn absDiff(lhs: u32, rhs: u32) u32 {
    return if (lhs > rhs) lhs - rhs else rhs - lhs;
}

fn native(handle: *anyopaque) *Monitor {
    return @ptrCast(@alignCast(handle));
}
