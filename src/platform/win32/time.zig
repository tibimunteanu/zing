const win = @import("types.zig");

var frequency: u64 = 1;

pub fn init() bool {
    var value: i64 = 0;
    if (win.QueryPerformanceFrequency(&value) == 0 or value <= 0) return false;
    frequency = @intCast(value);
    return true;
}

pub fn deinit() void {}

pub fn getTimerValue() u64 {
    var value: i64 = 0;
    _ = win.QueryPerformanceCounter(&value);
    return @intCast(value);
}

pub fn getTimerFrequency() u64 {
    return frequency;
}
