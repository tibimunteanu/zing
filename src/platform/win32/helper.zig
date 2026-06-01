const std = @import("std");
const win = @import("types.zig");

const class_name: [:0]const win.WCHAR = std.unicode.utf8ToUtf16LeStringLiteral("ZingWin32Helper");
const title: [:0]const win.WCHAR = std.unicode.utf8ToUtf16LeStringLiteral("Zing message window");
const GUID_DEVINTERFACE_HID = win.GUID{
    .Data1 = 0x4d1e55b2,
    .Data2 = 0xf16f,
    .Data3 = 0x11cf,
    .Data4 = .{ 0x88, 0xcb, 0x00, 0x11, 0x11, 0x00, 0x00, 0x30 },
};

var class_atom: win.ATOM = 0;
var helper_window: win.HWND = null;
var device_notification: win.HDEVNOTIFY = null;
var refs: usize = 0;
var device_arrival_callback: ?*const fn () void = null;
var device_removal_callback: ?*const fn () void = null;

pub fn setDeviceChangeCallbacks(arrival: ?*const fn () void, removal: ?*const fn () void) void {
    device_arrival_callback = arrival;
    device_removal_callback = removal;
}

pub fn retain() bool {
    if (!ensure()) return false;
    refs += 1;
    return true;
}

pub fn release() void {
    if (refs == 0) return;
    refs -= 1;
    if (refs != 0) return;

    if (device_notification) |notification| {
        _ = win.UnregisterDeviceNotification(notification);
        device_notification = null;
    }
    if (helper_window) |hwnd| {
        _ = win.DestroyWindow(hwnd);
        helper_window = null;
    }
    if (class_atom != 0) {
        _ = win.UnregisterClassW(class_name.ptr, win.instance);
        class_atom = 0;
    }
}

pub fn ensure() bool {
    if (helper_window != null) return true;
    if (win.instance == null) win.instance = @ptrCast(win.GetModuleHandleW(null));

    const wc = win.WNDCLASSEXW{
        .style = 0x0020,
        .lpfnWndProc = helperWndProc,
        .hInstance = win.instance,
        .lpszClassName = class_name.ptr,
    };
    class_atom = win.RegisterClassExW(&wc);
    if (class_atom == 0) return false;

    helper_window = win.CreateWindowExW(
        0,
        class_name.ptr,
        title.ptr,
        win.WS_CLIPSIBLINGS | win.WS_CLIPCHILDREN,
        0,
        0,
        1,
        1,
        null,
        null,
        win.instance,
        null,
    ) orelse return false;

    _ = win.ShowWindow(helper_window, win.SW_HIDE);

    var filter = win.DEV_BROADCAST_DEVICEINTERFACE_W{
        .dbcc_size = @sizeOf(win.DEV_BROADCAST_DEVICEINTERFACE_W),
        .dbcc_devicetype = win.DBT_DEVTYP_DEVICEINTERFACE,
        .dbcc_classguid = GUID_DEVINTERFACE_HID,
    };
    device_notification = win.RegisterDeviceNotificationW(@ptrCast(helper_window), &filter, win.DEVICE_NOTIFY_WINDOW_HANDLE);

    var msg: win.MSG = undefined;
    while (win.PeekMessageW(&msg, helper_window, 0, 0, win.PM_REMOVE) != 0) {
        _ = win.TranslateMessage(&msg);
        _ = win.DispatchMessageW(&msg);
    }

    return true;
}

pub fn handle() win.HWND {
    return if (ensure()) helper_window else null;
}

pub fn postEmpty() void {
    _ = win.PostMessageW(handle(), win.WM_NULL, 0, 0);
}

fn helperWndProc(hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) callconv(.winapi) win.LRESULT {
    switch (msg) {
        win.WM_DEVICECHANGE => {
            const hdr: ?*const win.DEV_BROADCAST_HDR = if (lparam != 0)
                @ptrFromInt(@as(usize, @bitCast(lparam)))
            else
                null;

            if (hdr) |value| {
                if (value.dbch_devicetype == win.DBT_DEVTYP_DEVICEINTERFACE) {
                    if (wparam == win.DBT_DEVICEARRIVAL) {
                        if (device_arrival_callback) |callback| callback();
                    } else if (wparam == win.DBT_DEVICEREMOVECOMPLETE) {
                        if (device_removal_callback) |callback| callback();
                    }
                }
            }
        },
        else => {},
    }

    return win.DefWindowProcW(hwnd, msg, wparam, lparam);
}
