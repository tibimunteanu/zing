const std = @import("std");

const x11 = @import("types.zig");
const joystick = @import("joystick.zig");
const window = @import("window.zig");

const linux = std.os.linux;

var empty_event_pipe: [2]i32 = .{ -1, -1 };

pub fn poll() void {
    drainEmptyEvents();
    joystick.detectConnections();

    const display = x11.display orelse return;
    const xlib = &(x11.xlib orelse return);
    _ = xlib.XPending(display);
    while (xlib.XPending(display) > 0) {
        var event: x11.XEvent = undefined;
        _ = xlib.XNextEvent(display, &event);
        window.handleEvent(&event);
    }
    window.pollDisabledCursor();
    _ = xlib.XFlush(display);
}

pub fn wait() void {
    if (!waitForAnyEvent(null)) return;
    poll();
}

pub fn waitTimeout(timeout: f64) void {
    if (!waitForAnyEvent(timeout)) return;
    poll();
}

pub fn postEmpty() void {
    if (!ensurePipe()) return;
    var byte = [_]u8{0};
    while (true) {
        const rc = linux.write(empty_event_pipe[1], &byte, 1);
        switch (std.posix.errno(rc)) {
            .SUCCESS => return,
            .INTR => continue,
            else => return,
        }
    }
}

fn waitForAnyEvent(timeout: ?f64) bool {
    const display = x11.display orelse return false;
    const xlib = &(x11.xlib orelse return false);
    if (!ensurePipe()) return false;

    const timeout_ms: i32 = if (timeout) |value|
        @intFromFloat(@min(value * 1000.0, @as(f64, @floatFromInt(std.math.maxInt(i32)))))
    else
        -1;

    var fds = [_]linux.pollfd{
        .{ .fd = xlib.XConnectionNumber(display), .events = linux.POLL.IN, .revents = 0 },
        .{ .fd = empty_event_pipe[0], .events = linux.POLL.IN, .revents = 0 },
        .{ .fd = joystick.eventFd(), .events = linux.POLL.IN, .revents = 0 },
    };

    while (xlib.XPending(display) == 0) {
        const rc = linux.poll(&fds, fds.len, timeout_ms);
        switch (std.posix.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) return false;
                for (fds[1..]) |fd| {
                    if (fd.fd >= 0 and (fd.revents & linux.POLL.IN) != 0) return true;
                }
                if ((fds[0].revents & linux.POLL.IN) != 0) return true;
            },
            .INTR => continue,
            else => return false,
        }
    }

    return true;
}

fn ensurePipe() bool {
    if (empty_event_pipe[0] != -1) return true;
    var fds: [2]i32 = undefined;
    const rc = linux.pipe2(&fds, .{ .NONBLOCK = true, .CLOEXEC = true });
    if (std.posix.errno(rc) != .SUCCESS) return false;
    empty_event_pipe = fds;
    return true;
}

fn drainEmptyEvents() void {
    if (empty_event_pipe[0] == -1) return;
    var buffer: [64]u8 = undefined;
    while (true) {
        const rc = linux.read(empty_event_pipe[0], &buffer, buffer.len);
        switch (std.posix.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) return;
            },
            .INTR => continue,
            else => return,
        }
    }
}
