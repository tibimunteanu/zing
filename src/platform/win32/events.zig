const win = @import("types.zig");
const helper = @import("helper.zig");
const window = @import("window.zig");

pub fn poll() void {
    var msg: win.MSG = undefined;
    while (win.PeekMessageW(&msg, null, 0, 0, win.PM_REMOVE) != 0) {
        if (msg.message == win.WM_QUIT) {
            window.closeAllFromEvent();
        } else {
            _ = win.TranslateMessage(&msg);
            _ = win.DispatchMessageW(&msg);
        }
    }

    window.repairStuckModifierKeys();
    window.recenterDisabledCursor();
}

pub fn wait() void {
    _ = win.WaitMessage();
    poll();
}

pub fn waitTimeout(timeout: f64) void {
    const milliseconds: win.DWORD = @intFromFloat(timeout * 1000.0);
    _ = win.MsgWaitForMultipleObjects(0, null, 0, milliseconds, win.QS_ALLINPUT);
    poll();
}

pub fn postEmpty() void {
    helper.postEmpty();
}
