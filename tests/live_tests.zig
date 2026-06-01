const std = @import("std");
const zing = @import("zing");

const Events = zing.Events;
const Input = zing.Input;
const Monitor = zing.Monitor;
const Platform = zing.Platform;
const Window = zing.Window;

const CallbackState = struct {
    focus_count: usize = 0,
    pos_count: usize = 0,
    size_count: usize = 0,
    key_count: usize = 0,
    char_count: usize = 0,
    saw_a_press: bool = false,
    saw_a_char: bool = false,
    mouse_button_count: usize = 0,
    cursor_pos_count: usize = 0,
    scroll_count: usize = 0,
    last_key: Input.Key = .unknown,
    last_key_action: Input.Action = .release,
    last_char: u21 = 0,
    last_mouse_button: Input.MouseButton = .left,
    last_mouse_action: Input.Action = .release,
    last_cursor_x: f64 = 0,
    last_cursor_y: f64 = 0,
    last_scroll_x: f64 = 0,
    last_scroll_y: f64 = 0,
};

var callback_state: CallbackState = .{};

fn resetCallbacks() void {
    callback_state = .{};
}

fn focusCallback(_: Window, _: bool) void {
    callback_state.focus_count += 1;
}

fn posCallback(_: Window, _: i32, _: i32) void {
    callback_state.pos_count += 1;
}

fn sizeCallback(_: Window, _: u32, _: u32) void {
    callback_state.size_count += 1;
}

fn keyCallback(_: Window, key: Input.Key, _: i32, action: Input.Action, _: Input.Modifiers) void {
    callback_state.key_count += 1;
    callback_state.last_key = key;
    callback_state.last_key_action = action;
    if (key == .a and action == .press) callback_state.saw_a_press = true;
}

fn charCallback(_: Window, codepoint: u21) void {
    callback_state.char_count += 1;
    callback_state.last_char = codepoint;
    if (codepoint == 'a') callback_state.saw_a_char = true;
}

fn mouseButtonCallback(_: Window, button: Input.MouseButton, action: Input.Action, _: Input.Modifiers) void {
    callback_state.mouse_button_count += 1;
    callback_state.last_mouse_button = button;
    callback_state.last_mouse_action = action;
}

fn cursorPosCallback(_: Window, x: f64, y: f64) void {
    callback_state.cursor_pos_count += 1;
    callback_state.last_cursor_x = x;
    callback_state.last_cursor_y = y;
}

fn scrollCallback(_: Window, xoffset: f64, yoffset: f64) void {
    callback_state.scroll_count += 1;
    callback_state.last_scroll_x = xoffset;
    callback_state.last_scroll_y = yoffset;
}

fn pump(seconds: f64) !void {
    Platform.Tests.pumpEvents(seconds);
    try Events.poll();
}

fn openLiveWindow(title: [:0]const u8) !Window {
    const window = try Window.create(420, 260, title, null, null, .{
        .visible = true,
        .focused = true,
        .client_api = .no_api,
    });
    try window.setPos(.{ .x = 80, .y = 80 });
    try window.show();
    try window.focus();
    try pump(0.05);
    return window;
}

test "live macOS window lifecycle and geometry" {
    try Window.initSystem();
    defer Window.deinitSystem();

    resetCallbacks();
    const window = try openLiveWindow("Zing Live Geometry");
    defer window.destroy() catch {};

    try window.setFocusCallback(focusCallback);
    try window.setPosCallback(posCallback);
    try window.setSizeCallback(sizeCallback);

    try window.setPos(.{ .x = 120, .y = 120 });
    try window.setSize(.{ .width = 500, .height = 300 });
    try pump(0.10);

    const size = try window.getSize();
    try std.testing.expectEqual(@as(u32, 500), size.width);
    try std.testing.expect(callback_state.size_count > 0);
    try std.testing.expect(try window.getAttrib(.visible));
}

test "live macOS keyboard input" {
    try Window.initSystem();
    defer Window.deinitSystem();

    resetCallbacks();
    const window = try openLiveWindow("Zing Live Keyboard");
    defer window.destroy() catch {};

    try window.setKeyCallback(keyCallback);
    try window.setCharCallback(charCallback);

    const native = try window.nativeHandle();
    try std.testing.expect(Platform.Tests.postKey(native, try Input.getKeyScancode(.a), true, 0));
    try pump(0.05);

    try std.testing.expect(callback_state.key_count > 0);
    try std.testing.expect(callback_state.saw_a_press);
    try std.testing.expect(callback_state.saw_a_char);
    try std.testing.expectEqual(Input.Action.press, try window.getKey(.a));

    try std.testing.expect(Platform.Tests.postKey(native, try Input.getKeyScancode(.a), false, 0));
    try pump(0.05);
    try std.testing.expectEqual(Input.Action.release, try window.getKey(.a));
}

test "live macOS mouse and scroll input" {
    try Window.initSystem();
    defer Window.deinitSystem();

    resetCallbacks();
    const window = try openLiveWindow("Zing Live Mouse");
    defer window.destroy() catch {};

    try window.setMouseButtonCallback(mouseButtonCallback);
    try window.setCursorPosCallback(cursorPosCallback);
    try window.setScrollCallback(scrollCallback);

    const native = try window.nativeHandle();
    try std.testing.expect(Platform.Tests.postMouseMove(native, 40.0, 50.0));
    try pump(0.05);
    try std.testing.expect(callback_state.cursor_pos_count > 0);
    try std.testing.expectApproxEqAbs(@as(f64, 40.0), callback_state.last_cursor_x, 4.0);
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), callback_state.last_cursor_y, 4.0);

    try std.testing.expect(Platform.Tests.postMouseButton(native, 0, true, 40.0, 50.0, 0));
    try pump(0.05);
    try std.testing.expect(callback_state.mouse_button_count > 0);
    try std.testing.expectEqual(Input.MouseButton.left, callback_state.last_mouse_button);
    try std.testing.expectEqual(Input.Action.press, callback_state.last_mouse_action);
    try std.testing.expectEqual(Input.Action.press, try window.getMouseButton(.left));

    try std.testing.expect(Platform.Tests.postMouseButton(native, 0, false, 40.0, 50.0, 0));
    try pump(0.05);
    try std.testing.expectEqual(Input.Action.release, try window.getMouseButton(.left));

    try std.testing.expect(Platform.Tests.postScroll(native, 10.0, -20.0));
    try pump(0.05);
    try std.testing.expect(callback_state.scroll_count > 0);
}

test "live macOS monitors expose usable geometry" {
    try Monitor.initSystem(std.testing.allocator);
    defer Monitor.deinitSystem();

    try Monitor.poll();
    const monitors = try Monitor.getMonitors(std.testing.allocator);
    defer std.testing.allocator.free(monitors);

    try std.testing.expect(monitors.len > 0);
    for (monitors) |monitor| {
        const work_area = try monitor.getWorkArea();
        const scale = try monitor.getContentScale();
        const modes = try monitor.getVideoModes(std.testing.allocator);
        defer std.testing.allocator.free(modes);
        try std.testing.expect(modes.len > 0);
        _ = work_area;
        try std.testing.expect(scale.x_scale > 0.0);
        try std.testing.expect(scale.y_scale > 0.0);
    }
}
