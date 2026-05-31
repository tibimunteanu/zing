const std = @import("std");
const zing = @import("zing");

const Cursor = zing.Cursor;
const Errors = zing.Errors;
const Events = zing.Events;
const Input = zing.Input;
const Joystick = zing.Joystick;
const Monitor = zing.Monitor;
const Native = zing.Native;
const Time = zing.Time;
const VulkanWSI = zing.VulkanWSI;
const Window = zing.Window;
const vk = zing.vk;

fn errorCallback(_: Errors.Code, _: [:0]const u8) void {}
fn monitorCallback(_: Monitor.Monitor, _: Monitor.Event) void {}
fn joystickCallback(_: Joystick.Joystick, _: Joystick.Event) void {}
fn windowCloseCallback(_: Window) void {}
fn windowPosCallback(_: Window, _: i32, _: i32) void {}
fn windowSizeCallback(_: Window, _: u32, _: u32) void {}
fn windowRefreshCallback(_: Window) void {}
fn windowFocusCallback(_: Window, _: bool) void {}
fn windowIconifyCallback(_: Window, _: bool) void {}
fn windowMaximizeCallback(_: Window, _: bool) void {}
fn windowFramebufferSizeCallback(_: Window, _: u32, _: u32) void {}
fn windowContentScaleCallback(_: Window, _: f32, _: f32) void {}
fn windowKeyCallback(_: Window, _: Input.Key, _: i32, _: Input.Action, _: Input.Modifiers) void {}
fn windowCharCallback(_: Window, _: u21) void {}
fn windowCharModsCallback(_: Window, _: u21, _: Input.Modifiers) void {}
fn windowMouseButtonCallback(_: Window, _: Input.MouseButton, _: Input.Action, _: Input.Modifiers) void {}
fn windowCursorPosCallback(_: Window, _: f64, _: f64) void {}
fn windowCursorEnterCallback(_: Window, _: bool) void {}
fn windowScrollCallback(_: Window, _: f64, _: f64) void {}
fn windowDropCallback(_: Window, _: []const [:0]const u8) void {}

test "errors public surface" {
    try std.testing.expect(Errors.setCallback(errorCallback) == null);
    try std.testing.expect(Errors.setCallback(null) == errorCallback);
    try std.testing.expect(Errors.get() == null);
    try std.testing.expect(Errors.getString() == null);
    Errors.clear();
}

test "time public surface" {
    try Time.initSystem();
    defer Time.deinitSystem();

    try std.testing.expect(try Time.get() >= 0.0);
    try Time.set(1.25);
    try std.testing.expect(try Time.getTimerValue() > 0);
    try std.testing.expect(try Time.getTimerFrequency() > 0);
}

test "events public surface" {
    try Events.poll();
    try Events.postEmpty();
    try Events.wait();
    try Events.waitTimeout(0.001);
    try std.testing.expectError(error.InvalidValue, Events.waitTimeout(std.math.nan(f64)));
    try std.testing.expectError(error.InvalidValue, Events.waitTimeout(-0.001));
}

test "input public surface" {
    try Input.initSystem();
    defer Input.deinitSystem();

    _ = try Input.rawMouseMotionSupported();
    try std.testing.expectEqual(@as(i32, 0x00), try Input.getKeyScancode(.a));
    try std.testing.expectEqualStrings("A", (try Input.getKeyName(.a, null)).?);
    try std.testing.expect((try Input.getKeyName(.f1, null)) == null);
    try std.testing.expectError(error.InvalidValue, Input.getKeyName(.unknown, -1));
    const mods = Input.Modifiers{ .shift = true, .alt = true };
    try std.testing.expect(mods.shift);
    try std.testing.expect(mods.alt);
    try std.testing.expectEqual(@as(usize, 0), Input.mouseButtonIndex(.one));
    try std.testing.expectEqual(@as(usize, 0), Input.mouseButtonIndex(.left));
    try std.testing.expectEqual(@as(usize, 1), Input.mouseButtonIndex(.two));
    try std.testing.expectEqual(@as(usize, 1), Input.mouseButtonIndex(.right));
}

test "monitor public surface" {
    const allocator = std.testing.allocator;

    try Monitor.initSystem(allocator);
    defer Monitor.deinitSystem();

    const monitors = try Monitor.getMonitors(allocator);
    defer allocator.free(monitors);
    try std.testing.expect(monitors.len > 0);

    const primary = try Monitor.getPrimary();
    _ = try primary.getPos();
    _ = try primary.getWorkArea();
    _ = try primary.getPhysicalSize();
    _ = try primary.getContentScale();
    _ = try primary.getName();
    try primary.setUserPointer(null);
    _ = try primary.getUserPointer();

    const modes = try primary.getVideoModes(allocator);
    defer allocator.free(modes);
    try std.testing.expect(modes.len > 0);
    _ = try primary.getVideoMode();

    try std.testing.expect(try Monitor.setCallback(monitorCallback) == null);
    try Monitor.poll();
}

test "cursor public surface" {
    var pixels = [_]u8{255} ** (16 * 16 * 4);
    const image = Cursor.Image{
        .width = 16,
        .height = 16,
        .pixels = &pixels,
    };

    const custom = try Cursor.create(image, 0, 0);
    defer custom.destroy() catch {};

    const standard = try Cursor.createStandard(.arrow);
    defer standard.destroy() catch {};
}

test "joystick public surface" {
    try Joystick.initSystem();
    defer Joystick.deinitSystem();

    const mapping_count_before = Joystick.gamepadMappingCount();
    try std.testing.expect(try Joystick.setCallback(joystickCallback) == null);
    try Joystick.updateGamepadMappings("030000000d0f00005e00000000000000,Test Controller,a:b0,b:b1\n");
    try std.testing.expectEqual(mapping_count_before + 1, Joystick.gamepadMappingCount());

    const joystick = Joystick.Joystick{ .id = .one };
    _ = try joystick.present();
    _ = try joystick.getAxes();
    _ = try joystick.getButtons();
    _ = try joystick.getHats();
    if (try joystick.present()) {
        _ = try joystick.getName();
        _ = try joystick.getGuid();
    }
    try joystick.setUserPointer(null);
    _ = try joystick.getUserPointer();
    if (try joystick.isGamepad()) {
        _ = try joystick.getGamepadName();
        _ = try joystick.getGamepadState();
    }
}

test "window public surface" {
    try Window.initSystem();
    defer Window.deinitSystem();

    try Window.defaultHints();
    try Window.setHint(.visible, false);
    try Window.setHint(.visible, true);
    try std.testing.expectError(error.ApiUnavailable, Window.setHint(.client_api, false));

    try std.testing.expectError(error.InvalidValue, Window.create(0, 360, "Bad", null, null, .{}));

    const window = try Window.create(640, 360, "Zing Test", null, null, .{});
    defer window.destroy() catch {};

    try std.testing.expectError(error.NoWindowContext, Window.create(640, 360, "Bad Share", null, window, .{}));

    _ = try window.shouldClose();
    try window.setShouldClose(false);
    try window.setTitle("Zing Test Updated");
    try std.testing.expectEqualStrings("Zing Test Updated", try window.getTitle());
    _ = try window.getPos();
    try window.setPos(.{ .x = 10, .y = 10 });
    _ = try window.getSize();
    try window.setSize(.{ .width = 800, .height = 450 });
    try window.setSizeLimits(.{ .width = 320, .height = 180 }, .{ .width = 1920, .height = 1080 });
    try window.setSizeLimits(null, null);
    try std.testing.expectError(error.InvalidValue, window.setSizeLimits(.{ .width = 0, .height = 180 }, null));
    try std.testing.expectError(error.InvalidValue, window.setSizeLimits(.{ .width = 640, .height = 480 }, .{ .width = 320, .height = 240 }));
    try window.setAspectRatio(.{ .numerator = 16, .denominator = 9 });
    try window.setAspectRatio(null);
    try std.testing.expectError(error.InvalidValue, window.setAspectRatio(.{ .numerator = 0, .denominator = 9 }));
    _ = try window.getFramebufferSize();
    _ = try window.getFrameSize();
    _ = try window.getContentScale();
    _ = try window.getOpacity();
    try window.setOpacity(1.0);
    try std.testing.expectError(error.InvalidValue, window.setOpacity(-0.1));
    try std.testing.expectError(error.InvalidValue, window.setOpacity(1.1));
    try window.iconify();
    try window.restore();
    try window.maximize();
    try window.show();
    try window.hide();
    try window.focus();
    try window.requestAttention();
    _ = try window.getMonitor();
    try window.setMonitor(null, .{ .x = 0, .y = 0 }, .{ .width = 640, .height = 360 }, null);
    try std.testing.expectError(error.InvalidValue, window.setMonitor(null, .{ .x = 0, .y = 0 }, .{ .width = 0, .height = 360 }, null));
    try std.testing.expectError(error.InvalidValue, window.setSize(.{ .width = 0, .height = 450 }));
    _ = try window.getAttrib(.iconified);
    try window.setAttrib(.floating, false);
    try window.setAttrib(.focus_on_show, false);
    try window.setAttrib(.mouse_passthrough, false);
    try std.testing.expect(!try window.getAttrib(.focus_on_show));
    try std.testing.expect(!try window.getAttrib(.mouse_passthrough));
    try std.testing.expect(try window.getAttrib(.client_api));
    try window.setUserPointer(null);
    _ = try window.getUserPointer();
    _ = try window.getKey(.a);
    _ = try window.getMouseButton(.left);
    _ = try window.getCursorPos();
    try window.setCursorPos(.{ .x = 1.0, .y = 1.0 });
    try window.setInputMode(.{ .cursor = .normal });
    try std.testing.expectEqual(Window.InputMode{ .cursor = .normal }, try window.getInputMode(.cursor));
    try window.setInputMode(.{ .sticky_keys = .enabled });
    try std.testing.expectEqual(Window.InputMode{ .sticky_keys = .enabled }, try window.getInputMode(.sticky_keys));
    try window.setInputMode(.{ .sticky_mouse_buttons = .enabled });
    try std.testing.expectEqual(Window.InputMode{ .sticky_mouse_buttons = .enabled }, try window.getInputMode(.sticky_mouse_buttons));
    try window.setInputMode(.{ .cursor = .disabled });
    try window.setCursorPos(.{ .x = 11.0, .y = 13.0 });
    try std.testing.expectEqual(Input.CursorPos{ .x = 11.0, .y = 13.0 }, try window.getCursorPos());
    try std.testing.expectError(error.FeatureUnimplemented, window.setInputMode(.{ .cursor = .captured }));
    try window.setInputMode(.{ .cursor = .normal });
    try std.testing.expectError(error.PlatformError, window.setInputMode(.{ .raw_mouse_motion = .enabled }));
    try window.setCursor(null);
    try std.testing.expectError(error.FeatureUnavailable, window.setIcon(&.{}));
    try Window.setClipboardString("zing clipboard test");
    const clipboard_string = Window.getClipboardString() catch |err| switch (err) {
        error.FormatUnavailable => null,
        else => return err,
    };
    if (clipboard_string) |value| try std.testing.expectEqualStrings("zing clipboard test", value);

    try window.setCloseCallback(windowCloseCallback);
    try window.setPosCallback(windowPosCallback);
    try window.setSizeCallback(windowSizeCallback);
    try window.setRefreshCallback(windowRefreshCallback);
    try window.setFocusCallback(windowFocusCallback);
    try window.setIconifyCallback(windowIconifyCallback);
    try window.setMaximizeCallback(windowMaximizeCallback);
    try window.setFramebufferSizeCallback(windowFramebufferSizeCallback);
    try window.setContentScaleCallback(windowContentScaleCallback);
    try window.setKeyCallback(windowKeyCallback);
    try window.setCharCallback(windowCharCallback);
    try window.setCharModsCallback(windowCharModsCallback);
    try window.setMouseButtonCallback(windowMouseButtonCallback);
    try window.setCursorPosCallback(windowCursorPosCallback);
    try window.setCursorEnterCallback(windowCursorEnterCallback);
    try window.setScrollCallback(windowScrollCallback);
    try window.setDropCallback(windowDropCallback);
}

test "vulkan WSI public surface" {
    try VulkanWSI.initSystem(vulkanTestLoader);
    defer VulkanWSI.deinitSystem();

    try std.testing.expect(try VulkanWSI.supported());
    const extensions = try VulkanWSI.getRequiredInstanceExtensions();
    try std.testing.expect(extensions.len > 0);
    try std.testing.expect(try VulkanWSI.getPhysicalDevicePresentationSupport(.null_handle, .null_handle, 0));

    var surface: vk.SurfaceKHR = .null_handle;
    const window = Window{ .id = 1 };
    try std.testing.expectError(error.ApiUnavailable, VulkanWSI.createWindowSurface(.null_handle, window, null, &surface));
}

test "vulkan WSI accepts MVK macOS surface fallback" {
    try VulkanWSI.initSystem(vulkanMvkTestLoader);
    defer VulkanWSI.deinitSystem();

    try std.testing.expect(try VulkanWSI.supported());
    const extensions = try VulkanWSI.getRequiredInstanceExtensions();
    try std.testing.expectEqualStrings("VK_KHR_surface", std.mem.span(extensions[0]));
    try std.testing.expectEqualStrings("VK_MVK_macos_surface", std.mem.span(extensions[1]));
}

fn vulkanTestLoader(_: vk.Instance, name: [*:0]const u8) callconv(vk.vulkan_call_conv) vk.PfnVoidFunction {
    if (std.mem.eql(u8, std.mem.span(name), "vkEnumerateInstanceExtensionProperties")) {
        return @ptrCast(&vulkanEnumerateInstanceExtensionProperties);
    }
    return null;
}

fn vulkanEnumerateInstanceExtensionProperties(
    layer_name: ?[*:0]const u8,
    property_count: *u32,
    properties: ?[*]vk.ExtensionProperties,
) callconv(vk.vulkan_call_conv) vk.Result {
    _ = layer_name;

    const names = [_][*:0]const u8{
        "VK_KHR_surface",
        "VK_EXT_metal_surface",
    };

    if (properties == null) {
        property_count.* = names.len;
        return .success;
    }

    const count = @min(property_count.*, names.len);
    for (names[0..count], 0..) |name, i| {
        @memset(&properties.?[i].extension_name, 0);
        const text = std.mem.span(name);
        @memcpy(properties.?[i].extension_name[0..text.len], text);
        properties.?[i].spec_version = 1;
    }
    property_count.* = @intCast(count);
    return .success;
}

fn vulkanMvkTestLoader(_: vk.Instance, name: [*:0]const u8) callconv(vk.vulkan_call_conv) vk.PfnVoidFunction {
    if (std.mem.eql(u8, std.mem.span(name), "vkEnumerateInstanceExtensionProperties")) {
        return @ptrCast(&vulkanMvkEnumerateInstanceExtensionProperties);
    }
    return null;
}

fn vulkanMvkEnumerateInstanceExtensionProperties(
    layer_name: ?[*:0]const u8,
    property_count: *u32,
    properties: ?[*]vk.ExtensionProperties,
) callconv(vk.vulkan_call_conv) vk.Result {
    _ = layer_name;

    const names = [_][*:0]const u8{
        "VK_KHR_surface",
        "VK_MVK_macos_surface",
    };

    if (properties == null) {
        property_count.* = names.len;
        return .success;
    }

    const count = @min(property_count.*, names.len);
    for (names[0..count], 0..) |name, i| {
        @memset(&properties.?[i].extension_name, 0);
        const text = std.mem.span(name);
        @memcpy(properties.?[i].extension_name[0..text.len], text);
        properties.?[i].spec_version = 1;
    }
    property_count.* = @intCast(count);
    return .success;
}

test "native public surface" {
    try Window.initSystem();
    defer Window.deinitSystem();
    try Monitor.initSystem(std.testing.allocator);
    defer Monitor.deinitSystem();

    const window = try Window.create(320, 180, "Native Test", null, null, .{ .visible = false });
    defer window.destroy() catch {};
    const monitor = try Monitor.getPrimary();

    _ = try Native.getCocoaWindow(window);
    _ = try Native.getCocoaView(window);
    _ = try Native.getMonitorNativeHandle(monitor);
}

test "objc public surface" {
    if (@import("builtin").os.tag != .macos) return;

    const objc = zing.objc;
    std.testing.refAllDecls(objc);

    const NSObject = objc.getClass("NSObject").?;
    const object = NSObject.msgSend(objc.Object, "alloc", .{});
    defer object.msgSend(void, "dealloc", .{});

    try std.testing.expectEqualStrings("NSObject", object.getClassName());
}
