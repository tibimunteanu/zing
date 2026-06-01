const std = @import("std");
const Input = @import("input.zig");
const Monitor = @import("monitor.zig").Monitor;
const CursorModule = @import("cursor.zig");
const Cursor = CursorModule.Cursor;
const Errors = @import("errors.zig");
const platform = @import("platform.zig");

const Window = @This();

id: usize,

const max_windows = 128;
const max_title_len = 256;
const key_count = Input.key_count;
const mouse_button_count = Input.mouse_button_count;

const State = struct {
    native: *anyopaque,
    title: [max_title_len:0]u8 = @splat(0),
    monitor: ?Monitor = null,
    selected_cursor: ?Cursor = null,
    resizable: bool = true,
    decorated: bool = true,
    auto_iconify: bool = true,
    floating: bool = false,
    focus_on_show: bool = true,
    mouse_passthrough: bool = false,
    transparent_framebuffer: bool = false,
    min_size: ?Size = null,
    max_size: ?Size = null,
    aspect_ratio: ?AspectRatio = null,
    cursor_mode: Input.CursorMode = .normal,
    sticky_keys: bool = false,
    sticky_mouse_buttons: bool = false,
    lock_key_mods: bool = false,
    raw_mouse_motion: bool = false,
    key_states: [key_count]Input.Action = @splat(.release),
    sticky_key_states: [key_count]bool = @splat(false),
    mouse_button_states: [mouse_button_count]Input.Action = @splat(.release),
    sticky_mouse_button_states: [mouse_button_count]bool = @splat(false),
    cursor_pos: Input.CursorPos = .{ .x = 0.0, .y = 0.0 },
    close_callback: ?CloseCallback = null,
    pos_callback: ?PosCallback = null,
    size_callback: ?SizeCallback = null,
    refresh_callback: ?RefreshCallback = null,
    focus_callback: ?FocusCallback = null,
    iconify_callback: ?IconifyCallback = null,
    maximize_callback: ?MaximizeCallback = null,
    framebuffer_size_callback: ?FramebufferSizeCallback = null,
    content_scale_callback: ?ContentScaleCallback = null,
    key_callback: ?KeyCallback = null,
    char_callback: ?CharCallback = null,
    char_mods_callback: ?CharModsCallback = null,
    mouse_button_callback: ?MouseButtonCallback = null,
    cursor_pos_callback: ?CursorPosCallback = null,
    cursor_enter_callback: ?CursorEnterCallback = null,
    scroll_callback: ?ScrollCallback = null,
    drop_callback: ?DropCallback = null,
};

var initialized = false;
var windows: [max_windows]?State = @splat(null);
var current_hints: Hints = .{};

pub const Size = struct {
    width: u32,
    height: u32,
};

pub const Pos = struct {
    x: i32,
    y: i32,
};

pub const FrameSize = struct {
    left: u32,
    top: u32,
    right: u32,
    bottom: u32,
};

pub const ContentScale = struct {
    x_scale: f32,
    y_scale: f32,
};

pub const AspectRatio = struct {
    numerator: u32,
    denominator: u32,
};

pub const Hints = struct {
    resizable: bool = true,
    visible: bool = true,
    decorated: bool = true,
    focused: bool = true,
    auto_iconify: bool = true,
    floating: bool = false,
    maximized: bool = false,
    center_cursor: bool = true,
    transparent_framebuffer: bool = false,
    focus_on_show: bool = true,
    mouse_passthrough: bool = false,
    scale_to_monitor: bool = false,
    scale_framebuffer: bool = true,
    client_api: ClientAPI = .no_api,

    pub const ClientAPI = enum {
        no_api,
    };
};

pub const Hint = enum {
    resizable,
    visible,
    decorated,
    focused,
    auto_iconify,
    floating,
    maximized,
    center_cursor,
    transparent_framebuffer,
    focus_on_show,
    mouse_passthrough,
    scale_to_monitor,
    scale_framebuffer,
    client_api,
};

pub const Attribute = enum {
    focused,
    iconified,
    maximized,
    hovered,
    visible,
    resizable,
    decorated,
    auto_iconify,
    floating,
    transparent_framebuffer,
    focus_on_show,
    mouse_passthrough,
    client_api,
};

pub const InputMode = union(enum) {
    cursor: Input.CursorMode,
    sticky_keys: Input.StickyMode,
    sticky_mouse_buttons: Input.StickyMode,
    lock_key_mods: Input.LockKeyModsMode,
    raw_mouse_motion: Input.RawMouseMotionMode,
};

pub const InputModeName = enum {
    cursor,
    sticky_keys,
    sticky_mouse_buttons,
    lock_key_mods,
    raw_mouse_motion,
};

pub const CloseCallback = *const fn (Window) void;
pub const PosCallback = *const fn (Window, i32, i32) void;
pub const SizeCallback = *const fn (Window, u32, u32) void;
pub const RefreshCallback = *const fn (Window) void;
pub const FocusCallback = *const fn (Window, bool) void;
pub const IconifyCallback = *const fn (Window, bool) void;
pub const MaximizeCallback = *const fn (Window, bool) void;
pub const FramebufferSizeCallback = *const fn (Window, u32, u32) void;
pub const ContentScaleCallback = *const fn (Window, f32, f32) void;
pub const KeyCallback = *const fn (Window, Input.Key, i32, Input.Action, Input.Modifiers) void;
pub const CharCallback = *const fn (Window, u21) void;
pub const CharModsCallback = *const fn (Window, u21, Input.Modifiers) void;
pub const MouseButtonCallback = *const fn (Window, Input.MouseButton, Input.Action, Input.Modifiers) void;
pub const CursorPosCallback = *const fn (Window, f64, f64) void;
pub const CursorEnterCallback = *const fn (Window, bool) void;
pub const ScrollCallback = *const fn (Window, f64, f64) void;
pub const DropCallback = *const fn (Window, []const [:0]const u8) void;

pub fn defaultHints() !void {
    try requireInit();
    current_hints = .{};
}

pub fn setHint(hint: Hint, value: bool) !void {
    try requireInit();
    switch (hint) {
        .resizable => current_hints.resizable = value,
        .visible => current_hints.visible = value,
        .decorated => current_hints.decorated = value,
        .focused => current_hints.focused = value,
        .auto_iconify => current_hints.auto_iconify = value,
        .floating => current_hints.floating = value,
        .maximized => current_hints.maximized = value,
        .center_cursor => current_hints.center_cursor = value,
        .transparent_framebuffer => current_hints.transparent_framebuffer = value,
        .focus_on_show => current_hints.focus_on_show = value,
        .mouse_passthrough => current_hints.mouse_passthrough = value,
        .scale_to_monitor => current_hints.scale_to_monitor = value,
        .scale_framebuffer => current_hints.scale_framebuffer = value,
        .client_api => {
            if (!value) {
                Errors.report(.api_unavailable, "Only Vulkan windows are supported", .{});
                return error.ApiUnavailable;
            }
            current_hints.client_api = .no_api;
        },
    }
}

pub fn createWithHints(width: u32, height: u32, title: [:0]const u8, monitor: ?Monitor, share: ?Window) !Window {
    return create(width, height, title, monitor, share, current_hints);
}

pub fn initSystem() !void {
    if (initialized) return;

    platform.Window.setEventCallbacks(.{
        .close = platformWindowClose,
        .pos = platformWindowPos,
        .size = platformWindowSize,
        .focus = platformWindowFocus,
        .iconify = platformWindowIconify,
        .maximize = platformWindowMaximize,
        .framebuffer_size = platformWindowFramebufferSize,
        .content_scale = platformWindowContentScale,
        .key = platformWindowKey,
        .char = platformWindowChar,
        .char_mods = platformWindowCharMods,
        .mouse_button = platformWindowMouseButton,
        .cursor_pos = platformWindowCursorPos,
        .cursor_enter = platformWindowCursorEnter,
        .scroll = platformWindowScroll,
        .refresh = platformWindowRefresh,
        .drop = platformWindowDrop,
    });

    if (!platform.Window.init()) {
        Errors.report(.platform_error, "failed to initialize platform window system", .{});
        return error.PlatformError;
    }

    initialized = true;
}

pub fn deinitSystem() void {
    for (&windows) |*entry| {
        if (entry.*) |state| {
            platform.Window.destroy(state.native);
            entry.* = null;
        }
    }

    platform.Window.deinit();
    initialized = false;
}

pub fn create(width: u32, height: u32, title: [:0]const u8, monitor: ?Monitor, share: ?Window, hints: Hints) !Window {
    try requireInit();

    if (width == 0 or height == 0) {
        Errors.report(.invalid_value, "invalid window size {d}x{d}", .{ width, height });
        return error.InvalidValue;
    }

    if (share != null) {
        Errors.report(.no_window_context, "Vulkan windows cannot share contexts", .{});
        return error.NoWindowContext;
    }

    const native = blk: {
        const config = platform.Window.Config{
            .width = width,
            .height = height,
            .title = title.ptr,
            .resizable = hints.resizable,
            .visible = hints.visible,
            .decorated = hints.decorated,
            .focused = hints.focused,
            .auto_iconify = hints.auto_iconify,
            .floating = hints.floating,
            .maximized = hints.maximized,
            .center_cursor = hints.center_cursor,
            .scale_to_monitor = hints.scale_to_monitor,
            .scale_framebuffer = hints.scale_framebuffer,
            .transparent_framebuffer = hints.transparent_framebuffer,
            .mouse_passthrough = hints.mouse_passthrough,
        };
        break :blk platform.Window.create(&config) orelse {
            Errors.report(.platform_error, "failed to create platform window", .{});
            return error.PlatformError;
        };
    };

    var state = State{
        .native = native,
        .monitor = monitor,
        .resizable = hints.resizable,
        .decorated = hints.decorated,
        .auto_iconify = hints.auto_iconify,
        .floating = hints.floating,
        .focus_on_show = hints.focus_on_show,
        .mouse_passthrough = hints.mouse_passthrough,
        .transparent_framebuffer = hints.transparent_framebuffer,
    };
    copyTitle(&state, title);

    const id = try insert(state);
    platform.Window.setCallbackId(native, id);
    if (monitor) |value| {
        const native_monitor = try @import("monitor.zig").nativeHandle(value);
        platform.Window.setMonitor(
            native,
            native_monitor,
            .{ .x = 0, .y = 0 },
            .{ .width = width, .height = height },
            0,
        );
    }
    return .{ .id = id };
}

pub fn destroy(self: Window) !void {
    var state = try remove(self);
    clearCallbacks(&state);
    platform.Window.destroy(state.native);
}

pub fn shouldClose(self: Window) !bool {
    const state = try getState(self);
    return platform.Window.shouldClose(state.native);
}

pub fn setShouldClose(self: Window, value: bool) !void {
    const state = try getState(self);
    platform.Window.setShouldClose(state.native, value);
}

pub fn setTitle(self: Window, title: [:0]const u8) !void {
    const state = try getStatePtr(self);
    copyTitle(state, title);
    platform.Window.setTitle(state.native, title.ptr);
}

pub fn getTitle(self: Window) ![:0]const u8 {
    const state = try getStatePtr(self);
    return std.mem.sliceTo(&state.title, 0);
}

pub fn getPos(self: Window) !Pos {
    const state = try getState(self);
    const pos = platform.Window.getPos(state.native);
    return .{ .x = pos.x, .y = pos.y };
}

pub fn setPos(self: Window, pos: Pos) !void {
    const state = try getState(self);
    if (state.monitor != null) return;
    platform.Window.setPos(state.native, .{ .x = pos.x, .y = pos.y });
}

pub fn getSize(self: Window) !Size {
    const state = try getState(self);
    const size = platform.Window.getSize(state.native);
    return .{ .width = size.width, .height = size.height };
}

pub fn setSize(self: Window, size: Size) !void {
    const state = try getState(self);
    if (size.width == 0 or size.height == 0) {
        Errors.report(.invalid_value, "invalid window size {d}x{d}", .{ size.width, size.height });
        return error.InvalidValue;
    }
    platform.Window.setSize(state.native, .{ .width = size.width, .height = size.height });
}

pub fn setSizeLimits(self: Window, min_size: ?Size, max_size: ?Size) !void {
    const state = try getStatePtr(self);
    if (min_size) |min| {
        if (min.width == 0 or min.height == 0) {
            Errors.report(.invalid_value, "invalid window minimum size {d}x{d}", .{ min.width, min.height });
            return error.InvalidValue;
        }
    }
    if (max_size) |max| {
        if (max.width == 0 or max.height == 0) {
            Errors.report(.invalid_value, "invalid window maximum size {d}x{d}", .{ max.width, max.height });
            return error.InvalidValue;
        }
        if (min_size) |min| {
            if (max.width < min.width or max.height < min.height) {
                Errors.report(.invalid_value, "invalid window maximum size {d}x{d}", .{ max.width, max.height });
                return error.InvalidValue;
            }
        }
    }

    state.min_size = min_size;
    state.max_size = max_size;
    if (state.monitor != null or !state.resizable) return;
    platform.Window.setSizeLimits(state.native, toPlatformOptionalSize(min_size), toPlatformOptionalSize(max_size));
}

pub fn setAspectRatio(self: Window, aspect_ratio: ?AspectRatio) !void {
    const state = try getStatePtr(self);
    if (aspect_ratio) |ratio| {
        if (ratio.numerator == 0 or ratio.denominator == 0) {
            Errors.report(.invalid_value, "invalid window aspect ratio {d}:{d}", .{ ratio.numerator, ratio.denominator });
            return error.InvalidValue;
        }
    }

    state.aspect_ratio = aspect_ratio;
    if (state.monitor != null or !state.resizable) return;
    if (aspect_ratio) |ratio| {
        platform.Window.setAspectRatio(state.native, ratio.numerator, ratio.denominator);
        return;
    }
    platform.Window.clearAspectRatio(state.native);
}

pub fn getFramebufferSize(self: Window) !Size {
    const state = try getState(self);
    const size = platform.Window.getFramebufferSize(state.native);
    return .{ .width = size.width, .height = size.height };
}

pub fn getFrameSize(self: Window) !FrameSize {
    const state = try getState(self);
    const frame = platform.Window.getFrameSize(state.native);
    return .{ .left = frame.left, .top = frame.top, .right = frame.right, .bottom = frame.bottom };
}

pub fn getContentScale(self: Window) !ContentScale {
    const state = try getState(self);
    const scale = platform.Window.getContentScale(state.native);
    return .{ .x_scale = scale.x_scale, .y_scale = scale.y_scale };
}

pub fn getOpacity(self: Window) !f32 {
    const state = try getState(self);
    return platform.Window.getOpacity(state.native);
}

pub fn setOpacity(self: Window, opacity: f32) !void {
    const state = try getState(self);
    if (std.math.isNan(opacity) or opacity < 0.0 or opacity > 1.0) {
        Errors.report(.invalid_value, "invalid window opacity {d}", .{opacity});
        return error.InvalidValue;
    }
    platform.Window.setOpacity(state.native, opacity);
}

pub fn iconify(self: Window) !void {
    const state = try getState(self);
    platform.Window.iconify(state.native);
}

pub fn restore(self: Window) !void {
    const state = try getState(self);
    platform.Window.restore(state.native);
}

pub fn maximize(self: Window) !void {
    const state = try getState(self);
    if (state.monitor != null) return;
    platform.Window.maximize(state.native);
}

pub fn show(self: Window) !void {
    const state = try getState(self);
    if (state.monitor != null) return;
    platform.Window.show(state.native);
    if (state.focus_on_show) platform.Window.focus(state.native);
}

pub fn hide(self: Window) !void {
    const state = try getState(self);
    if (state.monitor != null) return;
    platform.Window.hide(state.native);
}

pub fn focus(self: Window) !void {
    const state = try getState(self);
    platform.Window.focus(state.native);
}

pub fn requestAttention(self: Window) !void {
    const state = try getState(self);
    platform.Window.requestAttention(state.native);
}

pub fn getMonitor(self: Window) !?Monitor {
    return (try getState(self)).monitor;
}

pub fn setMonitor(self: Window, monitor: ?Monitor, pos: Pos, size: Size, refresh_rate: ?u32) !void {
    if (size.width == 0 or size.height == 0) {
        Errors.report(.invalid_value, "invalid window size {d}x{d}", .{ size.width, size.height });
        return error.InvalidValue;
    }
    if (refresh_rate) |rate| {
        if (rate == 0) {
            Errors.report(.invalid_value, "invalid refresh rate {d}", .{rate});
            return error.InvalidValue;
        }
    }
    const state = try getStatePtr(self);
    const previous_monitor = state.monitor;
    state.monitor = monitor;
    const native_monitor = if (monitor) |value| try @import("monitor.zig").nativeHandle(value) else null;
    platform.Window.setMonitor(
        state.native,
        native_monitor,
        .{ .x = pos.x, .y = pos.y },
        .{ .width = size.width, .height = size.height },
        refresh_rate orelse 0,
    );
    if (!sameMonitor(previous_monitor, monitor) and monitor == null and state.resizable) {
        platform.Window.setSizeLimits(state.native, toPlatformOptionalSize(state.min_size), toPlatformOptionalSize(state.max_size));
        if (state.aspect_ratio) |ratio| {
            platform.Window.setAspectRatio(state.native, ratio.numerator, ratio.denominator);
        } else {
            platform.Window.clearAspectRatio(state.native);
        }
    }
}

fn sameMonitor(a: ?Monitor, b: ?Monitor) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    return a.?.id == b.?.id;
}

pub fn setIcon(self: Window, images: []const CursorModule.Image) !void {
    const state = try getState(self);
    for (images) |image| {
        if (image.width == 0 or image.height == 0) {
            Errors.report(.invalid_value, "invalid window icon dimensions", .{});
            return error.InvalidValue;
        }
        if (image.pixels.len < image.width * image.height * 4) {
            Errors.report(.invalid_value, "window icon pixel buffer is too small", .{});
            return error.InvalidValue;
        }
    }
    const platform_images = try std.heap.c_allocator.alloc(platform.Window.IconImage, images.len);
    defer std.heap.c_allocator.free(platform_images);
    for (platform_images, images) |*out, image| {
        out.* = .{
            .width = image.width,
            .height = image.height,
            .pixels = image.pixels.ptr,
        };
    }
    if (!platform.Window.setIcon(state.native, platform_images.ptr, platform_images.len)) {
        Errors.report(.feature_unavailable, "regular window icons are not supported on this platform", .{});
        return error.FeatureUnavailable;
    }
}

pub fn getAttrib(self: Window, attribute: Attribute) !bool {
    const state = try getState(self);
    return switch (attribute) {
        .resizable => state.resizable,
        .decorated => state.decorated,
        .auto_iconify => state.auto_iconify,
        .floating => state.floating,
        .transparent_framebuffer => state.transparent_framebuffer,
        .focus_on_show => state.focus_on_show,
        .mouse_passthrough => state.mouse_passthrough,
        .client_api => true,
        else => platform.Window.getAttribute(state.native, @intFromEnum(attribute)),
    };
}

pub fn setAttrib(self: Window, attribute: Attribute, value: bool) !void {
    const state = try getStatePtr(self);
    switch (attribute) {
        .auto_iconify => {
            state.auto_iconify = value;
            return;
        },
        .focus_on_show => {
            state.focus_on_show = value;
            return;
        },
        .resizable => state.resizable = value,
        .decorated => state.decorated = value,
        .floating => state.floating = value,
        .mouse_passthrough => state.mouse_passthrough = value,
        else => {
            Errors.report(.invalid_enum, "window attribute cannot be set", .{});
            return error.InvalidEnum;
        },
    }
    if (state.monitor != null and attribute != .mouse_passthrough) return;
    platform.Window.setAttribute(state.native, @intFromEnum(attribute), value);
}

pub fn setUserPointer(self: Window, pointer: ?*anyopaque) !void {
    const state = try getState(self);
    platform.Window.setUserPointer(state.native, pointer);
}

pub fn getUserPointer(self: Window) !?*anyopaque {
    const state = try getState(self);
    return platform.Window.getUserPointer(state.native);
}

pub fn getKey(self: Window, key: Input.Key) !Input.Action {
    const state = try getStatePtr(self);
    if (state.sticky_key_states[@intFromEnum(key)]) {
        state.sticky_key_states[@intFromEnum(key)] = false;
        return .press;
    }
    return state.key_states[@intFromEnum(key)];
}

pub fn getMouseButton(self: Window, button: Input.MouseButton) !Input.Action {
    const state = try getStatePtr(self);
    const index = Input.mouseButtonIndex(button);
    if (state.sticky_mouse_button_states[index]) {
        state.sticky_mouse_button_states[index] = false;
        return .press;
    }
    return state.mouse_button_states[index];
}

pub fn getCursorPos(self: Window) !Input.CursorPos {
    const state = try getState(self);
    if (state.cursor_mode == .disabled) return state.cursor_pos;
    const pos = platform.Window.getCursorPos(state.native);
    return .{ .x = @floatFromInt(pos.x), .y = @floatFromInt(pos.y) };
}

pub fn setCursorPos(self: Window, pos: Input.CursorPos) !void {
    const state = try getStatePtr(self);
    if (!std.math.isFinite(pos.x) or !std.math.isFinite(pos.y)) {
        Errors.report(.invalid_value, "invalid cursor position", .{});
        return error.InvalidValue;
    }
    if (!try self.getAttrib(.focused)) return;
    if (state.cursor_mode == .disabled) {
        state.cursor_pos = pos;
        return;
    }
    platform.Window.setCursorPos(state.native, pos.x, pos.y);
}

pub fn setInputMode(self: Window, mode: InputMode) !void {
    const state = try getStatePtr(self);
    switch (mode) {
        .cursor => |cursor_mode| {
            if (state.cursor_mode == cursor_mode) return;
            if (platform.os_tag == .macos and cursor_mode == .captured) {
                Errors.report(.feature_unimplemented, "Cocoa: captured cursor mode not yet implemented", .{});
                return error.FeatureUnimplemented;
            }
            const pos = platform.Window.getCursorPos(state.native);
            state.cursor_pos = .{ .x = @floatFromInt(pos.x), .y = @floatFromInt(pos.y) };
            state.cursor_mode = cursor_mode;
            platform.Window.setInputMode(state.native, 0, @intFromEnum(cursor_mode));
            return;
        },
        .sticky_keys => |sticky_mode| {
            const enabled = sticky_mode == .enabled;
            if (!enabled) state.sticky_key_states = @splat(false);
            state.sticky_keys = enabled;
        },
        .sticky_mouse_buttons => |sticky_mode| {
            const enabled = sticky_mode == .enabled;
            if (!enabled) state.sticky_mouse_button_states = @splat(false);
            state.sticky_mouse_buttons = enabled;
        },
        .lock_key_mods => |lock_mode| {
            state.lock_key_mods = lock_mode == .enabled;
        },
        .raw_mouse_motion => |raw_mode| {
            const enabled = raw_mode == .enabled;
            if (enabled and !try Input.rawMouseMotionSupported()) {
                Errors.report(.platform_error, "raw mouse motion is not supported on this system", .{});
                return error.PlatformError;
            }
            state.raw_mouse_motion = enabled;
            platform.Window.setInputMode(state.native, 1, @intFromBool(enabled));
        },
    }
}

pub fn getInputMode(self: Window, mode: InputModeName) !InputMode {
    const state = try getState(self);
    return switch (mode) {
        .cursor => .{ .cursor = state.cursor_mode },
        .sticky_keys => .{ .sticky_keys = if (state.sticky_keys) .enabled else .disabled },
        .sticky_mouse_buttons => .{ .sticky_mouse_buttons = if (state.sticky_mouse_buttons) .enabled else .disabled },
        .lock_key_mods => .{ .lock_key_mods = if (state.lock_key_mods) .enabled else .disabled },
        .raw_mouse_motion => .{ .raw_mouse_motion = if (state.raw_mouse_motion) .enabled else .disabled },
    };
}

pub fn setCursor(self: Window, cursor: ?Cursor) !void {
    const state = try getStatePtr(self);
    state.selected_cursor = cursor;
    const cursor_native = if (cursor) |c| try c.nativeHandle() else null;
    platform.Window.setCursor(state.native, cursor_native);
}

pub fn clearCursor(cursor: Cursor) void {
    for (&windows) |*slot| {
        if (slot.*) |*state| {
            if (state.selected_cursor != null and state.selected_cursor.?.id == cursor.id) {
                state.selected_cursor = null;
                platform.Window.setCursor(state.native, null);
            }
        }
    }
}

pub fn setCloseCallback(self: Window, callback: ?CloseCallback) !void {
    (try getStatePtr(self)).close_callback = callback;
}

pub fn setPosCallback(self: Window, callback: ?PosCallback) !void {
    (try getStatePtr(self)).pos_callback = callback;
}

pub fn setSizeCallback(self: Window, callback: ?SizeCallback) !void {
    (try getStatePtr(self)).size_callback = callback;
}

pub fn setRefreshCallback(self: Window, callback: ?RefreshCallback) !void {
    (try getStatePtr(self)).refresh_callback = callback;
}

pub fn setFocusCallback(self: Window, callback: ?FocusCallback) !void {
    (try getStatePtr(self)).focus_callback = callback;
}

pub fn setIconifyCallback(self: Window, callback: ?IconifyCallback) !void {
    (try getStatePtr(self)).iconify_callback = callback;
}

pub fn setMaximizeCallback(self: Window, callback: ?MaximizeCallback) !void {
    (try getStatePtr(self)).maximize_callback = callback;
}

pub fn setFramebufferSizeCallback(self: Window, callback: ?FramebufferSizeCallback) !void {
    (try getStatePtr(self)).framebuffer_size_callback = callback;
}

pub fn setContentScaleCallback(self: Window, callback: ?ContentScaleCallback) !void {
    (try getStatePtr(self)).content_scale_callback = callback;
}

pub fn setKeyCallback(self: Window, callback: ?KeyCallback) !void {
    (try getStatePtr(self)).key_callback = callback;
}

pub fn setCharCallback(self: Window, callback: ?CharCallback) !void {
    (try getStatePtr(self)).char_callback = callback;
}

pub fn setCharModsCallback(self: Window, callback: ?CharModsCallback) !void {
    (try getStatePtr(self)).char_mods_callback = callback;
}

pub fn setMouseButtonCallback(self: Window, callback: ?MouseButtonCallback) !void {
    (try getStatePtr(self)).mouse_button_callback = callback;
}

pub fn setCursorPosCallback(self: Window, callback: ?CursorPosCallback) !void {
    (try getStatePtr(self)).cursor_pos_callback = callback;
}

pub fn setCursorEnterCallback(self: Window, callback: ?CursorEnterCallback) !void {
    (try getStatePtr(self)).cursor_enter_callback = callback;
}

pub fn setScrollCallback(self: Window, callback: ?ScrollCallback) !void {
    (try getStatePtr(self)).scroll_callback = callback;
}

pub fn setDropCallback(self: Window, callback: ?DropCallback) !void {
    (try getStatePtr(self)).drop_callback = callback;
}

pub fn nativeHandle(self: Window) !*anyopaque {
    return (try getState(self)).native;
}

pub fn setClipboardString(value: [:0]const u8) !void {
    try requireInit();
    platform.Window.setClipboardString(value.ptr);
}

pub fn getClipboardString() ![:0]const u8 {
    try requireInit();
    return std.mem.span(platform.Window.getClipboardString() orelse {
        Errors.report(.format_unavailable, "failed to retrieve string from the platform clipboard", .{});
        return error.FormatUnavailable;
    });
}

fn requireInit() !void {
    if (!initialized) {
        Errors.report(.not_initialized, "window system is not initialized", .{});
        return error.NotInitialized;
    }
}

fn insert(state: State) !usize {
    for (&windows, 0..) |*slot, i| {
        if (slot.* == null) {
            slot.* = state;
            return i;
        }
    }
    return error.OutOfMemory;
}

fn getState(self: Window) !State {
    if (self.id >= windows.len) return error.InvalidValue;
    return windows[self.id] orelse error.InvalidValue;
}

fn getStatePtr(self: Window) !*State {
    if (self.id >= windows.len) return error.InvalidValue;
    if (windows[self.id]) |*state| return state;
    return error.InvalidValue;
}

fn remove(self: Window) !State {
    const state = try getState(self);
    windows[self.id] = null;
    return state;
}

fn clearCallbacks(state: *State) void {
    state.close_callback = null;
    state.pos_callback = null;
    state.size_callback = null;
    state.refresh_callback = null;
    state.focus_callback = null;
    state.iconify_callback = null;
    state.maximize_callback = null;
    state.framebuffer_size_callback = null;
    state.content_scale_callback = null;
    state.key_callback = null;
    state.char_callback = null;
    state.char_mods_callback = null;
    state.mouse_button_callback = null;
    state.cursor_pos_callback = null;
    state.cursor_enter_callback = null;
    state.scroll_callback = null;
    state.drop_callback = null;
}

fn toPlatformOptionalSize(size: ?Size) platform.Window.Size {
    if (size) |value| return .{ .width = value.width, .height = value.height };
    return .{ .width = 0, .height = 0 };
}

fn copyTitle(state: *State, title: [:0]const u8) void {
    @memset(&state.title, 0);
    const len = @min(title.len, state.title.len - 1);
    @memcpy(state.title[0..len], title[0..len]);
}

fn filterMods(state: *const State, mods: Input.Modifiers) Input.Modifiers {
    var result = mods;
    if (!state.lock_key_mods) {
        result.caps_lock = false;
        result.num_lock = false;
    }
    return result;
}

fn releasePressedInputs(window: Window, state: *State) void {
    const mods = Input.Modifiers{};
    for (&state.key_states, 0..) |*key_state, i| {
        if (key_state.* == .press or key_state.* == .repeat) {
            key_state.* = .release;
            if (state.key_callback) |callback| {
                callback(window, std.enums.fromInt(Input.Key, i) orelse .unknown, 0, .release, mods);
            }
        }
    }

    for (&state.mouse_button_states, 0..) |*button_state, i| {
        if (button_state.* == .press) {
            button_state.* = .release;
            if (state.mouse_button_callback) |callback| {
                callback(window, Input.mouseButtonFromIndex(i), .release, mods);
            }
        }
    }
}

fn platformWindowClose(id: usize) void {
    const window = Window{ .id = id };
    if (getStatePtr(window) catch null) |state| {
        if (state.close_callback) |callback| callback(window);
    }
}

fn platformWindowPos(id: usize, x: i32, y: i32) void {
    const window = Window{ .id = id };
    if (getStatePtr(window) catch null) |state| {
        if (state.pos_callback) |callback| callback(window, x, y);
    }
}

fn platformWindowSize(id: usize, width: u32, height: u32) void {
    const window = Window{ .id = id };
    if (getStatePtr(window) catch null) |state| {
        if (state.size_callback) |callback| callback(window, width, height);
    }
}

fn platformWindowFocus(id: usize, focused: bool) void {
    const window = Window{ .id = id };
    if (getStatePtr(window) catch null) |state| {
        if (state.focus_callback) |callback| callback(window, focused);
        if (!focused) releasePressedInputs(window, state);
    }
}

fn platformWindowIconify(id: usize, iconified: bool) void {
    const window = Window{ .id = id };
    if (getStatePtr(window) catch null) |state| {
        if (state.iconify_callback) |callback| callback(window, iconified);
    }
}

fn platformWindowMaximize(id: usize, maximized: bool) void {
    const window = Window{ .id = id };
    if (getStatePtr(window) catch null) |state| {
        if (state.maximize_callback) |callback| callback(window, maximized);
    }
}

fn platformWindowFramebufferSize(id: usize, width: u32, height: u32) void {
    const window = Window{ .id = id };
    if (getStatePtr(window) catch null) |state| {
        if (state.framebuffer_size_callback) |callback| callback(window, width, height);
    }
}

fn platformWindowContentScale(id: usize, xscale: f32, yscale: f32) void {
    const window = Window{ .id = id };
    if (getStatePtr(window) catch null) |state| {
        if (state.content_scale_callback) |callback| callback(window, xscale, yscale);
    }
}

fn platformWindowKey(id: usize, key_code: i32, scancode: i32, action_value: i32, mods_value: u8) void {
    const window = Window{ .id = id };
    const key: Input.Key = std.enums.fromInt(Input.Key, key_code) orelse .unknown;
    var action: Input.Action = switch (action_value) {
        0 => .release,
        1 => .press,
        else => .repeat,
    };

    if (getStatePtr(window) catch null) |state| {
        const key_index = @intFromEnum(key);
        if (action == .release and state.key_states[key_index] == .release and !state.sticky_key_states[key_index]) return;
        if (action == .press and state.key_states[key_index] == .press) action = .repeat;

        if (action == .release and state.sticky_keys) {
            state.sticky_key_states[key_index] = true;
            state.key_states[key_index] = .release;
        } else {
            state.key_states[key_index] = if (action == .repeat) .press else action;
            if (action == .press) state.sticky_key_states[key_index] = false;
        }

        const mods = filterMods(state, @bitCast(mods_value));
        if (state.key_callback) |callback| callback(window, key, scancode, action, mods);
    }
}

fn platformWindowChar(id: usize, codepoint: u32) void {
    const window = Window{ .id = id };
    if (codepoint < 32 or (codepoint > 126 and codepoint < 160)) return;
    if (getStatePtr(window) catch null) |state| {
        if (state.char_callback) |callback| callback(window, @intCast(codepoint));
    }
}

fn platformWindowCharMods(id: usize, codepoint: u32, mods_value: u8) void {
    const window = Window{ .id = id };
    if (codepoint < 32 or (codepoint > 126 and codepoint < 160)) return;
    if (getStatePtr(window) catch null) |state| {
        if (state.char_mods_callback) |callback| callback(window, @intCast(codepoint), filterMods(state, @bitCast(mods_value)));
    }
}

fn platformWindowMouseButton(id: usize, button_value: i32, action_value: i32, mods_value: u8) void {
    const window = Window{ .id = id };
    const button = mouseButtonFromNative(button_value);
    const action: Input.Action = if (action_value == 0) .release else .press;

    if (getStatePtr(window) catch null) |state| {
        const index = Input.mouseButtonIndex(button);
        if (action == .release and state.sticky_mouse_buttons) {
            state.sticky_mouse_button_states[index] = true;
            state.mouse_button_states[index] = .release;
        } else {
            state.mouse_button_states[index] = action;
            if (action == .press) state.sticky_mouse_button_states[index] = false;
        }
        const mods = filterMods(state, @bitCast(mods_value));
        if (state.mouse_button_callback) |callback| callback(window, button, action, mods);
    }
}

fn platformWindowCursorPos(id: usize, x: f64, y: f64) void {
    const window = Window{ .id = id };
    if (getStatePtr(window) catch null) |state| {
        if (state.cursor_pos.x == x and state.cursor_pos.y == y) return;
        state.cursor_pos = .{ .x = x, .y = y };
        if (state.cursor_pos_callback) |callback| callback(window, x, y);
    }
}

fn platformWindowCursorEnter(id: usize, entered: bool) void {
    const window = Window{ .id = id };
    if (getStatePtr(window) catch null) |state| {
        if (state.cursor_enter_callback) |callback| callback(window, entered);
    }
}

fn platformWindowScroll(id: usize, xoffset: f64, yoffset: f64) void {
    const window = Window{ .id = id };
    if (xoffset == 0.0 and yoffset == 0.0) return;
    if (getStatePtr(window) catch null) |state| {
        if (state.scroll_callback) |callback| callback(window, xoffset, yoffset);
    }
}

fn platformWindowRefresh(id: usize) void {
    const window = Window{ .id = id };
    if (getStatePtr(window) catch null) |state| {
        if (state.refresh_callback) |callback| callback(window);
    }
}

fn platformWindowDrop(id: usize, count: usize, paths: [*][*:0]const u8) void {
    const window = Window{ .id = id };
    if (getStatePtr(window) catch null) |state| {
        if (state.drop_callback) |callback| {
            const buffer = std.heap.c_allocator.alloc([:0]const u8, count) catch return;
            defer std.heap.c_allocator.free(buffer);
            for (buffer, 0..) |*out, i| {
                out.* = std.mem.span(paths[i]);
            }
            callback(window, buffer);
        }
    }
}

fn mouseButtonFromNative(button: i32) Input.MouseButton {
    return switch (button) {
        0 => .left,
        1 => .right,
        2 => .middle,
        3 => .four,
        4 => .five,
        5 => .six,
        6 => .seven,
        else => .eight,
    };
}

var test_last_key_action: Input.Action = .release;

fn testKeyCallback(_: Window, _: Input.Key, _: i32, action: Input.Action, _: Input.Modifiers) void {
    test_last_key_action = action;
}

test "repeated key events keep getKey state pressed" {
    const window = Window{ .id = 0 };
    windows[window.id] = State{ .native = @as(*anyopaque, @ptrFromInt(1)), .key_callback = testKeyCallback };
    defer windows[window.id] = null;

    platformWindowKey(window.id, @intFromEnum(Input.Key.w), 17, 1, 0);
    try std.testing.expectEqual(Input.Action.press, test_last_key_action);
    try std.testing.expectEqual(Input.Action.press, try window.getKey(.w));

    platformWindowKey(window.id, @intFromEnum(Input.Key.w), 17, 1, 0);
    try std.testing.expectEqual(Input.Action.repeat, test_last_key_action);
    try std.testing.expectEqual(Input.Action.press, try window.getKey(.w));

    platformWindowKey(window.id, @intFromEnum(Input.Key.w), 17, 0, 0);
    try std.testing.expectEqual(Input.Action.release, try window.getKey(.w));
}
