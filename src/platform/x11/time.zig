const std = @import("std");

var start: u64 = 0;

pub fn init() bool {
    start = now();
    return true;
}

pub fn deinit() void {}

pub fn getTimerValue() u64 {
    return now() - start;
}

pub fn getTimerFrequency() u64 {
    return std.time.ns_per_s;
}

fn now() u64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}
