const win = @import("types.zig");

pub fn poll() void {
    var msg: win.MSG = undefined;
    while (win.PeekMessageW(&msg, null, 0, 0, win.PM_REMOVE) != 0) {
        _ = win.TranslateMessage(&msg);
        _ = win.DispatchMessageW(&msg);
    }
}

pub fn wait() void {
    var msg: win.MSG = undefined;
    if (win.GetMessageW(&msg, null, 0, 0) > 0) {
        _ = win.TranslateMessage(&msg);
        _ = win.DispatchMessageW(&msg);
    }
    poll();
}

pub fn waitTimeout(timeout: f64) void {
    const milliseconds: win.DWORD = if (timeout >= 4294967.0)
        win.INFINITE
    else
        @intFromFloat(@max(0.0, timeout * 1000.0));
    _ = win.MsgWaitForMultipleObjects(0, null, 0, milliseconds, win.QS_ALLINPUT);
    poll();
}

pub fn postEmpty() void {
    _ = win.PostMessageW(null, win.WM_APP_EMPTY, 0, 0);
}
