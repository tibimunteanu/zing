const std = @import("std");
const input = @import("input.zig");
const cursor_module = @import("cursor.zig");
const win = @import("types.zig");

pub const Config = extern struct {
    width: u32,
    height: u32,
    title: [*:0]const u8,
    resizable: bool,
    visible: bool,
    decorated: bool,
    focused: bool,
    floating: bool,
    maximized: bool,
    transparent_framebuffer: bool,
    mouse_passthrough: bool,
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
    char: *const fn (usize, u32) void,
    char_mods: *const fn (usize, u32, u8) void,
    mouse_button: *const fn (usize, i32, i32, u8) void,
    cursor_pos: *const fn (usize, f64, f64) void,
    cursor_enter: *const fn (usize, bool) void,
    scroll: *const fn (usize, f64, f64) void,
    refresh: *const fn (usize) void,
    drop: *const fn (usize, usize, [*][*:0]const u8) void,
};

const class_name: [:0]const win.WCHAR = std.unicode.utf8ToUtf16LeStringLiteral("ZingWin32Window");
var callbacks_: ?EventCallbacks = null;
var initialized = false;
var class_atom: win.ATOM = 0;

pub fn setEventCallbacks(new_callbacks: EventCallbacks) void {
    callbacks_ = new_callbacks;
}

pub fn init() bool {
    if (initialized) return true;
    win.instance = @ptrCast(win.GetModuleHandleW(null));
    _ = win.SetProcessDPIAware();

    const wc = win.WNDCLASSEXW{
        .style = 0x0003,
        .lpfnWndProc = wndProc,
        .hInstance = win.instance,
        .hCursor = win.LoadCursorW(null, win.IDC_ARROW),
        .lpszClassName = class_name.ptr,
    };
    class_atom = win.RegisterClassExW(&wc);
    if (class_atom == 0) return false;
    initialized = true;
    return true;
}

pub fn deinit() void {
    if (class_atom != 0) _ = win.UnregisterClassW(class_name.ptr, win.instance);
    class_atom = 0;
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
    native_window.* = .{ .handle = null, .width = config.width, .height = config.height };
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
    _ = win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, @intCast(@intFromPtr(native_window)));
    win.DragAcceptFiles(hwnd, 1);
    if (config.transparent_framebuffer) _ = win.SetLayeredWindowAttributes(hwnd, 0, 255, win.LWA_ALPHA);
    if (config.maximized) _ = win.ShowWindow(hwnd, win.SW_SHOWMAXIMIZED);
    if (config.visible) _ = win.ShowWindow(hwnd, if (config.maximized) win.SW_SHOWMAXIMIZED else win.SW_SHOWNORMAL);
    if (config.focused) {
        _ = win.BringWindowToTop(hwnd);
        _ = win.SetForegroundWindow(hwnd);
        _ = win.SetFocus(hwnd);
    }
    return @ptrCast(native_window);
}

pub fn destroy(handle: *anyopaque) void {
    const window = native(handle);
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
    const hwnd = native(handle).handle;
    var rect = win.RECT{ .left = 0, .top = 0, .right = @intCast(size.width), .bottom = @intCast(size.height) };
    _ = win.AdjustWindowRectEx(&rect, @intCast(win.GetWindowLongPtrW(hwnd, win.GWL_STYLE)), 0, @intCast(win.GetWindowLongPtrW(hwnd, win.GWL_EXSTYLE)));
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
    const dc = win.GetDC(native(handle).handle);
    defer _ = win.ReleaseDC(native(handle).handle, dc);
    return .{
        .x_scale = @as(f32, @floatFromInt(win.GetDeviceCaps(dc, win.LOGPIXELSX))) / @as(f32, @floatFromInt(win.USER_DEFAULT_SCREEN_DPI)),
        .y_scale = @as(f32, @floatFromInt(win.GetDeviceCaps(dc, win.LOGPIXELSY))) / @as(f32, @floatFromInt(win.USER_DEFAULT_SCREEN_DPI)),
    };
}

pub fn getOpacity(_: *anyopaque) f32 {
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
    var point = win.POINT{ .x = @intFromFloat(x), .y = @intFromFloat(y) };
    _ = win.ClientToScreen(native(handle).handle, &point);
    _ = win.SetCursorPos(point.x, point.y);
}

pub fn setCursor(handle: *anyopaque, cursor_handle: ?*anyopaque) void {
    const window = native(handle);
    window.cursor = if (cursor_handle) |value|
        (@as(*cursor_module.Cursor, @ptrCast(@alignCast(value)))).handle
    else
        win.LoadCursorW(null, win.IDC_ARROW);
    if (cursorInClient(window.handle)) _ = win.SetCursor(window.cursor);
}

pub fn setInputMode(handle: *anyopaque, mode: c_int, value: c_int) void {
    const window = native(handle);
    if (mode == 1) {
        const device = win.RAWINPUTDEVICE{
            .usUsagePage = 0x01,
            .usUsage = 0x02,
            .dwFlags = if (value != 0) win.RIDEV_INPUTSINK else win.RIDEV_REMOVE,
            .hwndTarget = if (value != 0) window.handle else null,
        };
        _ = win.RegisterRawInputDevices(&device, 1, @sizeOf(win.RAWINPUTDEVICE));
        return;
    }
    if (mode != 0) return;
    window.cursor_mode = value;
    if (value == 1 or value == 2) {
        _ = win.SetCursor(null);
    } else {
        _ = win.SetCursor(if (window.cursor) |cursor| cursor else win.LoadCursorW(null, win.IDC_ARROW));
    }
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
    if (win.OpenClipboard(null) == 0) return;
    defer _ = win.CloseClipboard();
    _ = win.EmptyClipboard();
    _ = win.SetClipboardData(win.CF_UNICODETEXT, memory);
}

pub fn getClipboardString() ?[*:0]const u8 {
    if (win.IsClipboardFormatAvailable(win.CF_UNICODETEXT) == 0) return null;
    if (win.OpenClipboard(null) == 0) return null;
    defer _ = win.CloseClipboard();
    const data = win.GetClipboardData(win.CF_UNICODETEXT) orelse return null;
    const wide: [*:0]const win.WCHAR = @ptrCast(@alignCast(win.GlobalLock(data) orelse return null));
    defer _ = win.GlobalUnlock(data);
    return (win.wideToUtf8Z(std.heap.c_allocator, wide) catch return null).ptr;
}

fn wndProc(hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) callconv(.winapi) win.LRESULT {
    if (msg == win.WM_CREATE) return win.DefWindowProcW(hwnd, msg, wparam, lparam);
    const window = windowFromHwnd(hwnd) orelse return win.DefWindowProcW(hwnd, msg, wparam, lparam);

    switch (msg) {
        win.WM_CLOSE => {
            window.should_close = true;
            callbacks().close(window.callback_id);
            return 0;
        },
        win.WM_MOVE => {
            callbacks().pos(window.callback_id, win.getX(lparam), win.getY(lparam));
            return 0;
        },
        win.WM_SIZE => {
            const width: u32 = win.loword(@bitCast(lparam));
            const height: u32 = win.hiword(@bitCast(lparam));
            window.width = width;
            window.height = height;
            callbacks().size(window.callback_id, width, height);
            callbacks().framebuffer_size(window.callback_id, width, height);
            const scale = getContentScale(@ptrCast(window));
            callbacks().content_scale(window.callback_id, scale.x_scale, scale.y_scale);
            callbacks().iconify(window.callback_id, wparam == win.SIZE_MINIMIZED);
            callbacks().maximize(window.callback_id, wparam == win.SIZE_MAXIMIZED);
            return 0;
        },
        win.WM_SETFOCUS => {
            callbacks().focus(window.callback_id, true);
            return 0;
        },
        win.WM_KILLFOCUS => {
            callbacks().focus(window.callback_id, false);
            return 0;
        },
        win.WM_PAINT => {
            var ps: win.PAINTSTRUCT = undefined;
            _ = BeginPaint(hwnd, &ps);
            _ = EndPaint(hwnd, &ps);
            callbacks().refresh(window.callback_id);
            return 0;
        },
        win.WM_GETMINMAXINFO => {
            const info: *win.MINMAXINFO = @ptrFromInt(@as(usize, @bitCast(lparam)));
            if (window.min_width > 0) info.ptMinTrackSize.x = @intCast(window.min_width);
            if (window.min_height > 0) info.ptMinTrackSize.y = @intCast(window.min_height);
            if (window.max_width > 0) info.ptMaxTrackSize.x = @intCast(window.max_width);
            if (window.max_height > 0) info.ptMaxTrackSize.y = @intCast(window.max_height);
            return 0;
        },
        win.WM_KEYDOWN, win.WM_SYSKEYDOWN => return keyMessage(window, wparam, lparam, 1),
        win.WM_KEYUP, win.WM_SYSKEYUP => return keyMessage(window, wparam, lparam, 0),
        win.WM_CHAR, win.WM_UNICHAR => {
            if (wparam == win.UNICODE_NOCHAR) return 1;
            const codepoint: u32 = @intCast(wparam);
            callbacks().char_mods(window.callback_id, codepoint, getKeyMods());
            callbacks().char(window.callback_id, codepoint);
            return 0;
        },
        win.WM_MOUSEMOVE => {
            if (!window.cursor_tracked) {
                var track = win.TRACKMOUSEEVENT{ .dwFlags = win.TME_LEAVE, .hwndTrack = hwnd };
                _ = win.TrackMouseEvent(&track);
                window.cursor_tracked = true;
                callbacks().cursor_enter(window.callback_id, true);
            }
            callbacks().cursor_pos(window.callback_id, @floatFromInt(win.getX(lparam)), @floatFromInt(win.getY(lparam)));
            return 0;
        },
        win.WM_MOUSELEAVE => {
            window.cursor_tracked = false;
            callbacks().cursor_enter(window.callback_id, false);
            return 0;
        },
        win.WM_LBUTTONDOWN, win.WM_RBUTTONDOWN, win.WM_MBUTTONDOWN, win.WM_XBUTTONDOWN => {
            _ = win.SetCapture(hwnd);
            callbacks().mouse_button(window.callback_id, mouseButtonFromMessage(msg, wparam), 1, getKeyMods());
            return 0;
        },
        win.WM_LBUTTONUP, win.WM_RBUTTONUP, win.WM_MBUTTONUP, win.WM_XBUTTONUP => {
            _ = win.ReleaseCapture();
            callbacks().mouse_button(window.callback_id, mouseButtonFromMessage(msg, wparam), 0, getKeyMods());
            return 0;
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
            if (window.cursor_mode == 1 or window.cursor_mode == 2) {
                _ = win.SetCursor(null);
            } else {
                _ = win.SetCursor(if (window.cursor) |cursor| cursor else win.LoadCursorW(null, win.IDC_ARROW));
            }
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

    var path_buffers: [64][:0]u8 = undefined;
    var path_ptrs: [64][*:0]const u8 = undefined;
    var converted_count: usize = 0;
    const capped_count = @min(count, path_ptrs.len);
    defer {
        for (path_buffers[0..converted_count]) |path| std.heap.c_allocator.free(path);
    }

    var i: usize = 0;
    while (i < capped_count) : (i += 1) {
        const wide_len = win.DragQueryFileW(drop, @intCast(i), null, 0);
        const wide = std.heap.c_allocator.allocSentinel(win.WCHAR, wide_len, 0) catch continue;
        defer std.heap.c_allocator.free(wide);
        _ = win.DragQueryFileW(drop, @intCast(i), wide.ptr, wide_len + 1);
        const utf8 = std.unicode.wtf16LeToWtf8AllocZ(std.heap.c_allocator, wide[0..wide_len]) catch continue;
        path_buffers[converted_count] = utf8;
        path_ptrs[converted_count] = utf8.ptr;
        converted_count += 1;
    }
    if (converted_count > 0) callbacks().drop(window.callback_id, converted_count, &path_ptrs);
}

fn keyMessage(window: *win.Window, wparam: win.WPARAM, lparam: win.LPARAM, action: i32) win.LRESULT {
    const scancode: u32 = @intCast((lparam >> 16) & 0x1ff);
    callbacks().key(window.callback_id, input.translateKey(@intCast(wparam), scancode), @intCast(scancode), action, getKeyMods());
    return 0;
}

fn callbacks() EventCallbacks {
    return callbacks_.?;
}

fn native(handle: *anyopaque) *win.Window {
    return @ptrCast(@alignCast(handle));
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
    _ = win.ScreenToClient(hwnd, &point);
    var rect: win.RECT = undefined;
    _ = win.GetClientRect(hwnd, &rect);
    return point.x >= rect.left and point.x < rect.right and point.y >= rect.top and point.y < rect.bottom;
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
