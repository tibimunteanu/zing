const std = @import("std");
const input = @import("input.zig");
const cursor_module = @import("cursor.zig");
const helper = @import("helper.zig");
const monitor_module = @import("monitor.zig");
const win = @import("types.zig");

pub const Config = extern struct {
    width: u32,
    height: u32,
    title: [*:0]const u8,
    resizable: bool,
    visible: bool,
    decorated: bool,
    focused: bool,
    auto_iconify: bool,
    floating: bool,
    maximized: bool,
    center_cursor: bool,
    scale_to_monitor: bool,
    scale_framebuffer: bool,
    transparent_framebuffer: bool,
    mouse_passthrough: bool,
    monitor: ?*anyopaque,
};

pub const ContentScale = extern struct {
    x_scale: f32,
    y_scale: f32,
};

pub const FrameSize = extern struct {
    left: u32,
    top: u32,
    right: u32,
    bottom: u32,
};

pub const Pos = extern struct {
    x: i32,
    y: i32,
};

pub const Size = extern struct {
    width: u32,
    height: u32,
};

pub const IconImage = extern struct {
    width: u32,
    height: u32,
    pixels: [*]const u8,
};

pub const EventCallbacks = struct {
    close: *const fn (usize) void,
    pos: *const fn (usize, i32, i32) void,
    size: *const fn (usize, u32, u32) void,
    focus: *const fn (usize, bool) void,
    iconify: *const fn (usize, bool) void,
    maximize: *const fn (usize, bool) void,
    framebuffer_size: *const fn (usize, u32, u32) void,
    content_scale: *const fn (usize, f32, f32) void,
    key: *const fn (usize, i32, i32, i32, u8) void,
    key_state: *const fn (usize, i32) i32,
    char: *const fn (usize, u32) void,
    char_mods: *const fn (usize, u32, u8) void,
    mouse_button: *const fn (usize, i32, i32, u8) void,
    cursor_pos: *const fn (usize, f64, f64) void,
    cursor_enter: *const fn (usize, bool) void,
    scroll: *const fn (usize, f64, f64) void,
    refresh: *const fn (usize) void,
    drop: *const fn (usize, usize, [*][*:0]const u8) void,
    monitor_changed: *const fn () void,
};

const class_name: [:0]const win.WCHAR = std.unicode.utf8ToUtf16LeStringLiteral("ZingWin32Window");
var callbacks_: ?EventCallbacks = null;
var initialized = false;
var class_atom: win.ATOM = 0;
var native_windows: [128]?*win.Window = @splat(null);
var clipboard_buffer: ?[:0]u8 = null;
var blank_cursor: win.HCURSOR = null;
var disabled_cursor_window: ?*win.Window = null;
var captured_cursor_window: ?*win.Window = null;
var restore_cursor_pos_x: f64 = 0;
var restore_cursor_pos_y: f64 = 0;
var acquired_monitor_count: usize = 0;
var mouse_trail_size: win.UINT = 0;

pub fn setEventCallbacks(new_callbacks: EventCallbacks) void {
    callbacks_ = new_callbacks;
}

pub fn closeAllFromEvent() void {
    for (native_windows) |maybe_window| {
        if (maybe_window) |window| {
            window.should_close = true;
            if (callbacks_) |cb| cb.close(window.callback_id);
        }
    }
}

pub fn repairStuckModifierKeys() void {
    const active_handle = win.GetActiveWindow() orelse return;
    const window = windowFromHwnd(active_handle) orelse return;

    const keys = [_]struct { vk: win.UINT, key: c_int }{
        .{ .vk = win.VK_LSHIFT, .key = 340 },
        .{ .vk = win.VK_RSHIFT, .key = 344 },
        .{ .vk = win.VK_LWIN, .key = 343 },
        .{ .vk = win.VK_RWIN, .key = 347 },
    };

    for (keys) |entry| {
        if ((@as(u16, @bitCast(win.GetKeyState(@intCast(entry.vk)))) & 0x8000) != 0) continue;
        callbacks().key(window.callback_id, entry.key, input.getKeyScancode(entry.key), 0, getKeyMods());
    }
}

pub fn recenterDisabledCursor() void {
    const window = disabled_cursor_window orelse return;
    const x: i32 = @intCast(window.width / 2);
    const y: i32 = @intCast(window.height / 2);

    if (window.last_cursor_pos_x != x or window.last_cursor_pos_y != y) {
        setCursorPos(@ptrCast(window), @floatFromInt(x), @floatFromInt(y));
    }
}

pub fn init() bool {
    if (initialized) return true;
    win.instance = @ptrCast(win.GetModuleHandleW(null));
    win.initDynamicApis();
    if (!helper.retain()) return false;
    if (win.set_process_dpi_awareness_context) |set_dpi_context| {
        if (set_dpi_context(win.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) == 0) {
            _ = win.SetProcessDPIAware();
        }
    } else {
        _ = win.SetProcessDPIAware();
    }

    const wc = win.WNDCLASSEXW{
        .style = 0x0003,
        .lpfnWndProc = wndProc,
        .hInstance = win.instance,
        .hCursor = win.LoadCursorW(null, win.IDC_ARROW),
        .lpszClassName = class_name.ptr,
    };
    class_atom = win.RegisterClassExW(&wc);
    if (class_atom == 0) {
        helper.release();
        return false;
    }
    blank_cursor = createBlankCursor();
    if (blank_cursor == null) {
        _ = win.UnregisterClassW(class_name.ptr, win.instance);
        helper.release();
        class_atom = 0;
        return false;
    }
    initialized = true;
    return true;
}

pub fn deinit() void {
    if (blank_cursor) |cursor| {
        _ = win.DestroyIcon(@ptrCast(cursor));
        blank_cursor = null;
    }
    if (class_atom != 0) _ = win.UnregisterClassW(class_name.ptr, win.instance);
    class_atom = 0;
    native_windows = @splat(null);
    if (clipboard_buffer) |buffer| {
        std.heap.c_allocator.free(buffer);
        clipboard_buffer = null;
    }
    helper.release();
    initialized = false;
}

pub fn create(config: *const Config) ?*anyopaque {
    const title = win.utf8ToWideZ(std.heap.c_allocator, config.title) catch return null;
    defer std.heap.c_allocator.free(title);

    const style = windowStyle(config.decorated, config.resizable);
    var ex_style: win.DWORD = win.WS_EX_APPWINDOW | win.WS_EX_ACCEPTFILES;
    if (config.floating) ex_style |= win.WS_EX_TOPMOST;
    if (config.transparent_framebuffer) ex_style |= win.WS_EX_LAYERED;
    if (config.mouse_passthrough) ex_style |= win.WS_EX_TRANSPARENT;

    var rect = win.RECT{ .left = 0, .top = 0, .right = @intCast(config.width), .bottom = @intCast(config.height) };
    _ = win.AdjustWindowRectEx(&rect, style, 0, ex_style);

    const native_window = std.heap.c_allocator.create(win.Window) catch return null;
    native_window.* = .{
        .handle = null,
        .width = config.width,
        .height = config.height,
        .decorated = config.decorated,
        .auto_iconify = config.auto_iconify,
        .transparent_framebuffer = config.transparent_framebuffer,
        .scale_to_monitor = config.scale_to_monitor,
        .scale_framebuffer = config.scale_framebuffer,
    };
    errdefer std.heap.c_allocator.destroy(native_window);

    const hwnd = win.CreateWindowExW(
        ex_style,
        class_name.ptr,
        title.ptr,
        style,
        win.CW_USEDEFAULT,
        win.CW_USEDEFAULT,
        rect.right - rect.left,
        rect.bottom - rect.top,
        null,
        null,
        win.instance,
        native_window,
    ) orelse return null;
    native_window.handle = hwnd;
    registerNativeWindow(native_window);
    _ = win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, @intCast(@intFromPtr(native_window)));
    win.DragAcceptFiles(hwnd, 1);
    if (config.transparent_framebuffer) {
        _ = win.SetLayeredWindowAttributes(hwnd, 0, 255, win.LWA_ALPHA);
        updateFramebufferTransparency(native_window);
    }
    if (config.maximized) _ = win.ShowWindow(hwnd, win.SW_SHOWMAXIMIZED);
    if (config.visible) _ = win.ShowWindow(hwnd, if (config.maximized) win.SW_SHOWMAXIMIZED else win.SW_SHOWNORMAL);
    if (config.focused) {
        _ = win.BringWindowToTop(hwnd);
        _ = win.SetForegroundWindow(hwnd);
        _ = win.SetFocus(hwnd);
    }
    return @ptrCast(native_window);
}

pub fn setMonitor(handle: *anyopaque, monitor: ?*anyopaque, pos: Pos, size: Size, refresh_rate: u32) void {
    const window = native(handle);
    if (window.monitor) |old_monitor| if (old_monitor != monitor) monitor_module.restoreVideoMode(old_monitor);

    window.monitor = monitor;
    if (monitor) |native_monitor| {
        if (!window.has_windowed_state) {
            _ = win.GetWindowRect(window.handle, &window.windowed_rect);
            window.windowed_style = @intCast(win.GetWindowLongPtrW(window.handle, win.GWL_STYLE));
            window.windowed_ex_style = @intCast(win.GetWindowLongPtrW(window.handle, win.GWL_EXSTYLE));
            window.has_windowed_state = true;
        }
        acquireMonitor(window, native_monitor, size, refresh_rate);
        const monitor_pos = monitor_module.getPos(native_monitor);
        _ = win.SetWindowLongPtrW(window.handle, win.GWL_STYLE, @intCast(win.WS_POPUP));
        _ = win.SetWindowPos(window.handle, win.HWND_TOPMOST, monitor_pos.x, monitor_pos.y, @intCast(size.width), @intCast(size.height), win.SWP_FRAMECHANGED | win.SWP_SHOWWINDOW);
    } else {
        const style = if (window.has_windowed_state) window.windowed_style else windowStyle(window.decorated, true);
        const ex_style = if (window.has_windowed_state) window.windowed_ex_style else @as(win.DWORD, @intCast(win.GetWindowLongPtrW(window.handle, win.GWL_EXSTYLE)));
        _ = win.SetWindowLongPtrW(window.handle, win.GWL_STYLE, @intCast(style));
        _ = win.SetWindowLongPtrW(window.handle, win.GWL_EXSTYLE, @intCast(ex_style));
        const restore_rect = if (window.has_windowed_state) window.windowed_rect else win.RECT{
            .left = pos.x,
            .top = pos.y,
            .right = pos.x + @as(win.LONG, @intCast(size.width)),
            .bottom = pos.y + @as(win.LONG, @intCast(size.height)),
        };
        _ = win.SetWindowPos(
            window.handle,
            win.HWND_NOTOPMOST,
            restore_rect.left,
            restore_rect.top,
            restore_rect.right - restore_rect.left,
            restore_rect.bottom - restore_rect.top,
            win.SWP_FRAMECHANGED | win.SWP_SHOWWINDOW,
        );
        window.has_windowed_state = false;
        window.monitor_acquired = false;
    }
}

pub fn setIcon(handle: *anyopaque, images: [*]const IconImage, count: usize) bool {
    const window = native(handle);
    if (window.big_icon) |icon| {
        _ = win.DestroyIcon(icon);
        window.big_icon = null;
    }
    if (window.small_icon) |icon| {
        _ = win.DestroyIcon(icon);
        window.small_icon = null;
    }

    if (count == 0) {
        _ = win.SendMessageW(window.handle, win.WM_SETICON, win.ICON_BIG, 0);
        _ = win.SendMessageW(window.handle, win.WM_SETICON, win.ICON_SMALL, 0);
        return true;
    }

    const image = selectIconImage(images[0..count]);
    window.big_icon = createIconFromImage(image);
    window.small_icon = createIconFromImage(image);
    if (window.big_icon == null or window.small_icon == null) return false;

    _ = win.SendMessageW(window.handle, win.WM_SETICON, win.ICON_BIG, @bitCast(@intFromPtr(window.big_icon.?)));
    _ = win.SendMessageW(window.handle, win.WM_SETICON, win.ICON_SMALL, @bitCast(@intFromPtr(window.small_icon.?)));
    return true;
}

pub fn destroy(handle: *anyopaque) void {
    const window = native(handle);
    if (disabled_cursor_window == window) {
        enableCursor(window);
    }
    if (captured_cursor_window == window) captured_cursor_window = null;
    releaseCursorClip();
    if (window.monitor) |monitor| monitor_module.restoreVideoMode(monitor);
    if (window.big_icon) |icon| _ = win.DestroyIcon(icon);
    if (window.small_icon) |icon| _ = win.DestroyIcon(icon);
    unregisterNativeWindow(window);
    _ = win.DestroyWindow(window.handle);
    std.heap.c_allocator.destroy(window);
}

pub fn setCallbackId(handle: *anyopaque, id: usize) void {
    native(handle).callback_id = id;
}

pub fn shouldClose(handle: *anyopaque) bool {
    return native(handle).should_close;
}

pub fn setShouldClose(handle: *anyopaque, value: bool) void {
    native(handle).should_close = value;
}

pub fn setTitle(handle: *anyopaque, title: [*:0]const u8) void {
    const wide = win.utf8ToWideZ(std.heap.c_allocator, title) catch return;
    defer std.heap.c_allocator.free(wide);
    _ = win.SetWindowTextW(native(handle).handle, wide.ptr);
}

pub fn getPos(handle: *anyopaque) Pos {
    var rect: win.RECT = undefined;
    _ = win.GetWindowRect(native(handle).handle, &rect);
    return .{ .x = rect.left, .y = rect.top };
}

pub fn setPos(handle: *anyopaque, pos: Pos) void {
    _ = win.SetWindowPos(native(handle).handle, null, pos.x, pos.y, 0, 0, win.SWP_NOSIZE | win.SWP_NOZORDER | win.SWP_NOACTIVATE);
}

pub fn getSize(handle: *anyopaque) Size {
    var rect: win.RECT = undefined;
    _ = win.GetClientRect(native(handle).handle, &rect);
    return .{ .width = @intCast(rect.right - rect.left), .height = @intCast(rect.bottom - rect.top) };
}

pub fn setSize(handle: *anyopaque, size: Size) void {
    const window = native(handle);
    if (window.monitor) |monitor| {
        acquireMonitor(window, monitor, size, 0);
        const monitor_pos = monitor_module.getPos(monitor);
        _ = win.SetWindowPos(window.handle, win.HWND_TOPMOST, monitor_pos.x, monitor_pos.y, @intCast(size.width), @intCast(size.height), win.SWP_FRAMECHANGED | win.SWP_SHOWWINDOW);
        return;
    }

    const hwnd = window.handle;
    var rect = win.RECT{ .left = 0, .top = 0, .right = @intCast(size.width), .bottom = @intCast(size.height) };
    adjustWindowRectForCurrentDpi(hwnd, &rect);
    _ = win.SetWindowPos(hwnd, null, 0, 0, rect.right - rect.left, rect.bottom - rect.top, win.SWP_NOMOVE | win.SWP_NOZORDER | win.SWP_NOACTIVATE);
}

pub fn setSizeLimits(handle: *anyopaque, min_size: Size, max_size: Size) void {
    const window = native(handle);
    window.min_width = min_size.width;
    window.min_height = min_size.height;
    window.max_width = max_size.width;
    window.max_height = max_size.height;
}

pub fn setAspectRatio(handle: *anyopaque, numerator: u32, denominator: u32) void {
    native(handle).numer = numerator;
    native(handle).denom = denominator;
}

pub fn clearAspectRatio(handle: *anyopaque) void {
    native(handle).numer = 0;
    native(handle).denom = 0;
}

pub fn getFramebufferSize(handle: *anyopaque) Size {
    return getSize(handle);
}

pub fn getFrameSize(handle: *anyopaque) FrameSize {
    const hwnd = native(handle).handle;
    var window_rect: win.RECT = undefined;
    var client_rect: win.RECT = undefined;
    _ = win.GetWindowRect(hwnd, &window_rect);
    _ = win.GetClientRect(hwnd, &client_rect);
    var top_left = win.POINT{ .x = client_rect.left, .y = client_rect.top };
    var bottom_right = win.POINT{ .x = client_rect.right, .y = client_rect.bottom };
    _ = win.ClientToScreen(hwnd, &top_left);
    _ = win.ClientToScreen(hwnd, &bottom_right);
    return .{
        .left = @intCast(top_left.x - window_rect.left),
        .top = @intCast(top_left.y - window_rect.top),
        .right = @intCast(window_rect.right - bottom_right.x),
        .bottom = @intCast(window_rect.bottom - bottom_right.y),
    };
}

pub fn getContentScale(handle: *anyopaque) ContentScale {
    const dpi = getDpiForWindow(native(handle).handle);
    return .{
        .x_scale = @as(f32, @floatFromInt(dpi)) / @as(f32, @floatFromInt(win.USER_DEFAULT_SCREEN_DPI)),
        .y_scale = @as(f32, @floatFromInt(dpi)) / @as(f32, @floatFromInt(win.USER_DEFAULT_SCREEN_DPI)),
    };
}

pub fn getOpacity(handle: *anyopaque) f32 {
    const hwnd = native(handle).handle;
    const ex_style: win.DWORD = @intCast(win.GetWindowLongPtrW(hwnd, win.GWL_EXSTYLE));
    if ((ex_style & win.WS_EX_LAYERED) != 0) {
        var alpha: win.BYTE = 255;
        var flags: win.DWORD = 0;
        if (win.GetLayeredWindowAttributes(hwnd, null, &alpha, &flags) != 0 and (flags & win.LWA_ALPHA) != 0) {
            return @as(f32, @floatFromInt(alpha)) / 255.0;
        }
    }
    return 1.0;
}

pub fn setOpacity(handle: *anyopaque, opacity: f32) void {
    const hwnd = native(handle).handle;
    const ex_style: win.DWORD = @intCast(win.GetWindowLongPtrW(hwnd, win.GWL_EXSTYLE));
    _ = win.SetWindowLongPtrW(hwnd, win.GWL_EXSTYLE, @intCast(ex_style | win.WS_EX_LAYERED));
    _ = win.SetLayeredWindowAttributes(hwnd, 0, @intFromFloat(opacity * 255.0), win.LWA_ALPHA);
}

pub fn iconify(handle: *anyopaque) void {
    _ = win.ShowWindow(native(handle).handle, win.SW_SHOWMINIMIZED);
}

pub fn restore(handle: *anyopaque) void {
    _ = win.ShowWindow(native(handle).handle, win.SW_RESTORE);
}

pub fn maximize(handle: *anyopaque) void {
    _ = win.ShowWindow(native(handle).handle, win.SW_SHOWMAXIMIZED);
}

pub fn show(handle: *anyopaque) void {
    _ = win.ShowWindow(native(handle).handle, win.SW_SHOW);
}

pub fn hide(handle: *anyopaque) void {
    _ = win.ShowWindow(native(handle).handle, win.SW_HIDE);
}

pub fn focus(handle: *anyopaque) void {
    _ = win.BringWindowToTop(native(handle).handle);
    _ = win.SetForegroundWindow(native(handle).handle);
    _ = win.SetFocus(native(handle).handle);
}

pub fn requestAttention(handle: *anyopaque) void {
    _ = win.FlashWindow(native(handle).handle, 1);
}

pub fn getAttribute(handle: *anyopaque, attr: c_int) bool {
    const hwnd = native(handle).handle;
    return switch (attr) {
        0 => win.GetFocus() == hwnd,
        1 => win.IsIconic(hwnd) != 0,
        2 => win.IsZoomed(hwnd) != 0,
        3 => cursorInClient(hwnd),
        4 => win.IsWindowVisible(hwnd) != 0,
        5 => (@as(win.DWORD, @intCast(win.GetWindowLongPtrW(hwnd, win.GWL_STYLE))) & win.WS_THICKFRAME) != 0,
        6 => (@as(win.DWORD, @intCast(win.GetWindowLongPtrW(hwnd, win.GWL_STYLE))) & win.WS_CAPTION) != 0,
        7 => true,
        8 => (@as(win.DWORD, @intCast(win.GetWindowLongPtrW(hwnd, win.GWL_EXSTYLE))) & win.WS_EX_TOPMOST) != 0,
        9 => false,
        10 => true,
        11 => (@as(win.DWORD, @intCast(win.GetWindowLongPtrW(hwnd, win.GWL_EXSTYLE))) & win.WS_EX_TRANSPARENT) != 0,
        else => false,
    };
}

pub fn setAttribute(handle: *anyopaque, attr: c_int, value: bool) void {
    const hwnd = native(handle).handle;
    switch (attr) {
        5 => setStyleBit(hwnd, win.WS_THICKFRAME | win.WS_MAXIMIZEBOX, value),
        6 => setStyleBit(hwnd, win.WS_CAPTION | win.WS_SYSMENU | win.WS_MINIMIZEBOX, value),
        8 => _ = win.SetWindowPos(hwnd, if (value) win.HWND_TOPMOST else win.HWND_NOTOPMOST, 0, 0, 0, 0, win.SWP_NOMOVE | win.SWP_NOSIZE | win.SWP_NOACTIVATE),
        11 => setExStyleBit(hwnd, win.WS_EX_TRANSPARENT, value),
        else => {},
    }
}

pub fn setUserPointer(handle: *anyopaque, pointer: ?*anyopaque) void {
    native(handle).user_pointer = pointer;
}

pub fn getUserPointer(handle: *anyopaque) ?*anyopaque {
    return native(handle).user_pointer;
}

pub fn getCursorPos(handle: *anyopaque) Pos {
    var point: win.POINT = undefined;
    _ = win.GetCursorPos(&point);
    _ = win.ScreenToClient(native(handle).handle, &point);
    return .{ .x = point.x, .y = point.y };
}

pub fn setCursorPos(handle: *anyopaque, x: f64, y: f64) void {
    const window = native(handle);
    var point = win.POINT{ .x = @intFromFloat(x), .y = @intFromFloat(y) };
    window.last_cursor_pos_x = point.x;
    window.last_cursor_pos_y = point.y;
    _ = win.ClientToScreen(window.handle, &point);
    _ = win.SetCursorPos(point.x, point.y);
}

pub fn setCursor(handle: *anyopaque, cursor_handle: ?*anyopaque) void {
    const window = native(handle);
    window.cursor = if (cursor_handle) |value|
        (@as(*cursor_module.Cursor, @ptrCast(@alignCast(value)))).handle
    else
        win.LoadCursorW(null, win.IDC_ARROW);
    if (cursorInClient(window.handle)) updateCursorImage(window);
}

pub fn setInputMode(handle: *anyopaque, mode: c_int, value: c_int) void {
    const window = native(handle);
    if (mode == 1) {
        window.raw_mouse_motion = value != 0;
        if (disabled_cursor_window == window) setRawMouseMotion(window, value != 0);
        return;
    }
    if (mode != 0) return;
    window.cursor_mode = value;
    const pos = getCursorPos(handle);
    window.virtual_cursor_x = @floatFromInt(pos.x);
    window.virtual_cursor_y = @floatFromInt(pos.y);
    window.last_cursor_pos_x = pos.x;
    window.last_cursor_pos_y = pos.y;
    if (win.GetFocus() == window.handle) {
        if (value == 2) {
            disableCursor(window);
        } else if (disabled_cursor_window == window) {
            enableCursor(window);
        }
        if (value == 3) {
            captureCursor(window);
        } else if (value != 2 and disabled_cursor_window != window) {
            releaseCursorClip();
        }
    }
    if (cursorInClient(window.handle)) updateCursorImage(window);
}

pub fn setClipboardString(value: [*:0]const u8) void {
    const wide = win.utf8ToWideZ(std.heap.c_allocator, value) catch return;
    defer std.heap.c_allocator.free(wide);
    const byte_count = (wide.len + 1) * @sizeOf(win.WCHAR);
    const memory = win.GlobalAlloc(win.GMEM_MOVEABLE, byte_count) orelse return;
    errdefer _ = win.GlobalFree(memory);
    const target: [*]u8 = @ptrCast(win.GlobalLock(memory) orelse return);
    @memcpy(target[0..byte_count], std.mem.sliceAsBytes(wide[0 .. wide.len + 1]));
    _ = win.GlobalUnlock(memory);
    if (!openClipboardWithRetry(helper.handle())) return;
    defer _ = win.CloseClipboard();
    _ = win.EmptyClipboard();
    _ = win.SetClipboardData(win.CF_UNICODETEXT, memory);
}

pub fn getClipboardString() ?[*:0]const u8 {
    if (win.IsClipboardFormatAvailable(win.CF_UNICODETEXT) == 0) return null;
    if (!openClipboardWithRetry(helper.handle())) return null;
    defer _ = win.CloseClipboard();
    const data = win.GetClipboardData(win.CF_UNICODETEXT) orelse return null;
    const wide: [*:0]const win.WCHAR = @ptrCast(@alignCast(win.GlobalLock(data) orelse return null));
    defer _ = win.GlobalUnlock(data);
    if (clipboard_buffer) |buffer| {
        std.heap.c_allocator.free(buffer);
        clipboard_buffer = null;
    }
    clipboard_buffer = win.wideToUtf8Z(std.heap.c_allocator, wide) catch return null;
    return clipboard_buffer.?.ptr;
}

fn wndProc(hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) callconv(.winapi) win.LRESULT {
    if (msg == win.WM_CREATE) return win.DefWindowProcW(hwnd, msg, wparam, lparam);
    const window = windowFromHwnd(hwnd) orelse return win.DefWindowProcW(hwnd, msg, wparam, lparam);

    switch (msg) {
        win.WM_MOUSEACTIVATE => {
            if (win.hiword(@bitCast(lparam)) == win.WM_LBUTTONDOWN and win.loword(@bitCast(lparam)) != win.HTCLIENT) {
                window.frame_action = true;
            }
            return win.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        win.WM_CAPTURECHANGED => {
            if (lparam == 0 and window.frame_action) {
                if (window.cursor_mode == 2) {
                    disableCursor(window);
                } else if (window.cursor_mode == 3) {
                    captureCursor(window);
                }
                window.frame_action = false;
            }
            return win.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        win.WM_CLOSE => {
            window.should_close = true;
            callbacks().close(window.callback_id);
            return 0;
        },
        win.WM_MOVE => {
            callbacks().pos(window.callback_id, win.getX(lparam), win.getY(lparam));
            if (captured_cursor_window == window) captureCursor(window);
            return 0;
        },
        win.WM_SIZE => {
            const width: u32 = win.loword(@bitCast(lparam));
            const height: u32 = win.hiword(@bitCast(lparam));
            const iconified = wparam == win.SIZE_MINIMIZED;
            const maximized = wparam == win.SIZE_MAXIMIZED or (window.maximized and wparam != win.SIZE_RESTORED);
            if (captured_cursor_window == window) captureCursor(window);
            if (window.iconified != iconified) callbacks().iconify(window.callback_id, iconified);
            if (window.maximized != maximized) callbacks().maximize(window.callback_id, maximized);
            if (width != window.width or height != window.height) {
                window.width = width;
                window.height = height;
                callbacks().framebuffer_size(window.callback_id, width, height);
                callbacks().size(window.callback_id, width, height);
            }
            if (window.monitor) |native_monitor| {
                if (window.iconified != iconified and iconified) {
                    releaseMonitor(window, native_monitor);
                } else if (window.iconified != iconified and !iconified) {
                    acquireMonitor(window, native_monitor, .{ .width = width, .height = height }, 0);
                    const monitor_pos = monitor_module.getPos(native_monitor);
                    _ = win.SetWindowPos(window.handle, win.HWND_TOPMOST, monitor_pos.x, monitor_pos.y, @intCast(width), @intCast(height), win.SWP_FRAMECHANGED | win.SWP_SHOWWINDOW);
                }
            }
            window.iconified = iconified;
            window.maximized = maximized;
            return 0;
        },
        win.WM_SETFOCUS => {
            callbacks().focus(window.callback_id, true);
            if (window.frame_action) return 0;
            if (window.cursor_mode == 2) {
                disableCursor(window);
            } else if (window.cursor_mode == 3) {
                captureCursor(window);
            }
            return 0;
        },
        win.WM_KILLFOCUS => {
            if (window.cursor_mode == 2) enableCursor(window);
            if (window.cursor_mode == 3) releaseCursorClip();
            if (window.monitor != null and window.auto_iconify) iconify(@ptrCast(window));
            callbacks().focus(window.callback_id, false);
            return 0;
        },
        win.WM_SYSCOMMAND => {
            switch (wparam & 0xfff0) {
                win.SC_SCREENSAVE, win.SC_MONITORPOWER => {
                    if (window.monitor != null) return 0;
                },
                else => {},
            }
            return win.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        win.WM_PAINT => {
            var ps: win.PAINTSTRUCT = undefined;
            _ = BeginPaint(hwnd, &ps);
            _ = EndPaint(hwnd, &ps);
            callbacks().refresh(window.callback_id);
            return 0;
        },
        win.WM_ENTERSIZEMOVE, win.WM_ENTERMENULOOP => {
            if (!window.frame_action) {
                if (window.cursor_mode == 2) {
                    enableCursor(window);
                } else if (window.cursor_mode == 3) {
                    releaseCursorClip();
                }
            }
            return win.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        win.WM_EXITSIZEMOVE, win.WM_EXITMENULOOP => {
            if (!window.frame_action) {
                if (window.cursor_mode == 2) {
                    disableCursor(window);
                } else if (window.cursor_mode == 3) {
                    captureCursor(window);
                }
            }
            return win.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        win.WM_NCACTIVATE, win.WM_NCPAINT => {
            if (!window.decorated) return 1;
            return win.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        win.WM_DWMCOMPOSITIONCHANGED, win.WM_DWMCOLORIZATIONCOLORCHANGED => {
            if (window.transparent_framebuffer) updateFramebufferTransparency(window);
            return 0;
        },
        win.WM_GETMINMAXINFO => {
            const info: *win.MINMAXINFO = @ptrFromInt(@as(usize, @bitCast(lparam)));
            var frame = win.RECT{ .left = 0, .top = 0, .right = 0, .bottom = 0 };
            adjustWindowRectForCurrentDpi(hwnd, &frame);
            const frame_width = frame.right - frame.left;
            const frame_height = frame.bottom - frame.top;
            if (window.min_width > 0) info.ptMinTrackSize.x = @intCast(window.min_width + @as(u32, @intCast(frame_width)));
            if (window.min_height > 0) info.ptMinTrackSize.y = @intCast(window.min_height + @as(u32, @intCast(frame_height)));
            if (window.max_width > 0) info.ptMaxTrackSize.x = @intCast(window.max_width + @as(u32, @intCast(frame_width)));
            if (window.max_height > 0) info.ptMaxTrackSize.y = @intCast(window.max_height + @as(u32, @intCast(frame_height)));
            return 0;
        },
        win.WM_GETDPISCALEDSIZE => {
            if (window.scale_to_monitor) return win.DefWindowProcW(hwnd, msg, wparam, lparam);
            const requested_size: *win.SIZE = @ptrFromInt(@as(usize, @bitCast(lparam)));
            var source = win.RECT{ .left = 0, .top = 0, .right = 0, .bottom = 0 };
            var target = win.RECT{ .left = 0, .top = 0, .right = 0, .bottom = 0 };
            adjustWindowRectForDpi(hwnd, &source, getDpiForWindow(hwnd));
            adjustWindowRectForDpi(hwnd, &target, @intCast(wparam));
            requested_size.cx += (target.right - target.left) - (source.right - source.left);
            requested_size.cy += (target.bottom - target.top) - (source.bottom - source.top);
            return 1;
        },
        win.WM_DPICHANGED => {
            const x_scale = @as(f32, @floatFromInt(win.hiword(wparam))) / @as(f32, @floatFromInt(win.USER_DEFAULT_SCREEN_DPI));
            const y_scale = @as(f32, @floatFromInt(win.loword(wparam))) / @as(f32, @floatFromInt(win.USER_DEFAULT_SCREEN_DPI));
            const suggested: *win.RECT = @ptrFromInt(@as(usize, @bitCast(lparam)));
            if (window.monitor == null and window.scale_to_monitor) {
                _ = win.SetWindowPos(
                    hwnd,
                    null,
                    suggested.left,
                    suggested.top,
                    suggested.right - suggested.left,
                    suggested.bottom - suggested.top,
                    win.SWP_NOACTIVATE | win.SWP_NOZORDER,
                );
            }
            callbacks().content_scale(window.callback_id, x_scale, y_scale);
            return 0;
        },
        win.WM_INPUTLANGCHANGE => {
            input.updateKeyNames();
            return 0;
        },
        win.WM_KEYDOWN, win.WM_SYSKEYDOWN => return keyMessage(window, wparam, lparam, 1),
        win.WM_KEYUP, win.WM_SYSKEYUP => return keyMessage(window, wparam, lparam, 0),
        win.WM_CHAR, win.WM_SYSCHAR => {
            if (wparam >= 0xd800 and wparam <= 0xdbff) {
                window.high_surrogate = @intCast(wparam);
                return 0;
            }

            var codepoint: u32 = 0;
            if (wparam >= 0xdc00 and wparam <= 0xdfff) {
                if (window.high_surrogate != 0) {
                    codepoint += (@as(u32, window.high_surrogate) - 0xd800) << 10;
                    codepoint += @as(u32, @intCast(wparam)) - 0xdc00;
                    codepoint += 0x10000;
                }
            } else {
                codepoint = @intCast(wparam);
            }

            window.high_surrogate = 0;
            if (codepoint != 0) {
                callbacks().char_mods(window.callback_id, codepoint, getKeyMods());
                if (msg != win.WM_SYSCHAR) callbacks().char(window.callback_id, codepoint);
            }
            return 0;
        },
        win.WM_UNICHAR => {
            if (wparam == win.UNICODE_NOCHAR) return 1;
            const codepoint: u32 = @intCast(wparam);
            callbacks().char_mods(window.callback_id, codepoint, getKeyMods());
            callbacks().char(window.callback_id, codepoint);
            return 0;
        },
        win.WM_MOUSEMOVE => {
            const x = win.getX(lparam);
            const y = win.getY(lparam);
            if (!window.cursor_tracked) {
                var track = win.TRACKMOUSEEVENT{ .dwFlags = win.TME_LEAVE, .hwndTrack = hwnd };
                _ = win.TrackMouseEvent(&track);
                window.cursor_tracked = true;
                callbacks().cursor_enter(window.callback_id, true);
            }
            if (window.cursor_mode == 2) {
                const dx = x - window.last_cursor_pos_x;
                const dy = y - window.last_cursor_pos_y;
                if (disabled_cursor_window == window and !window.raw_mouse_motion) {
                    window.virtual_cursor_x += @floatFromInt(dx);
                    window.virtual_cursor_y += @floatFromInt(dy);
                    callbacks().cursor_pos(window.callback_id, window.virtual_cursor_x, window.virtual_cursor_y);
                }
            } else {
                window.virtual_cursor_x = @floatFromInt(x);
                window.virtual_cursor_y = @floatFromInt(y);
                callbacks().cursor_pos(window.callback_id, @floatFromInt(x), @floatFromInt(y));
            }
            window.last_cursor_pos_x = x;
            window.last_cursor_pos_y = y;
            return 0;
        },
        win.WM_INPUT => {
            handleRawInput(window, @ptrFromInt(@as(usize, @bitCast(lparam))));
            return 0;
        },
        win.WM_MOUSELEAVE => {
            window.cursor_tracked = false;
            callbacks().cursor_enter(window.callback_id, false);
            return 0;
        },
        win.WM_LBUTTONDOWN, win.WM_RBUTTONDOWN, win.WM_MBUTTONDOWN, win.WM_XBUTTONDOWN => {
            const button = mouseButtonFromMessage(msg, wparam);
            if (window.mouse_button_mask == 0) _ = win.SetCapture(hwnd);
            window.mouse_button_mask |= buttonMask(button);
            callbacks().mouse_button(window.callback_id, button, 1, getKeyMods());
            return if (msg == win.WM_XBUTTONDOWN) 1 else 0;
        },
        win.WM_LBUTTONUP, win.WM_RBUTTONUP, win.WM_MBUTTONUP, win.WM_XBUTTONUP => {
            const button = mouseButtonFromMessage(msg, wparam);
            window.mouse_button_mask &= ~buttonMask(button);
            callbacks().mouse_button(window.callback_id, button, 0, getKeyMods());
            if (window.mouse_button_mask == 0) _ = win.ReleaseCapture();
            return if (msg == win.WM_XBUTTONUP) 1 else 0;
        },
        win.WM_MOUSEWHEEL => {
            callbacks().scroll(window.callback_id, 0.0, @as(f64, @floatFromInt(@as(i16, @bitCast(win.hiword(wparam))))) / 120.0);
            return 0;
        },
        win.WM_MOUSEHWHEEL => {
            callbacks().scroll(window.callback_id, -@as(f64, @floatFromInt(@as(i16, @bitCast(win.hiword(wparam))))) / 120.0, 0.0);
            return 0;
        },
        win.WM_SETCURSOR => {
            updateCursorImage(window);
            return 1;
        },
        win.WM_DROPFILES => {
            handleDrop(window, @ptrFromInt(wparam));
            return 0;
        },
        else => return win.DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

fn handleDrop(window: *win.Window, drop: win.HDROP) void {
    defer win.DragFinish(drop);
    const count = win.DragQueryFileW(drop, 0xffffffff, null, 0);
    if (count == 0) return;

    const path_buffers = std.heap.c_allocator.alloc(?[:0]u8, count) catch return;
    defer std.heap.c_allocator.free(path_buffers);
    @memset(path_buffers, null);
    const path_ptrs = std.heap.c_allocator.alloc([*:0]const u8, count) catch return;
    defer std.heap.c_allocator.free(path_ptrs);
    var converted_count: usize = 0;
    defer {
        for (path_buffers) |maybe_path| {
            if (maybe_path) |path| std.heap.c_allocator.free(path);
        }
    }

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const wide_len = win.DragQueryFileW(drop, @intCast(i), null, 0);
        const wide = std.heap.c_allocator.allocSentinel(win.WCHAR, wide_len, 0) catch continue;
        defer std.heap.c_allocator.free(wide);
        _ = win.DragQueryFileW(drop, @intCast(i), wide.ptr, wide_len + 1);
        const utf8 = std.unicode.wtf16LeToWtf8AllocZ(std.heap.c_allocator, wide[0..wide_len]) catch continue;
        path_buffers[i] = utf8;
        path_ptrs[converted_count] = utf8.ptr;
        converted_count += 1;
    }
    if (converted_count > 0) callbacks().drop(window.callback_id, converted_count, path_ptrs.ptr);
}

fn handleRawInput(window: *win.Window, raw_input: win.HANDLE) void {
    if (disabled_cursor_window != window or !window.raw_mouse_motion) return;

    var size: win.UINT = 0;
    _ = win.GetRawInputData(raw_input, win.RID_INPUT, null, &size, @sizeOf(win.RAWINPUTHEADER));
    if (size < @sizeOf(win.RAWINPUT)) return;

    const buffer = std.heap.c_allocator.alloc(u8, size) catch return;
    defer std.heap.c_allocator.free(buffer);

    var read_size = size;
    if (win.GetRawInputData(raw_input, win.RID_INPUT, buffer.ptr, &read_size, @sizeOf(win.RAWINPUTHEADER)) == std.math.maxInt(win.UINT)) return;
    if (read_size < @sizeOf(win.RAWINPUT)) return;

    const data: *align(1) const win.RAWINPUT = @ptrCast(buffer.ptr);
    if (data.header.dwType != win.RIM_TYPEMOUSE) return;

    var dx: i32 = undefined;
    var dy: i32 = undefined;
    if ((data.data.mouse.usFlags & win.MOUSE_MOVE_ABSOLUTE) != 0) {
        var pos = win.POINT{ .x = 0, .y = 0 };
        const width: i32 = if ((data.data.mouse.usFlags & win.MOUSE_VIRTUAL_DESKTOP) != 0)
            win.GetSystemMetrics(win.SM_CXVIRTUALSCREEN)
        else
            win.GetSystemMetrics(win.SM_CXSCREEN);
        const height: i32 = if ((data.data.mouse.usFlags & win.MOUSE_VIRTUAL_DESKTOP) != 0)
            win.GetSystemMetrics(win.SM_CYVIRTUALSCREEN)
        else
            win.GetSystemMetrics(win.SM_CYSCREEN);
        if ((data.data.mouse.usFlags & win.MOUSE_VIRTUAL_DESKTOP) != 0) {
            pos.x += win.GetSystemMetrics(win.SM_XVIRTUALSCREEN);
            pos.y += win.GetSystemMetrics(win.SM_YVIRTUALSCREEN);
        }
        pos.x += @intFromFloat((@as(f64, @floatFromInt(data.data.mouse.lLastX)) / 65535.0) * @as(f64, @floatFromInt(width)));
        pos.y += @intFromFloat((@as(f64, @floatFromInt(data.data.mouse.lLastY)) / 65535.0) * @as(f64, @floatFromInt(height)));
        _ = win.ScreenToClient(window.handle, &pos);
        dx = pos.x - window.last_cursor_pos_x;
        dy = pos.y - window.last_cursor_pos_y;
    } else {
        dx = @intCast(data.data.mouse.lLastX);
        dy = @intCast(data.data.mouse.lLastY);
    }

    window.virtual_cursor_x += @floatFromInt(dx);
    window.virtual_cursor_y += @floatFromInt(dy);
    callbacks().cursor_pos(window.callback_id, window.virtual_cursor_x, window.virtual_cursor_y);
    window.last_cursor_pos_x += dx;
    window.last_cursor_pos_y += dy;
}

fn keyMessage(window: *win.Window, wparam: win.WPARAM, lparam: win.LPARAM, action: i32) win.LRESULT {
    var scancode: u32 = @intCast((lparam >> 16) & 0x1ff);
    if (scancode == 0) scancode = win.MapVirtualKeyW(@intCast(wparam), win.MAPVK_VK_TO_VSC);
    if (scancode == 0x54) scancode = 0x137;
    if (scancode == 0x146) scancode = 0x45;
    if (scancode == 0x136) scancode = 0x36;

    if (wparam == win.VK_PROCESSKEY) return 0;
    if (wparam == win.VK_CONTROL and (scancode & win.KF_EXTENDED) == 0 and isAltGrControlMessage()) return 0;

    const mods = getKeyMods();
    if (action == 0 and wparam == win.VK_SHIFT) {
        callbacks().key(window.callback_id, 340, @intCast(scancode), 0, mods);
        callbacks().key(window.callback_id, 344, @intCast(scancode), 0, mods);
        return 0;
    }

    const key = input.translateKey(@intCast(wparam), scancode);
    if (wparam == win.VK_SNAPSHOT) {
        callbacks().key(window.callback_id, key, @intCast(scancode), 1, mods);
        callbacks().key(window.callback_id, key, @intCast(scancode), 0, mods);
        return 0;
    }

    callbacks().key(window.callback_id, key, @intCast(scancode), action, mods);
    return 0;
}

fn isAltGrControlMessage() bool {
    var next: win.MSG = undefined;
    if (win.PeekMessageW(&next, null, 0, 0, win.PM_NOREMOVE) == 0) return false;
    if (next.message != win.WM_KEYDOWN and next.message != win.WM_SYSKEYDOWN and
        next.message != win.WM_KEYUP and next.message != win.WM_SYSKEYUP) return false;
    if (next.wParam != win.VK_MENU) return false;
    if ((@as(u32, @intCast((next.lParam >> 16) & 0xffff)) & win.KF_EXTENDED) == 0) return false;
    return next.time == @as(win.DWORD, @bitCast(win.GetMessageTime()));
}

fn callbacks() EventCallbacks {
    return callbacks_.?;
}

fn native(handle: *anyopaque) *win.Window {
    return @ptrCast(@alignCast(handle));
}

fn registerNativeWindow(window: *win.Window) void {
    for (&native_windows) |*slot| {
        if (slot.* == null) {
            slot.* = window;
            return;
        }
    }
}

fn unregisterNativeWindow(window: *win.Window) void {
    for (&native_windows) |*slot| {
        if (slot.* == window) {
            slot.* = null;
            return;
        }
    }
}

fn openClipboardWithRetry(owner: win.HWND) bool {
    var retries: usize = 0;
    while (retries < 3) : (retries += 1) {
        if (win.OpenClipboard(owner) != 0) return true;
        win.Sleep(1);
    }
    return false;
}

fn selectIconImage(images: []const IconImage) IconImage {
    var best = images[0];
    for (images[1..]) |image| {
        if (image.width * image.height > best.width * best.height) best = image;
    }
    return best;
}

fn createIconFromImage(image: IconImage) win.HICON {
    var header = win.BITMAPV5HEADER{
        .bV5Width = @intCast(image.width),
        .bV5Height = -@as(win.LONG, @intCast(image.height)),
    };
    var bits: ?*anyopaque = null;
    const color = win.CreateDIBSection(null, &header, win.DIB_RGB_COLORS, &bits, null, 0);
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
        .fIcon = 1,
        .xHotspot = 0,
        .yHotspot = 0,
        .hbmMask = mask,
        .hbmColor = color,
    };
    return win.CreateIconIndirect(&icon_info);
}

fn createBlankCursor() win.HCURSOR {
    const width: u32 = @intCast(win.GetSystemMetrics(win.SM_CXCURSOR));
    const height: u32 = @intCast(win.GetSystemMetrics(win.SM_CYCURSOR));
    const pixels = std.heap.c_allocator.alloc(u8, width * height * 4) catch return null;
    defer std.heap.c_allocator.free(pixels);
    @memset(pixels, 0);
    if (pixels.len >= 4) pixels[3] = 1;

    const image = IconImage{
        .width = width,
        .height = height,
        .pixels = pixels.ptr,
    };
    return createCursorFromImage(image, 0, 0);
}

fn createCursorFromImage(image: IconImage, x_hot: u32, y_hot: u32) win.HCURSOR {
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
        .xHotspot = x_hot,
        .yHotspot = y_hot,
        .hbmMask = mask,
        .hbmColor = color,
    };
    return win.CreateIconIndirect(&icon_info);
}

fn windowFromHwnd(hwnd: win.HWND) ?*win.Window {
    const ptr_value = win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA);
    if (ptr_value == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(ptr_value)));
}

fn windowStyle(decorated: bool, resizable: bool) win.DWORD {
    if (!decorated) return win.WS_POPUP;
    var style = win.WS_OVERLAPPED | win.WS_CAPTION | win.WS_SYSMENU | win.WS_MINIMIZEBOX;
    if (resizable) style |= win.WS_THICKFRAME | win.WS_MAXIMIZEBOX;
    return style;
}

fn setStyleBit(hwnd: win.HWND, bit: win.DWORD, enabled: bool) void {
    const style: win.DWORD = @intCast(win.GetWindowLongPtrW(hwnd, win.GWL_STYLE));
    _ = win.SetWindowLongPtrW(hwnd, win.GWL_STYLE, @intCast(if (enabled) style | bit else style & ~bit));
    _ = win.SetWindowPos(hwnd, null, 0, 0, 0, 0, win.SWP_NOMOVE | win.SWP_NOSIZE | win.SWP_NOZORDER | win.SWP_NOACTIVATE | win.SWP_FRAMECHANGED);
}

fn setExStyleBit(hwnd: win.HWND, bit: win.DWORD, enabled: bool) void {
    const style: win.DWORD = @intCast(win.GetWindowLongPtrW(hwnd, win.GWL_EXSTYLE));
    _ = win.SetWindowLongPtrW(hwnd, win.GWL_EXSTYLE, @intCast(if (enabled) style | bit else style & ~bit));
    _ = win.SetWindowPos(hwnd, null, 0, 0, 0, 0, win.SWP_NOMOVE | win.SWP_NOSIZE | win.SWP_NOZORDER | win.SWP_NOACTIVATE | win.SWP_FRAMECHANGED);
}

fn cursorInClient(hwnd: win.HWND) bool {
    var point: win.POINT = undefined;
    if (win.GetCursorPos(&point) == 0) return false;
    if (win.WindowFromPoint(point) != hwnd) return false;
    var rect: win.RECT = undefined;
    _ = win.GetClientRect(hwnd, &rect);
    var top_left = win.POINT{ .x = rect.left, .y = rect.top };
    var bottom_right = win.POINT{ .x = rect.right, .y = rect.bottom };
    _ = win.ClientToScreen(hwnd, &top_left);
    _ = win.ClientToScreen(hwnd, &bottom_right);
    rect.left = top_left.x;
    rect.top = top_left.y;
    rect.right = bottom_right.x;
    rect.bottom = bottom_right.y;
    return point.x >= rect.left and point.x < rect.right and point.y >= rect.top and point.y < rect.bottom;
}

fn updateCursorImage(window: *win.Window) void {
    if (window.cursor_mode == 0 or window.cursor_mode == 3) {
        _ = win.SetCursor(if (window.cursor) |cursor| cursor else win.LoadCursorW(null, win.IDC_ARROW));
    } else {
        _ = win.SetCursor(blank_cursor);
    }
}

fn disableCursor(window: *win.Window) void {
    disabled_cursor_window = window;
    const pos = getCursorPos(@ptrCast(window));
    restore_cursor_pos_x = @floatFromInt(pos.x);
    restore_cursor_pos_y = @floatFromInt(pos.y);
    updateCursorImage(window);
    centerCursorInClient(window);
    captureCursor(window);
    if (window.raw_mouse_motion) setRawMouseMotion(window, true);
}

fn enableCursor(window: *win.Window) void {
    if (window.raw_mouse_motion) setRawMouseMotion(window, false);
    disabled_cursor_window = null;
    releaseCursorClip();
    setCursorPos(@ptrCast(window), restore_cursor_pos_x, restore_cursor_pos_y);
    updateCursorImage(window);
}

fn centerCursorInClient(window: *win.Window) void {
    setCursorPos(@ptrCast(window), @as(f64, @floatFromInt(window.width)) / 2.0, @as(f64, @floatFromInt(window.height)) / 2.0);
}

fn captureCursor(window: *win.Window) void {
    clipCursorToClient(window.handle);
    captured_cursor_window = window;
}

fn clipCursorToClient(hwnd: win.HWND) void {
    if (win.GetFocus() != hwnd) return;
    var rect: win.RECT = undefined;
    _ = win.GetClientRect(hwnd, &rect);
    var top_left = win.POINT{ .x = rect.left, .y = rect.top };
    var bottom_right = win.POINT{ .x = rect.right, .y = rect.bottom };
    _ = win.ClientToScreen(hwnd, &top_left);
    _ = win.ClientToScreen(hwnd, &bottom_right);
    rect.left = top_left.x;
    rect.top = top_left.y;
    rect.right = bottom_right.x;
    rect.bottom = bottom_right.y;
    _ = win.ClipCursor(&rect);
}

fn releaseCursorClip() void {
    _ = win.ClipCursor(null);
    captured_cursor_window = null;
}

fn setRawMouseMotion(window: *win.Window, enabled: bool) void {
    const device = win.RAWINPUTDEVICE{
        .usUsagePage = 0x01,
        .usUsage = 0x02,
        .dwFlags = if (enabled) 0 else win.RIDEV_REMOVE,
        .hwndTarget = if (enabled) window.handle else null,
    };
    _ = win.RegisterRawInputDevices(&device, 1, @sizeOf(win.RAWINPUTDEVICE));
}

fn buttonMask(button: i32) u8 {
    return @as(u8, 1) << @intCast(@max(0, @min(button, 7)));
}

fn adjustWindowRectForCurrentDpi(hwnd: win.HWND, rect: *win.RECT) void {
    adjustWindowRectForDpi(hwnd, rect, getDpiForWindow(hwnd));
}

fn adjustWindowRectForDpi(hwnd: win.HWND, rect: *win.RECT, dpi: win.UINT) void {
    const style: win.DWORD = @intCast(win.GetWindowLongPtrW(hwnd, win.GWL_STYLE));
    const ex_style: win.DWORD = @intCast(win.GetWindowLongPtrW(hwnd, win.GWL_EXSTYLE));
    if (win.adjust_window_rect_ex_for_dpi) |adjust| {
        if (adjust(rect, style, 0, ex_style, dpi) != 0) return;
    }
    {
        _ = win.AdjustWindowRectEx(rect, style, 0, ex_style);
    }
}

fn getDpiForWindow(hwnd: win.HWND) win.UINT {
    if (win.get_dpi_for_window) |get_dpi| {
        const dpi = get_dpi(hwnd);
        if (dpi != 0) return dpi;
    }
    const dc = win.GetDC(hwnd);
    defer _ = win.ReleaseDC(hwnd, dc);
    return @intCast(@max(win.USER_DEFAULT_SCREEN_DPI, win.GetDeviceCaps(dc, win.LOGPIXELSX)));
}

fn updateFramebufferTransparency(window: *win.Window) void {
    if (win.dwm_enable_blur_behind_window == null) return;

    const region = win.CreateRectRgn(0, 0, -1, -1);
    defer {
        if (region) |handle| _ = win.DeleteObject(handle);
    }

    const blur = win.DWM_BLURBEHIND{
        .dwFlags = win.DWM_BB_ENABLE | win.DWM_BB_BLURREGION,
        .fEnable = 1,
        .hRgnBlur = region,
        .fTransitionOnMaximized = 0,
    };
    _ = win.dwm_enable_blur_behind_window.?(window.handle, &blur);
}

fn acquireMonitor(window: *win.Window, native_monitor: *anyopaque, size: Size, refresh_rate: u32) void {
    if (!window.monitor_acquired and acquired_monitor_count == 0) {
        _ = win.SetThreadExecutionState(win.ES_CONTINUOUS | win.ES_DISPLAY_REQUIRED);
        _ = win.SystemParametersInfoW(win.SPI_GETMOUSETRAILS, 0, &mouse_trail_size, 0);
        _ = win.SystemParametersInfoW(win.SPI_SETMOUSETRAILS, 0, null, 0);
    }

    const current = monitor_module.getVideoMode(native_monitor);
    if (monitor_module.setVideoMode(native_monitor, .{
        .width = size.width,
        .height = size.height,
        .red_bits = current.red_bits,
        .green_bits = current.green_bits,
        .blue_bits = current.blue_bits,
        .refresh_rate = if (refresh_rate != 0) refresh_rate else current.refresh_rate,
    })) {
        if (!window.monitor_acquired) acquired_monitor_count += 1;
        window.monitor_acquired = true;
    } else if (!window.monitor_acquired and acquired_monitor_count == 0) {
        _ = win.SetThreadExecutionState(win.ES_CONTINUOUS);
        _ = win.SystemParametersInfoW(win.SPI_SETMOUSETRAILS, mouse_trail_size, null, 0);
    }
}

fn releaseMonitor(window: *win.Window, native_monitor: *anyopaque) void {
    if (!window.monitor_acquired) return;
    if (acquired_monitor_count > 0) acquired_monitor_count -= 1;
    if (acquired_monitor_count == 0) {
        _ = win.SetThreadExecutionState(win.ES_CONTINUOUS);
        _ = win.SystemParametersInfoW(win.SPI_SETMOUSETRAILS, mouse_trail_size, null, 0);
    }
    monitor_module.restoreVideoMode(native_monitor);
    window.monitor_acquired = false;
}

fn mouseButtonFromMessage(msg: win.UINT, wparam: win.WPARAM) i32 {
    return switch (msg) {
        win.WM_LBUTTONDOWN, win.WM_LBUTTONUP => 0,
        win.WM_RBUTTONDOWN, win.WM_RBUTTONUP => 1,
        win.WM_MBUTTONDOWN, win.WM_MBUTTONUP => 2,
        win.WM_XBUTTONDOWN, win.WM_XBUTTONUP => if (win.hiword(wparam) == 1) 3 else 4,
        else => 0,
    };
}

fn getKeyMods() u8 {
    var mods: u8 = 0;
    if ((@as(u16, @bitCast(win.GetKeyState(win.VK_SHIFT))) & 0x8000) != 0) mods |= 1 << 0;
    if ((@as(u16, @bitCast(win.GetKeyState(win.VK_CONTROL))) & 0x8000) != 0) mods |= 1 << 1;
    if ((@as(u16, @bitCast(win.GetKeyState(win.VK_MENU))) & 0x8000) != 0) mods |= 1 << 2;
    if ((@as(u16, @bitCast(win.GetKeyState(win.VK_LWIN))) & 0x8000) != 0 or (@as(u16, @bitCast(win.GetKeyState(win.VK_RWIN))) & 0x8000) != 0) mods |= 1 << 3;
    if ((win.GetKeyState(win.VK_CAPITAL) & 1) != 0) mods |= 1 << 4;
    if ((win.GetKeyState(win.VK_NUMLOCK) & 1) != 0) mods |= 1 << 5;
    return mods;
}

extern "user32" fn BeginPaint(hWnd: win.HWND, lpPaint: *win.PAINTSTRUCT) callconv(.winapi) win.HDC;
extern "user32" fn EndPaint(hWnd: win.HWND, lpPaint: *const win.PAINTSTRUCT) callconv(.winapi) win.BOOL;
