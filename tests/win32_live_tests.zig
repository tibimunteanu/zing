const std = @import("std");
const zing = @import("zing");

const Cursor = zing.Cursor;
const Events = zing.Events;
const Input = zing.Input;
const Monitor = zing.Monitor;
const Native = zing.Native;
const Time = zing.Time;
const Window = zing.Window;

const allocator = std.heap.c_allocator;
const result_path = "C:\\Users\\Public\\zing-win32-live-tests.txt";

var close_events: usize = 0;
var pos_events: usize = 0;
var size_events: usize = 0;
var focus_events: usize = 0;
var framebuffer_events: usize = 0;
var cursor_events: usize = 0;

fn expect(value: bool, message: []const u8) !void {
    if (!value) {
        std.debug.print("FAIL: {s}\n", .{message});
        var buffer: [512]u8 = undefined;
        const result = try std.fmt.bufPrint(&buffer, "FAIL: {s}\n", .{message});
        try writeResult(result);
        return error.TestFailed;
    }
}

fn expectEqual(comptime T: type, expected: T, actual: T, message: []const u8) !void {
    if (expected != actual) {
        std.debug.print("FAIL: {s}: expected {any}, got {any}\n", .{ message, expected, actual });
        var buffer: [512]u8 = undefined;
        const result = try std.fmt.bufPrint(&buffer, "FAIL: {s}: expected {any}, got {any}\n", .{ message, expected, actual });
        try writeResult(result);
        return error.TestFailed;
    }
}

fn expectInputMode(expected: Window.InputMode, actual: Window.InputMode, message: []const u8) !void {
    if (!std.meta.eql(expected, actual)) {
        std.debug.print("FAIL: {s}: expected {any}, got {any}\n", .{ message, expected, actual });
        var buffer: [512]u8 = undefined;
        const result = try std.fmt.bufPrint(&buffer, "FAIL: {s}: expected {any}, got {any}\n", .{ message, expected, actual });
        try writeResult(result);
        return error.TestFailed;
    }
}

fn expectString(expected: []const u8, actual: []const u8, message: []const u8) !void {
    if (!std.mem.eql(u8, expected, actual)) {
        std.debug.print("FAIL: {s}: expected '{s}', got '{s}'\n", .{ message, expected, actual });
        var buffer: [512]u8 = undefined;
        const result = try std.fmt.bufPrint(&buffer, "FAIL: {s}: expected '{s}', got '{s}'\n", .{ message, expected, actual });
        try writeResult(result);
        return error.TestFailed;
    }
}

fn pumpEvents(iterations: usize) !void {
    for (0..iterations) |_| {
        try Events.poll();
        try Events.waitTimeout(0.01);
    }
}

fn onClose(_: Window) void {
    close_events += 1;
}

fn onPos(_: Window, _: i32, _: i32) void {
    pos_events += 1;
}

fn onSize(_: Window, _: u32, _: u32) void {
    size_events += 1;
}

fn onFocus(_: Window, _: bool) void {
    focus_events += 1;
}

fn onFramebufferSize(_: Window, _: u32, _: u32) void {
    framebuffer_events += 1;
}

fn onCursorPos(_: Window, _: f64, _: f64) void {
    cursor_events += 1;
}

pub fn main() void {
    run() catch |err| {
        if (err == error.TestFailed) std.process.exit(1);
        var buffer: [256]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "FAIL: {s}\n", .{@errorName(err)}) catch "FAIL\n";
        writeResult(message) catch {};
        std.process.exit(1);
    };

    writeResult("OK\n") catch {};
}

fn run() !void {
    std.debug.print("zing win32 live tests: start\n", .{});

    try Time.initSystem();
    defer Time.deinitSystem();

    try Input.initSystem();
    defer Input.deinitSystem();

    try Monitor.initSystem(allocator);
    defer Monitor.deinitSystem();

    try Window.initSystem();
    defer Window.deinitSystem();

    try expect(try Time.get() >= 0.0, "time starts at or above zero");
    try Time.set(0.25);
    try expect(try Time.getTimerFrequency() > 0, "timer frequency is available");

    try expect(try Input.rawMouseMotionSupported(), "raw mouse motion is reported on Win32");
    try expect(try Input.getKeyScancode(.a) > 0, "A scancode is available");
    if (try Input.getKeyName(.a, null)) |name| {
        try expect(name.len > 0, "A key name is non-empty");
    }

    const monitors = try Monitor.getMonitors(allocator);
    defer allocator.free(monitors);
    try expect(monitors.len > 0, "at least one monitor is enumerated");

    const primary = try Monitor.getPrimary();
    const work_area = try primary.getWorkArea();
    try expect(work_area.width > 0 and work_area.height > 0, "primary monitor has a usable work area");
    const modes = try primary.getVideoModes(allocator);
    defer allocator.free(modes);
    try expect(modes.len > 0, "primary monitor exposes video modes");
    const current_mode = try primary.getVideoMode();
    try expect(current_mode.width > 0 and current_mode.height > 0, "primary monitor exposes current mode");
    _ = try Native.getMonitorNativeHandle(primary);

    const window = try Window.create(320, 240, "Zing Win32 Live", null, null, .{
        .visible = true,
        .focused = true,
        .client_api = .no_api,
    });
    defer window.destroy() catch {};

    try window.setCloseCallback(onClose);
    try window.setPosCallback(onPos);
    try window.setSizeCallback(onSize);
    try window.setFocusCallback(onFocus);
    try window.setFramebufferSizeCallback(onFramebufferSize);
    try window.setCursorPosCallback(onCursorPos);

    _ = try Native.getWin32Window(window);
    try expect(!(try window.shouldClose()), "new window should not be closing");
    try expect(try window.getAttrib(.client_api), "window uses no client API");

    try expectString("Zing Win32 Live", try window.getTitle(), "initial title is tracked");
    try window.setTitle("Zing Win32 Live Updated");
    try expectString("Zing Win32 Live Updated", try window.getTitle(), "updated title is tracked");

    try window.setPos(.{ .x = 80, .y = 80 });
    try window.setSize(.{ .width = 400, .height = 300 });
    try pumpEvents(8);

    const size = try window.getSize();
    try expectEqual(u32, 400, size.width, "client width updates");
    try expectEqual(u32, 300, size.height, "client height updates");
    const framebuffer_size = try window.getFramebufferSize();
    try expect(framebuffer_size.width > 0 and framebuffer_size.height > 0, "framebuffer size is valid");

    try window.setSizeLimits(.{ .width = 160, .height = 120 }, .{ .width = 800, .height = 600 });
    try window.setAspectRatio(.{ .numerator = 4, .denominator = 3 });
    try window.setAspectRatio(null);
    try window.setSizeLimits(null, null);

    try window.setOpacity(0.95);
    try window.setAttrib(.floating, true);
    try expect(try window.getAttrib(.floating), "floating attribute updates");
    try window.setAttrib(.floating, false);

    try window.setInputMode(.{ .sticky_keys = .enabled });
    try expectInputMode(.{ .sticky_keys = .enabled }, try window.getInputMode(.sticky_keys), "sticky keys mode updates");
    try window.setInputMode(.{ .sticky_mouse_buttons = .enabled });
    try expectInputMode(.{ .sticky_mouse_buttons = .enabled }, try window.getInputMode(.sticky_mouse_buttons), "sticky mouse mode updates");
    try window.setInputMode(.{ .raw_mouse_motion = .enabled });
    try expectInputMode(.{ .raw_mouse_motion = .enabled }, try window.getInputMode(.raw_mouse_motion), "raw mouse mode updates");
    try window.setInputMode(.{ .raw_mouse_motion = .disabled });

    try window.setCursorPos(.{ .x = 24.0, .y = 32.0 });
    try pumpEvents(4);
    _ = try window.getCursorPos();

    const arrow = try Cursor.createStandard(.arrow);
    defer arrow.destroy() catch {};
    try window.setCursor(arrow);
    try window.setCursor(null);

    var pixels = [_]u8{255} ** (16 * 16 * 4);
    const custom = try Cursor.create(.{ .width = 16, .height = 16, .pixels = &pixels }, 0, 0);
    defer custom.destroy() catch {};
    try window.setCursor(custom);
    try window.setCursor(null);

    try Window.setClipboardString("zing win32 clipboard");
    const clipboard = try Window.getClipboardString();
    try expectString("zing win32 clipboard", clipboard, "clipboard round trips");

    try window.iconify();
    try pumpEvents(4);
    try window.restore();
    try window.maximize();
    try pumpEvents(4);
    try window.restore();
    try window.hide();
    try pumpEvents(2);
    try window.show();
    try window.focus();
    try window.requestAttention();
    try pumpEvents(8);

    try window.setShouldClose(true);
    try expect(try window.shouldClose(), "should close flag updates");
    try window.setShouldClose(false);
    try expect(!(try window.shouldClose()), "should close flag clears");

    try expect(size_events > 0, "size callback fired");
    try expect(framebuffer_events > 0, "framebuffer callback fired");
    _ = pos_events;
    _ = focus_events;
    _ = cursor_events;
    _ = close_events;

    std.debug.print("zing win32 live tests: ok\n", .{});
}

fn writeResult(message: []const u8) !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = result_path, .data = message });
}
