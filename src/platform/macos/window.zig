const std = @import("std");

const input = @import("input.zig");
const monitor_module = @import("monitor.zig");
const objc = @import("objc.zig");
const types = @import("types.zig");

pub const Config = extern struct {
    width: u32,
    height: u32,
    title: [*:0]const u8,
    resizable: bool,
    visible: bool,
    decorated: bool,
    focused: bool,
    auto_iconify: bool,
    floating: bool,
    maximized: bool,
    center_cursor: bool,
    scale_to_monitor: bool,
    scale_framebuffer: bool,
    transparent_framebuffer: bool,
    mouse_passthrough: bool,
    monitor: ?*anyopaque,
};

pub const ContentScale = extern struct {
    x_scale: f32,
    y_scale: f32,
};

pub const FrameSize = extern struct {
    left: u32,
    top: u32,
    right: u32,
    bottom: u32,
};

pub const Pos = extern struct {
    x: i32,
    y: i32,
};

pub const Size = extern struct {
    width: u32,
    height: u32,
};

pub const IconImage = extern struct {
    width: u32,
    height: u32,
    pixels: [*]const u8,
};

const NSWindowStyleMaskBorderless: usize = 0;
const NSWindowStyleMaskTitled: usize = 1 << 0;
const NSWindowStyleMaskClosable: usize = 1 << 1;
const NSWindowStyleMaskMiniaturizable: usize = 1 << 2;
const NSWindowStyleMaskResizable: usize = 1 << 3;
const NSBackingStoreBuffered: usize = 2;
const NSNormalWindowLevel: isize = 0;
const NSFloatingWindowLevel: isize = 3;
const NSMainMenuWindowLevel: isize = 24;
const NSWindowCollectionBehaviorManaged: usize = 1 << 2;
const NSWindowCollectionBehaviorFullScreenPrimary: usize = 1 << 7;
const NSWindowCollectionBehaviorFullScreenNone: usize = 1 << 9;
const NSWindowTabbingModeDisallowed: isize = 2;
const NSEventMaskKeyUp: usize = 1 << 11;
const NSApplicationActivationPolicyRegular: isize = 0;
const NSWindowOcclusionStateVisible: usize = 1 << 1;
const NSEventModifierFlagCapsLock: usize = 1 << 16;
const NSEventModifierFlagShift: usize = 1 << 17;
const NSEventModifierFlagControl: usize = 1 << 18;
const NSEventModifierFlagOption: usize = 1 << 19;
const NSEventModifierFlagCommand: usize = 1 << 20;
const NSEventModifierFlagDeviceIndependentFlagsMask: usize = 0xffff0000;
const NSTrackingMouseEnteredAndExited: usize = 0x01;
const NSTrackingCursorUpdate: usize = 0x04;
const NSTrackingActiveInKeyWindow: usize = 0x20;
const NSTrackingAssumeInside: usize = 0x100;
const NSTrackingInVisibleRect: usize = 0x200;
const NSTrackingEnabledDuringMouseDrag: usize = 0x400;
const NSDragOperationGeneric: c_ulong = 4;
const NSUTF32StringEncoding: c_ulong = 0x8c000100;
const kCGEventSourceStateHIDSystemState: c_int = 1;
const empty_range = NSRange{ .location = std.math.maxInt(c_ulong), .length = 0 };

var app_initialized = false;
var classes_registered = false;
var window_class: ?objc.Class = null;
var app_delegate_class: ?objc.Class = null;
var helper_class: ?objc.Class = null;
var delegate_class: ?objc.Class = null;
var view_class: ?objc.Class = null;
var app_delegate: objc.c.id = null;
var helper: objc.c.id = null;
var nib_objects: objc.c.id = null;
var window_list: [128]?*types.Window = @splat(null);
var cursor_hidden = false;
var disabled_cursor_window: ?*types.Window = null;
var restore_cursor_pos_x: f64 = 0.0;
var restore_cursor_pos_y: f64 = 0.0;
var clipboard_string: ?[:0]u8 = null;
var key_up_monitor: objc.c.id = null;
var event_source: ?CGEventSourceRef = null;

const KeyUpMonitorBlock = objc.Block(struct {}, .{objc.c.id}, objc.c.id);

pub const EventCallbacks = struct {
    close: *const fn (usize) void,
    pos: *const fn (usize, i32, i32) void,
    size: *const fn (usize, u32, u32) void,
    focus: *const fn (usize, bool) void,
    iconify: *const fn (usize, bool) void,
    maximize: *const fn (usize, bool) void,
    framebuffer_size: *const fn (usize, u32, u32) void,
    content_scale: *const fn (usize, f32, f32) void,
    key: *const fn (usize, i32, i32, i32, u8) void,
    key_state: *const fn (usize, i32) i32,
    char: *const fn (usize, u32) void,
    char_mods: *const fn (usize, u32, u8) void,
    mouse_button: *const fn (usize, i32, i32, u8) void,
    cursor_pos: *const fn (usize, f64, f64) void,
    cursor_enter: *const fn (usize, bool) void,
    scroll: *const fn (usize, f64, f64) void,
    refresh: *const fn (usize) void,
    drop: *const fn (usize, usize, [*][*:0]const u8) void,
    monitor_changed: *const fn () void,
};

var event_callbacks: ?EventCallbacks = null;

pub fn setEventCallbacks(new_callbacks: EventCallbacks) void {
    event_callbacks = new_callbacks;
}

pub fn init() bool {
    if (app_initialized) return true;
    registerClasses();
    if (helper == null) {
        const object = helper_class.?.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
        if (object.value == null) return false;
        helper = object.value;
        objc.getClass("NSThread").?.msgSend(void, "detachNewThreadSelector:toTarget:withObject:", .{
            objc.sel("doNothing:").value,
            helper,
            @as(objc.c.id, null),
        });
    }
    const app = sharedApplication();
    if (app_delegate == null) {
        const delegate = app_delegate_class.?.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
        if (delegate.value == null) return false;
        app_delegate = delegate.value;
        app.msgSend(void, "setDelegate:", .{app_delegate});
    }
    if (key_up_monitor == null) {
        var block = KeyUpMonitorBlock.init(.{}, keyUpMonitorCallback);
        key_up_monitor = objc.getClass("NSEvent").?.msgSend(objc.Object, "addLocalMonitorForEventsMatchingMask:handler:", .{
            @as(usize, NSEventMaskKeyUp),
            &block,
        }).value;
    }
    changeToResourcesDirectory();
    const defaults = objc.getClass("NSDictionary").?.msgSend(objc.Object, "dictionaryWithObject:forKey:", .{
        objc.getClass("NSNumber").?.msgSend(objc.Object, "numberWithBool:", .{false}).value,
        nsString("ApplePressAndHoldEnabled").value,
    });
    objc.getClass("NSUserDefaults").?.msgSend(objc.Object, "standardUserDefaults", .{}).msgSend(void, "registerDefaults:", .{defaults.value});
    objc.getClass("NSNotificationCenter").?.msgSend(objc.Object, "defaultCenter", .{}).msgSend(void, "addObserver:selector:name:object:", .{
        helper,
        objc.sel("selectedKeyboardInputSourceChanged:").value,
        nsString("NSTextInputContextKeyboardSelectionDidChangeNotification").value,
        @as(objc.c.id, null),
    });
    event_source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState) orelse return false;
    CGEventSourceSetLocalEventsSuppressionInterval(event_source.?, 0.0);
    if (!input.init()) return false;
    _ = monitor_module.count();
    if (!objc.getClass("NSRunningApplication").?.msgSend(objc.Object, "currentApplication", .{}).msgSend(bool, "isFinishedLaunching", .{})) {
        app.msgSend(void, "run", .{});
    }
    _ = app.msgSend(bool, "setActivationPolicy:", .{@as(isize, NSApplicationActivationPolicyRegular)});
    app_initialized = true;
    return true;
}

pub fn deinit() void {
    input.deinit();
    if (event_source) |source| {
        CFRelease(@ptrCast(source));
        event_source = null;
    }
    if (app_delegate) |delegate| {
        sharedApplication().msgSend(void, "setDelegate:", .{@as(objc.c.id, null)});
        objc.Object.fromId(delegate).msgSend(void, "release", .{});
        app_delegate = null;
    }
    if (helper) |object| {
        const center = objc.getClass("NSNotificationCenter").?.msgSend(objc.Object, "defaultCenter", .{});
        center.msgSend(void, "removeObserver:name:object:", .{
            object,
            nsString("NSTextInputContextKeyboardSelectionDidChangeNotification").value,
            @as(objc.c.id, null),
        });
        center.msgSend(void, "removeObserver:", .{object});
        objc.Object.fromId(object).msgSend(void, "release", .{});
        helper = null;
    }
    if (key_up_monitor) |monitor| {
        objc.getClass("NSEvent").?.msgSend(void, "removeMonitor:", .{monitor});
        key_up_monitor = null;
    }
    if (clipboard_string) |value| {
        std.heap.c_allocator.free(value);
        clipboard_string = null;
    }
    window_list = @splat(null);
    app_initialized = false;
}

pub fn create(config: *const Config) ?*anyopaque {
    registerClasses();

    var style: usize = NSWindowStyleMaskMiniaturizable;
    if (config.monitor != null or !config.decorated) {
        style |= NSWindowStyleMaskBorderless;
    } else {
        style |= NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
        if (config.resizable) style |= NSWindowStyleMaskResizable;
    }

    const rect = if (config.monitor) |monitor| blk: {
        const mode = monitor_module.getVideoMode(monitor);
        const pos = monitor_module.getPos(monitor);
        break :blk CGRect{
            .origin = .{ .x = @floatFromInt(pos.x), .y = @floatFromInt(pos.y) },
            .size = .{ .width = @floatFromInt(mode.width), .height = @floatFromInt(mode.height) },
        };
    } else CGRect{
        .origin = .{ .x = 0.0, .y = 0.0 },
        .size = .{ .width = @floatFromInt(config.width), .height = @floatFromInt(config.height) },
    };

    const ns_window = window_class.?.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "initWithContentRect:styleMask:backing:defer:", .{
        rect,
        style,
        @as(usize, NSBackingStoreBuffered),
        false,
    });
    if (ns_window.value == null) return null;
    errdefer ns_window.msgSend(void, "release", .{});

    const result = std.heap.c_allocator.create(types.Window) catch return null;
    result.* = .{
        .window = ns_window.value,
        .view = null,
        .delegate = null,
        .cursor = null,
        .marked_text = null,
        .layer = null,
        .monitor = config.monitor,
        .should_close = false,
        .maximized = false,
        .occluded = false,
        .resizable = config.resizable,
        .decorated = config.decorated,
        .floating = config.floating,
        .auto_iconify = config.auto_iconify,
        .scale_framebuffer = config.scale_framebuffer,
        .user_pointer = null,
        .callback_id = 0,
        .cursor_mode = 0,
        .cursor_warp_delta_x = 0.0,
        .cursor_warp_delta_y = 0.0,
        .virtual_cursor_x = 0.0,
        .virtual_cursor_y = 0.0,
        .video_width = config.width,
        .video_height = config.height,
        .video_red_bits = 8,
        .video_green_bits = 8,
        .video_blue_bits = 8,
        .video_refresh_rate = 0,
        .min_width = 0,
        .min_height = 0,
        .max_width = 0,
        .max_height = 0,
        .aspect_numerator = 0,
        .aspect_denominator = 0,
        .windowed_x = 0.0,
        .windowed_y = 0.0,
        .windowed_width = 0.0,
        .windowed_height = 0.0,
        .width = 0.0,
        .height = 0.0,
        .fb_width = 0.0,
        .fb_height = 0.0,
        .xscale = 0.0,
        .yscale = 0.0,
        .windowed_style = style,
        .windowed_level = NSNormalWindowLevel,
        .windowed_has_shadow = true,
    };
    errdefer std.heap.c_allocator.destroy(result);

    const view = view_class.?.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "initWithFrame:zingWindow:", .{ rect, @as(objc.c.id, @ptrCast(result)) });
    if (view.value == null) return null;
    errdefer view.msgSend(void, "release", .{});
    result.view = view.value;

    const delegate = delegate_class.?.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "initWithZingWindow:", .{@as(objc.c.id, @ptrCast(result))});
    if (delegate.value == null) return null;
    errdefer delegate.msgSend(void, "release", .{});
    result.delegate = delegate.value;

    ns_window.msgSend(void, "setContentView:", .{view.value});
    ns_window.msgSend(void, "makeFirstResponder:", .{view.value});
    ns_window.msgSend(void, "setDelegate:", .{delegate.value});
    setTitle(@ptrCast(result), config.title);
    ns_window.msgSend(void, "setAcceptsMouseMovedEvents:", .{true});
    ns_window.msgSend(void, "setRestorable:", .{false});
    if (ns_window.msgSend(bool, "respondsToSelector:", .{objc.sel("setTabbingMode:").value})) {
        ns_window.msgSend(void, "setTabbingMode:", .{@as(isize, NSWindowTabbingModeDisallowed)});
    }
    if (config.monitor == null) {
        ns_window.msgSend(void, "setCollectionBehavior:", .{if (config.resizable)
            @as(usize, NSWindowCollectionBehaviorFullScreenPrimary | NSWindowCollectionBehaviorManaged)
        else
            @as(usize, NSWindowCollectionBehaviorFullScreenNone)});
        ns_window.msgSend(void, "center", .{});
    } else {
        ns_window.msgSend(void, "setLevel:", .{@as(isize, NSMainMenuWindowLevel + 1)});
    }

    if (config.transparent_framebuffer) {
        ns_window.msgSend(void, "setOpaque:", .{false});
        ns_window.msgSend(void, "setHasShadow:", .{false});
        ns_window.msgSend(void, "setBackgroundColor:", .{objc.getClass("NSColor").?.msgSend(objc.Object, "clearColor", .{}).value});
    }
    if (config.mouse_passthrough) ns_window.msgSend(void, "setIgnoresMouseEvents:", .{true});
    if (config.monitor == null and config.floating) ns_window.msgSend(void, "setLevel:", .{@as(isize, NSFloatingWindowLevel)});
    if (config.monitor == null and config.maximized) ns_window.msgSend(void, "zoom:", .{@as(objc.c.id, null)});
    result.maximized = ns_window.msgSend(bool, "isZoomed", .{});
    if (config.monitor) |monitor| {
        ns_window.msgSend(void, "orderFront:", .{@as(objc.c.id, null)});
        sharedApplication().msgSend(void, "activateIgnoringOtherApps:", .{true});
        ns_window.msgSend(void, "makeKeyAndOrderFront:", .{@as(objc.c.id, null)});
        acquireMonitor(result, monitor);
        if (config.center_cursor) centerCursorInContentArea(result);
    } else if (config.visible) {
        ns_window.msgSend(void, "orderFront:", .{@as(objc.c.id, null)});
        if (config.focused) {
            sharedApplication().msgSend(void, "activateIgnoringOtherApps:", .{true});
            ns_window.msgSend(void, "makeKeyAndOrderFront:", .{@as(objc.c.id, null)});
        }
    }
    updateCachedWindowMetrics(result);
    trackWindow(result);

    return @ptrCast(result);
}

pub fn destroy(handle: *anyopaque) void {
    const window = native(handle);
    untrackWindow(window);
    if (disabled_cursor_window == window) disabled_cursor_window = null;
    const ns_window = objc.Object.fromId(window.window);
    ns_window.msgSend(void, "orderOut:", .{@as(objc.c.id, null)});
    if (window.monitor != null) releaseMonitor(window);
    ns_window.msgSend(void, "setDelegate:", .{@as(objc.c.id, null)});
    if (window.delegate) |delegate| {
        objc.Object.fromId(delegate).msgSend(void, "release", .{});
        window.delegate = null;
    }
    if (window.view) |view| {
        objc.Object.fromId(view).msgSend(void, "release", .{});
        window.view = null;
    }
    ns_window.msgSend(void, "close", .{});
    window.window = null;
    std.heap.c_allocator.destroy(window);
    @import("events.zig").poll();
}

pub fn setCallbackId(handle: *anyopaque, id: usize) void {
    native(handle).callback_id = id;
}

pub fn shouldClose(handle: *anyopaque) bool {
    return native(handle).should_close;
}

pub fn setShouldClose(handle: *anyopaque, value: bool) void {
    native(handle).should_close = value;
}

pub fn setTitle(handle: *anyopaque, title: [*:0]const u8) void {
    const string = objc.getClass("NSString").?.msgSend(objc.Object, "stringWithUTF8String:", .{title});
    const ns_window = windowObject(handle);
    ns_window.msgSend(void, "setTitle:", .{string.value});
    ns_window.msgSend(void, "setMiniwindowTitle:", .{string.value});
}

pub fn getPos(handle: *anyopaque) Pos {
    const ns_window = windowObject(handle);
    const content = ns_window.msgSend(CGRect, "contentRectForFrameRect:", .{ns_window.msgSend(CGRect, "frame", .{})});
    return .{
        .x = @intFromFloat(content.origin.x),
        .y = @intFromFloat(transformY(content.origin.y + content.size.height - 1.0)),
    };
}

pub fn setPos(handle: *anyopaque, pos: Pos) void {
    const content = viewObject(handle).msgSend(CGRect, "frame", .{});
    const dummy = CGRect{
        .origin = .{ .x = @floatFromInt(pos.x), .y = transformY(@as(f64, @floatFromInt(pos.y)) + content.size.height - 1.0) },
        .size = .{ .width = 0.0, .height = 0.0 },
    };
    const frame = windowObject(handle).msgSend(CGRect, "frameRectForContentRect:", .{dummy});
    windowObject(handle).msgSend(void, "setFrameOrigin:", .{frame.origin});
}

pub fn getSize(handle: *anyopaque) Size {
    const content = viewObject(handle).msgSend(CGRect, "frame", .{});
    return .{
        .width = @intFromFloat(content.size.width),
        .height = @intFromFloat(content.size.height),
    };
}

pub fn setSize(handle: *anyopaque, size: Size) void {
    const window = native(handle);
    if (window.monitor) |monitor| {
        window.video_width = size.width;
        window.video_height = size.height;
        if (monitor_module.getWindow(monitor) == handle) acquireMonitor(window, monitor);
        return;
    }

    const ns_window = windowObject(handle);
    var content = ns_window.msgSend(CGRect, "contentRectForFrameRect:", .{ns_window.msgSend(CGRect, "frame", .{})});
    content.origin.y += content.size.height - @as(f64, @floatFromInt(size.height));
    content.size = .{
        .width = @floatFromInt(size.width),
        .height = @floatFromInt(size.height),
    };
    ns_window.msgSend(void, "setFrame:display:", .{ ns_window.msgSend(CGRect, "frameRectForContentRect:", .{content}), true });
    updateCachedWindowMetrics(window);
}

pub fn setMonitor(handle: *anyopaque, monitor: ?*anyopaque, pos: Pos, size: Size, refresh_rate: u32) void {
    const window = native(handle);
    const ns_window = windowObject(handle);

    if (window.monitor == monitor) {
        if (monitor) |native_monitor| {
            updateVideoMode(window, monitor, size, refresh_rate);
            if (monitor_module.getWindow(native_monitor) == handle) acquireMonitor(window, native_monitor);
        } else {
            const content = CGRect{
                .origin = .{
                    .x = @floatFromInt(pos.x),
                    .y = transformY(@as(f64, @floatFromInt(pos.y)) + @as(f64, @floatFromInt(size.height)) - 1.0),
                },
                .size = .{ .width = @floatFromInt(size.width), .height = @floatFromInt(size.height) },
            };
            ns_window.msgSend(void, "setFrame:display:", .{ ns_window.msgSend(CGRect, "frameRectForContentRect:", .{content}), true });
            updateCachedWindowMetrics(window);
        }
        return;
    }

    if (window.monitor != null) releaseMonitor(window);
    updateVideoMode(window, monitor, size, refresh_rate);

    if (monitor) |native_monitor| {
        if (window.monitor == null) {
            const frame = ns_window.msgSend(CGRect, "frame", .{});
            window.windowed_x = frame.origin.x;
            window.windowed_y = frame.origin.y;
            window.windowed_width = frame.size.width;
            window.windowed_height = frame.size.height;
            window.windowed_style = ns_window.msgSend(usize, "styleMask", .{});
            window.windowed_level = ns_window.msgSend(isize, "level", .{});
            window.windowed_has_shadow = ns_window.msgSend(bool, "hasShadow", .{});
        }

        window.monitor = native_monitor;
        @import("events.zig").poll();

        var style = ns_window.msgSend(usize, "styleMask", .{});
        style &= ~(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable);
        style |= NSWindowStyleMaskBorderless;
        ns_window.msgSend(void, "setStyleMask:", .{style});
        ns_window.msgSend(void, "makeFirstResponder:", .{window.view});
        ns_window.msgSend(void, "setLevel:", .{@as(isize, NSMainMenuWindowLevel + 1)});
        ns_window.msgSend(void, "setHasShadow:", .{false});

        acquireMonitor(window, native_monitor);
    } else {
        window.monitor = null;
        @import("events.zig").poll();

        var style = ns_window.msgSend(usize, "styleMask", .{});
        if (window.decorated) {
            style &= ~NSWindowStyleMaskBorderless;
            style |= NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
        } else {
            style |= NSWindowStyleMaskBorderless;
            style &= ~(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable);
        }
        if (window.resizable) {
            style |= NSWindowStyleMaskResizable;
        } else {
            style &= ~NSWindowStyleMaskResizable;
        }
        ns_window.msgSend(void, "setStyleMask:", .{style});
        ns_window.msgSend(void, "makeFirstResponder:", .{window.view});

        const content = CGRect{
            .origin = .{
                .x = @floatFromInt(pos.x),
                .y = transformY(@as(f64, @floatFromInt(pos.y)) + @as(f64, @floatFromInt(size.height)) - 1.0),
            },
            .size = .{ .width = @floatFromInt(size.width), .height = @floatFromInt(size.height) },
        };
        ns_window.msgSend(void, "setFrame:display:", .{ ns_window.msgSend(CGRect, "frameRectForContentRect:", .{content}), true });
        applyWindowConstraints(window);
        ns_window.msgSend(void, "setLevel:", .{if (window.floating) @as(isize, NSFloatingWindowLevel) else @as(isize, NSNormalWindowLevel)});
        ns_window.msgSend(void, "setCollectionBehavior:", .{if (window.resizable)
            @as(usize, NSWindowCollectionBehaviorFullScreenPrimary | NSWindowCollectionBehaviorManaged)
        else
            @as(usize, NSWindowCollectionBehaviorFullScreenNone)});
        ns_window.msgSend(void, "setHasShadow:", .{true});
        const mini_title = ns_window.msgSend(objc.Object, "miniwindowTitle", .{});
        if (mini_title.value != null) ns_window.msgSend(void, "setTitle:", .{mini_title.value});
    }
    updateCachedWindowMetrics(window);
}

pub fn setIcon(_: *anyopaque, _: [*]const IconImage, _: usize) bool {
    return false;
}

pub fn setSizeLimits(handle: *anyopaque, min_size: Size, max_size: Size) void {
    const window = native(handle);
    window.min_width = min_size.width;
    window.min_height = min_size.height;
    window.max_width = max_size.width;
    window.max_height = max_size.height;
    applySizeLimits(window);
}

pub fn setAspectRatio(handle: *anyopaque, numerator: u32, denominator: u32) void {
    const window = native(handle);
    window.aspect_numerator = numerator;
    window.aspect_denominator = denominator;
    applyAspectRatio(window);
}

pub fn clearAspectRatio(handle: *anyopaque) void {
    const window = native(handle);
    window.aspect_numerator = 0;
    window.aspect_denominator = 0;
    applyAspectRatio(window);
}

pub fn getFramebufferSize(handle: *anyopaque) Size {
    const view = viewObject(handle);
    const content = view.msgSend(CGRect, "frame", .{});
    const framebuffer = view.msgSend(CGRect, "convertRectToBacking:", .{content});
    return .{
        .width = @intFromFloat(framebuffer.size.width),
        .height = @intFromFloat(framebuffer.size.height),
    };
}

pub fn getFrameSize(handle: *anyopaque) FrameSize {
    const content = viewObject(handle).msgSend(CGRect, "frame", .{});
    const frame = windowObject(handle).msgSend(CGRect, "frameRectForContentRect:", .{content});
    return .{
        .left = @intFromFloat(content.origin.x - frame.origin.x),
        .top = @intFromFloat(frame.origin.y + frame.size.height - content.origin.y - content.size.height),
        .right = @intFromFloat(frame.origin.x + frame.size.width - content.origin.x - content.size.width),
        .bottom = @intFromFloat(content.origin.y - frame.origin.y),
    };
}

pub fn getContentScale(handle: *anyopaque) ContentScale {
    const view = viewObject(handle);
    const points = view.msgSend(CGRect, "frame", .{});
    const pixels = view.msgSend(CGRect, "convertRectToBacking:", .{points});
    return .{
        .x_scale = @floatCast(pixels.size.width / points.size.width),
        .y_scale = @floatCast(pixels.size.height / points.size.height),
    };
}

pub fn getOpacity(handle: *anyopaque) f32 {
    return @floatCast(windowObject(handle).msgSend(f64, "alphaValue", .{}));
}

pub fn setOpacity(handle: *anyopaque, opacity: f32) void {
    windowObject(handle).msgSend(void, "setAlphaValue:", .{@as(f64, opacity)});
}

pub fn iconify(handle: *anyopaque) void {
    windowObject(handle).msgSend(void, "miniaturize:", .{@as(objc.c.id, null)});
}

pub fn restore(handle: *anyopaque) void {
    const ns_window = windowObject(handle);
    if (ns_window.msgSend(bool, "isMiniaturized", .{})) {
        ns_window.msgSend(void, "deminiaturize:", .{@as(objc.c.id, null)});
    } else if (ns_window.msgSend(bool, "isZoomed", .{})) {
        ns_window.msgSend(void, "zoom:", .{@as(objc.c.id, null)});
    }
}

pub fn maximize(handle: *anyopaque) void {
    const ns_window = windowObject(handle);
    if (!ns_window.msgSend(bool, "isZoomed", .{})) {
        ns_window.msgSend(void, "zoom:", .{@as(objc.c.id, null)});
    }
}

pub fn show(handle: *anyopaque) void {
    windowObject(handle).msgSend(void, "orderFront:", .{@as(objc.c.id, null)});
}

pub fn hide(handle: *anyopaque) void {
    windowObject(handle).msgSend(void, "orderOut:", .{@as(objc.c.id, null)});
}

pub fn focus(handle: *anyopaque) void {
    sharedApplication().msgSend(void, "activateIgnoringOtherApps:", .{true});
    windowObject(handle).msgSend(void, "makeKeyAndOrderFront:", .{@as(objc.c.id, null)});
}

pub fn requestAttention(_: *anyopaque) void {
    sharedApplication().msgSend(void, "requestUserAttention:", .{@as(c_int, 10)});
}

pub fn getAttribute(handle: *anyopaque, attr: c_int) bool {
    const ns_window = windowObject(handle);
    return switch (attr) {
        0 => ns_window.msgSend(bool, "isKeyWindow", .{}),
        1 => ns_window.msgSend(bool, "isMiniaturized", .{}),
        2 => native(handle).resizable and ns_window.msgSend(bool, "isZoomed", .{}),
        3 => isHovered(handle),
        4 => ns_window.msgSend(bool, "isVisible", .{}),
        5 => (ns_window.msgSend(usize, "styleMask", .{}) & NSWindowStyleMaskResizable) != 0,
        6 => (ns_window.msgSend(usize, "styleMask", .{}) & NSWindowStyleMaskTitled) != 0,
        7 => true,
        8 => ns_window.msgSend(isize, "level", .{}) == NSFloatingWindowLevel,
        9 => !ns_window.msgSend(bool, "isOpaque", .{}) and !viewObject(handle).msgSend(bool, "isOpaque", .{}),
        10 => true,
        11 => ns_window.msgSend(bool, "ignoresMouseEvents", .{}),
        else => false,
    };
}

pub fn setAttribute(handle: *anyopaque, attr: c_int, value: bool) void {
    const ns_window = windowObject(handle);
    const window = native(handle);
    var style = ns_window.msgSend(usize, "styleMask", .{});
    switch (attr) {
        5 => {
            window.resizable = value;
            ns_window.msgSend(void, "setStyleMask:", .{if (value) style | NSWindowStyleMaskResizable else style & ~NSWindowStyleMaskResizable});
            ns_window.msgSend(void, "setCollectionBehavior:", .{if (value)
                @as(usize, NSWindowCollectionBehaviorFullScreenPrimary | NSWindowCollectionBehaviorManaged)
            else
                @as(usize, NSWindowCollectionBehaviorFullScreenNone)});
        },
        6 => {
            window.decorated = value;
            if (value) {
                style |= NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
                style &= ~NSWindowStyleMaskBorderless;
            } else {
                style |= NSWindowStyleMaskBorderless;
                style &= ~(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable);
            }
            ns_window.msgSend(void, "setStyleMask:", .{style});
            ns_window.msgSend(void, "makeFirstResponder:", .{native(handle).view});
        },
        8 => {
            window.floating = value;
            ns_window.msgSend(void, "setLevel:", .{if (value) NSFloatingWindowLevel else NSNormalWindowLevel});
        },
        11 => ns_window.msgSend(void, "setIgnoresMouseEvents:", .{value}),
        else => {},
    }
}

pub fn setUserPointer(handle: *anyopaque, pointer: ?*anyopaque) void {
    native(handle).user_pointer = pointer;
}

pub fn getUserPointer(handle: *anyopaque) ?*anyopaque {
    return native(handle).user_pointer;
}

pub fn getCursorPos(handle: *anyopaque) Pos {
    const content = viewObject(handle).msgSend(CGRect, "frame", .{});
    const pos = windowObject(handle).msgSend(CGPoint, "mouseLocationOutsideOfEventStream", .{});
    return .{
        .x = @intFromFloat(pos.x),
        .y = @intFromFloat(content.size.height - pos.y),
    };
}

pub fn setCursorPos(handle: *anyopaque, x: f64, y: f64) void {
    updateCursorImage(native(handle));
    const content = viewObject(handle).msgSend(CGRect, "frame", .{});
    const pos = windowObject(handle).msgSend(CGPoint, "mouseLocationOutsideOfEventStream", .{});
    native(handle).cursor_warp_delta_x += x - pos.x;
    native(handle).cursor_warp_delta_y += y - content.size.height + pos.y;
    if (native(handle).monitor) |monitor| {
        CGDisplayMoveCursorToPoint(monitor_module.getDisplayId(monitor), .{ .x = x, .y = y });
    } else {
        const local = CGRect{
            .origin = .{ .x = x, .y = content.size.height - y - 1.0 },
            .size = .{ .width = 0.0, .height = 0.0 },
        };
        const global = windowObject(handle).msgSend(CGRect, "convertRectToScreen:", .{local});
        CGWarpMouseCursorPosition(.{ .x = global.origin.x, .y = transformY(global.origin.y) });
    }
    if (native(handle).cursor_mode != 2) CGAssociateMouseAndMouseCursorPosition(true);
}

pub fn setCursor(handle: *anyopaque, cursor_handle: ?*anyopaque) void {
    const window = native(handle);
    window.cursor = if (cursor_handle) |value| (@as(*types.Cursor, @ptrCast(@alignCast(value)))).cursor else null;
    if (cursorInContentArea(window)) updateCursorImage(window);
}

pub fn setInputMode(handle: *anyopaque, mode: c_int, value: c_int) void {
    if (mode != 0) return;
    const window = native(handle);
    window.cursor_mode = value;
    const pos = getCursorPos(handle);
    window.virtual_cursor_x = @floatFromInt(pos.x);
    window.virtual_cursor_y = @floatFromInt(pos.y);
    if (windowObject(handle).msgSend(bool, "isKeyWindow", .{})) updateCursorMode(window);
}

pub fn setClipboardString(value: [*:0]const u8) void {
    const ns_string = objc.getClass("NSString").?.msgSend(objc.Object, "stringWithUTF8String:", .{value});
    const pasteboard = objc.getClass("NSPasteboard").?.msgSend(objc.Object, "generalPasteboard", .{});
    const string_type = nsString("public.utf8-plain-text");
    const types_array = objc.getClass("NSArray").?.msgSend(objc.Object, "arrayWithObject:", .{string_type.value});
    _ = pasteboard.msgSend(isize, "declareTypes:owner:", .{ types_array.value, @as(objc.c.id, null) });
    _ = pasteboard.msgSend(bool, "setString:forType:", .{ ns_string.value, string_type.value });
}

pub fn getClipboardString() ?[*:0]const u8 {
    const pasteboard = objc.getClass("NSPasteboard").?.msgSend(objc.Object, "generalPasteboard", .{});
    const string_type = nsString("public.utf8-plain-text");
    const types_array = pasteboard.msgSend(objc.Object, "types", .{});
    if (!types_array.msgSend(bool, "containsObject:", .{string_type.value})) return null;
    const value = pasteboard.msgSend(objc.Object, "stringForType:", .{string_type.value});
    if (value.value == null) return null;
    if (clipboard_string) |old| std.heap.c_allocator.free(old);
    clipboard_string = std.heap.c_allocator.dupeZ(u8, std.mem.span(value.msgSend([*:0]const u8, "UTF8String", .{}))) catch null;
    return if (clipboard_string) |new_value| new_value.ptr else null;
}

fn callbacks() EventCallbacks {
    return event_callbacks.?;
}

fn keyUpMonitorCallback(_: *const KeyUpMonitorBlock.Context, event_id: objc.c.id) callconv(.c) objc.c.id {
    const event = objc.Object.fromId(event_id);
    if ((event.msgSend(usize, "modifierFlags", .{}) & NSEventModifierFlagCommand) != 0) {
        const key_window = sharedApplication().msgSend(objc.Object, "keyWindow", .{});
        if (key_window.value != null) key_window.msgSend(void, "sendEvent:", .{event_id});
    }
    return event_id;
}

fn cursorInContentArea(window: *types.Window) bool {
    const pos = objc.Object.fromId(window.window).msgSend(CGPoint, "mouseLocationOutsideOfEventStream", .{});
    return objc.Object.fromId(window.view).msgSend(bool, "mouse:inRect:", .{
        pos,
        objc.Object.fromId(window.view).msgSend(CGRect, "frame", .{}),
    });
}

fn hideCursor() void {
    if (!cursor_hidden) {
        objc.getClass("NSCursor").?.msgSend(void, "hide", .{});
        cursor_hidden = true;
    }
}

fn showCursor() void {
    if (cursor_hidden) {
        objc.getClass("NSCursor").?.msgSend(void, "unhide", .{});
        cursor_hidden = false;
    }
}

fn updateCursorImage(window: *types.Window) void {
    if (window.cursor_mode == 0) {
        showCursor();
        const cursor = if (window.cursor) |cursor|
            objc.Object.fromId(cursor)
        else
            objc.getClass("NSCursor").?.msgSend(objc.Object, "arrowCursor", .{});
        cursor.msgSend(void, "set", .{});
    } else {
        hideCursor();
    }
}

fn updateCursorMode(window: *types.Window) void {
    if (window.cursor_mode == 2) {
        disabled_cursor_window = window;
        const pos = getCursorPos(@ptrCast(window));
        restore_cursor_pos_x = @floatFromInt(pos.x);
        restore_cursor_pos_y = @floatFromInt(pos.y);
        centerCursorInContentArea(window);
        CGAssociateMouseAndMouseCursorPosition(false);
    } else if (disabled_cursor_window == window) {
        disabled_cursor_window = null;
        setCursorPos(@ptrCast(window), restore_cursor_pos_x, restore_cursor_pos_y);
    }

    if (cursorInContentArea(window)) updateCursorImage(window);
}

fn acquireMonitor(window: *types.Window, monitor: *anyopaque) void {
    _ = monitor_module.setVideoMode(monitor, .{
        .width = window.video_width,
        .height = window.video_height,
        .red_bits = window.video_red_bits,
        .green_bits = window.video_green_bits,
        .blue_bits = window.video_blue_bits,
        .refresh_rate = window.video_refresh_rate,
    });
    setFullscreenFrame(window, monitor);
    monitor_module.setWindow(monitor, @ptrCast(window));
}

fn releaseMonitor(window: *types.Window) void {
    const monitor = window.monitor orelse return;
    if (monitor_module.getWindow(monitor) != @as(*anyopaque, @ptrCast(window))) return;
    monitor_module.setWindow(monitor, null);
    monitor_module.restoreVideoMode(monitor);
}

fn updateVideoMode(window: *types.Window, monitor: ?*anyopaque, size: Size, refresh_rate: u32) void {
    const current = if (monitor) |native_monitor| monitor_module.getVideoMode(native_monitor) else null;
    window.video_width = size.width;
    window.video_height = size.height;
    window.video_red_bits = if (current) |mode| mode.red_bits else 8;
    window.video_green_bits = if (current) |mode| mode.green_bits else 8;
    window.video_blue_bits = if (current) |mode| mode.blue_bits else 8;
    window.video_refresh_rate = refresh_rate;
}

fn applyWindowConstraints(window: *types.Window) void {
    applyAspectRatio(window);
    applySizeLimits(window);
}

fn applyAspectRatio(window: *types.Window) void {
    const ns_window = objc.Object.fromId(window.window);
    if (window.aspect_numerator == 0 or window.aspect_denominator == 0) {
        ns_window.msgSend(void, "setResizeIncrements:", .{CGSize{ .width = 1.0, .height = 1.0 }});
    } else {
        ns_window.msgSend(void, "setContentAspectRatio:", .{CGSize{
            .width = @floatFromInt(window.aspect_numerator),
            .height = @floatFromInt(window.aspect_denominator),
        }});
    }
}

fn applySizeLimits(window: *types.Window) void {
    const ns_window = objc.Object.fromId(window.window);
    ns_window.msgSend(void, "setContentMinSize:", .{if (window.min_width == 0 or window.min_height == 0)
        CGSize{ .width = 0.0, .height = 0.0 }
    else
        CGSize{ .width = @floatFromInt(window.min_width), .height = @floatFromInt(window.min_height) }});
    ns_window.msgSend(void, "setContentMaxSize:", .{if (window.max_width == 0 or window.max_height == 0)
        CGSize{ .width = std.math.floatMax(f64), .height = std.math.floatMax(f64) }
    else
        CGSize{ .width = @floatFromInt(window.max_width), .height = @floatFromInt(window.max_height) }});
}

fn setFullscreenFrame(window: *types.Window, monitor: *anyopaque) void {
    const bounds = monitor_module.getDisplayBounds(monitor);
    objc.Object.fromId(window.window).msgSend(void, "setFrame:display:", .{ CGRect{
        .origin = .{
            .x = bounds.origin.x,
            .y = transformY(bounds.origin.y + bounds.size.height - 1.0),
        },
        .size = .{ .width = bounds.size.width, .height = bounds.size.height },
    }, true });
    updateCachedWindowMetrics(window);
}

fn updateCachedWindowMetrics(window: *types.Window) void {
    const view = objc.Object.fromId(window.view);
    const content = view.msgSend(CGRect, "frame", .{});
    const framebuffer = view.msgSend(CGRect, "convertRectToBacking:", .{content});
    window.width = content.size.width;
    window.height = content.size.height;
    window.fb_width = framebuffer.size.width;
    window.fb_height = framebuffer.size.height;
    if (content.size.width != 0.0 and content.size.height != 0.0) {
        window.xscale = framebuffer.size.width / content.size.width;
        window.yscale = framebuffer.size.height / content.size.height;
    }
}

fn centerCursorInContentArea(window: *types.Window) void {
    const content = objc.Object.fromId(window.view).msgSend(CGRect, "frame", .{});
    setCursorPos(@ptrCast(window), content.size.width / 2.0, content.size.height / 2.0);
}

fn registerClasses() void {
    if (classes_registered) return;

    helper_class = objc.allocateClassPair(objc.getClass("NSObject"), "ZingZigHelper").?;
    _ = helper_class.?.addMethod("selectedKeyboardInputSourceChanged:", helperSelectedKeyboardInputSourceChanged);
    _ = helper_class.?.addMethod("doNothing:", helperDoNothing);
    objc.registerClassPair(helper_class.?);

    app_delegate_class = objc.allocateClassPair(objc.getClass("NSObject"), "ZingZigApplicationDelegate").?;
    _ = app_delegate_class.?.addMethod("applicationShouldTerminate:", applicationShouldTerminate);
    _ = app_delegate_class.?.addMethod("applicationDidChangeScreenParameters:", applicationDidChangeScreenParameters);
    _ = app_delegate_class.?.addMethod("applicationWillFinishLaunching:", applicationWillFinishLaunching);
    _ = app_delegate_class.?.addMethod("applicationDidFinishLaunching:", applicationDidFinishLaunching);
    _ = app_delegate_class.?.addMethod("applicationDidHide:", applicationDidHide);
    objc.registerClassPair(app_delegate_class.?);

    window_class = objc.allocateClassPair(objc.getClass("NSWindow"), "ZingZigWindowObject").?;
    _ = window_class.?.addMethod("canBecomeKeyWindow", windowCanBecomeKeyWindow);
    _ = window_class.?.addMethod("canBecomeMainWindow", windowCanBecomeMainWindow);
    objc.registerClassPair(window_class.?);

    delegate_class = objc.allocateClassPair(objc.getClass("NSObject"), "ZingZigWindowDelegate").?;
    _ = delegate_class.?.addIvar("zingWindow");
    _ = delegate_class.?.addMethod("initWithZingWindow:", delegateInitWithZingWindow);
    _ = delegate_class.?.addMethod("windowShouldClose:", delegateWindowShouldClose);
    _ = delegate_class.?.addMethod("windowDidMove:", delegateWindowDidMove);
    _ = delegate_class.?.addMethod("windowDidResize:", delegateWindowDidResize);
    _ = delegate_class.?.addMethod("windowDidBecomeKey:", delegateWindowDidBecomeKey);
    _ = delegate_class.?.addMethod("windowDidResignKey:", delegateWindowDidResignKey);
    _ = delegate_class.?.addMethod("windowDidMiniaturize:", delegateWindowDidMiniaturize);
    _ = delegate_class.?.addMethod("windowDidDeminiaturize:", delegateWindowDidDeminiaturize);
    _ = delegate_class.?.addMethod("windowDidChangeOcclusionState:", delegateWindowDidChangeOcclusionState);
    objc.registerClassPair(delegate_class.?);

    view_class = objc.allocateClassPair(objc.getClass("NSView"), "ZingZigContentView").?;
    if (objc.getProtocol("NSTextInputClient")) |protocol| {
        _ = view_class.?.addProtocol(protocol);
    }
    _ = view_class.?.addIvar("zingWindow");
    _ = view_class.?.addIvar("trackingArea");
    _ = view_class.?.addMethod("initWithFrame:zingWindow:", viewInitWithFrame);
    _ = view_class.?.addMethod("dealloc", viewDealloc);
    _ = view_class.?.addMethod("acceptsFirstResponder", viewAcceptsFirstResponder);
    _ = view_class.?.addMethod("canBecomeKeyView", viewCanBecomeKeyView);
    _ = view_class.?.addMethod("acceptsFirstMouse:", viewAcceptsFirstMouse);
    _ = view_class.?.addMethod("isOpaque", viewIsOpaque);
    _ = view_class.?.addMethod("wantsUpdateLayer", viewWantsUpdateLayer);
    _ = view_class.?.addMethod("updateLayer", viewUpdateLayer);
    _ = view_class.?.addMethod("cursorUpdate:", viewCursorUpdate);
    _ = view_class.?.addMethod("drawRect:", viewDrawRect);
    _ = view_class.?.addMethod("viewDidChangeBackingProperties", viewDidChangeBackingProperties);
    _ = view_class.?.addMethod("keyDown:", viewKeyDown);
    _ = view_class.?.addMethod("keyUp:", viewKeyUp);
    _ = view_class.?.addMethod("flagsChanged:", viewFlagsChanged);
    _ = view_class.?.addMethod("mouseDown:", viewMouseDown);
    _ = view_class.?.addMethod("mouseUp:", viewMouseUp);
    _ = view_class.?.addMethod("rightMouseDown:", viewRightMouseDown);
    _ = view_class.?.addMethod("rightMouseUp:", viewRightMouseUp);
    _ = view_class.?.addMethod("otherMouseDown:", viewOtherMouseDown);
    _ = view_class.?.addMethod("otherMouseUp:", viewOtherMouseUp);
    _ = view_class.?.addMethod("mouseMoved:", viewMouseMoved);
    _ = view_class.?.addMethod("mouseDragged:", viewMouseMoved);
    _ = view_class.?.addMethod("rightMouseDragged:", viewMouseMoved);
    _ = view_class.?.addMethod("otherMouseDragged:", viewMouseMoved);
    _ = view_class.?.addMethod("scrollWheel:", viewScrollWheel);
    _ = view_class.?.addMethod("updateTrackingAreas", viewUpdateTrackingAreas);
    _ = view_class.?.addMethod("mouseEntered:", viewMouseEntered);
    _ = view_class.?.addMethod("mouseExited:", viewMouseExited);
    _ = view_class.?.addMethod("draggingEntered:", viewDraggingEntered);
    _ = view_class.?.addMethod("performDragOperation:", viewPerformDragOperation);
    _ = view_class.?.addMethod("hasMarkedText", viewHasMarkedText);
    _ = view_class.?.addMethod("markedRange", viewMarkedRange);
    _ = view_class.?.addMethod("selectedRange", viewSelectedRange);
    _ = view_class.?.addMethod("setMarkedText:selectedRange:replacementRange:", viewSetMarkedText);
    _ = view_class.?.addMethod("unmarkText", viewUnmarkText);
    _ = view_class.?.addMethod("validAttributesForMarkedText", viewValidAttributesForMarkedText);
    _ = view_class.?.addMethod("attributedSubstringForProposedRange:actualRange:", viewAttributedSubstringForProposedRange);
    _ = view_class.?.addMethod("characterIndexForPoint:", viewCharacterIndexForPoint);
    _ = view_class.?.addMethod("firstRectForCharacterRange:actualRange:", viewFirstRectForCharacterRange);
    _ = view_class.?.addMethod("insertText:replacementRange:", viewInsertText);
    _ = view_class.?.addMethod("doCommandBySelector:", viewDoCommandBySelector);
    objc.registerClassPair(view_class.?);

    classes_registered = true;
}

fn helperSelectedKeyboardInputSourceChanged(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    _ = input.updateUnicodeData();
}

fn helperDoNothing(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {}

fn changeToResourcesDirectory() void {
    const bundle = objc.getClass("NSBundle").?.msgSend(objc.Object, "mainBundle", .{});
    if (bundle.value == null) return;

    const resource_path = bundle.msgSend(objc.Object, "resourcePath", .{});
    if (resource_path.value == null) return;

    const last_component = resource_path.msgSend(objc.Object, "lastPathComponent", .{});
    if (last_component.value == null) return;
    if (!last_component.msgSend(bool, "isEqualToString:", .{nsString("Resources").value})) return;

    const path = resource_path.msgSend([*:0]const u8, "fileSystemRepresentation", .{});
    _ = chdir(path);
}

fn createMenuBar() void {
    var app_name_buffer: [256:0]u8 = @splat(0);
    const app_name = getApplicationName(&app_name_buffer);

    const menu_class = objc.getClass("NSMenu").?;
    const item_class = objc.getClass("NSMenuItem").?;
    const app = sharedApplication();

    const bar = menu_class.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
    if (bar.value == null) return;
    app.msgSend(void, "setMainMenu:", .{bar.value});

    const app_menu_item = addMenuItem(bar, "", null, "");
    const app_menu = menu_class.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
    app_menu_item.msgSend(void, "setSubmenu:", .{app_menu.value});

    var title_buffer: [320:0]u8 = @splat(0);
    const about_title = std.fmt.bufPrintSentinel(&title_buffer, "About {s}", .{app_name}, 0) catch "About GLFW Application";
    _ = addMenuItem(app_menu, about_title, objc.sel("orderFrontStandardAboutPanel:").value, "");
    app_menu.msgSend(void, "addItem:", .{item_class.msgSend(objc.Object, "separatorItem", .{}).value});

    const services_menu = menu_class.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
    app.msgSend(void, "setServicesMenu:", .{services_menu.value});
    addMenuItem(app_menu, "Services", null, "").msgSend(void, "setSubmenu:", .{services_menu.value});
    services_menu.msgSend(void, "release", .{});

    app_menu.msgSend(void, "addItem:", .{item_class.msgSend(objc.Object, "separatorItem", .{}).value});
    const hide_title = std.fmt.bufPrintSentinel(&title_buffer, "Hide {s}", .{app_name}, 0) catch "Hide GLFW Application";
    _ = addMenuItem(app_menu, hide_title, objc.sel("hide:").value, "h");
    const hide_others = addMenuItem(app_menu, "Hide Others", objc.sel("hideOtherApplications:").value, "h");
    hide_others.msgSend(void, "setKeyEquivalentModifierMask:", .{@as(usize, NSEventModifierFlagOption | NSEventModifierFlagCommand)});
    _ = addMenuItem(app_menu, "Show All", objc.sel("unhideAllApplications:").value, "");
    app_menu.msgSend(void, "addItem:", .{item_class.msgSend(objc.Object, "separatorItem", .{}).value});
    const quit_title = std.fmt.bufPrintSentinel(&title_buffer, "Quit {s}", .{app_name}, 0) catch "Quit GLFW Application";
    _ = addMenuItem(app_menu, quit_title, objc.sel("terminate:").value, "q");

    const window_menu_item = addMenuItem(bar, "", null, "");
    bar.msgSend(void, "release", .{});
    const window_menu = menu_class.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "initWithTitle:", .{nsString("Window").value});
    app.msgSend(void, "setWindowsMenu:", .{window_menu.value});
    window_menu_item.msgSend(void, "setSubmenu:", .{window_menu.value});
    _ = addMenuItem(window_menu, "Minimize", objc.sel("performMiniaturize:").value, "m");
    _ = addMenuItem(window_menu, "Zoom", objc.sel("performZoom:").value, "");
    window_menu.msgSend(void, "addItem:", .{item_class.msgSend(objc.Object, "separatorItem", .{}).value});
    _ = addMenuItem(window_menu, "Bring All to Front", objc.sel("arrangeInFront:").value, "");
    window_menu.msgSend(void, "addItem:", .{item_class.msgSend(objc.Object, "separatorItem", .{}).value});
    const fullscreen = addMenuItem(window_menu, "Enter Full Screen", objc.sel("toggleFullScreen:").value, "f");
    fullscreen.msgSend(void, "setKeyEquivalentModifierMask:", .{@as(usize, NSEventModifierFlagControl | NSEventModifierFlagCommand)});

    app.msgSend(void, "performSelector:withObject:", .{ objc.sel("setAppleMenu:").value, app_menu.value });
}

fn addMenuItem(menu: objc.Object, title: [:0]const u8, action: objc.c.SEL, key: [:0]const u8) objc.Object {
    return menu.msgSend(objc.Object, "addItemWithTitle:action:keyEquivalent:", .{
        nsString(title).value,
        action,
        nsString(key).value,
    });
}

fn getApplicationName(buffer: *[256:0]u8) [:0]const u8 {
    const bundle = objc.getClass("NSBundle").?.msgSend(objc.Object, "mainBundle", .{});
    const info = bundle.msgSend(objc.Object, "infoDictionary", .{});
    const keys = [_][:0]const u8{
        "CFBundleDisplayName",
        "CFBundleName",
        "CFBundleExecutable",
    };

    for (keys) |key| {
        const name = info.msgSend(objc.Object, "objectForKey:", .{nsString(key).value});
        if (name.value != null and
            name.msgSend(bool, "isKindOfClass:", .{objc.getClass("NSString").?.value}) and
            name.msgSend(usize, "length", .{}) > 0)
        {
            return copyApplicationName(buffer, std.mem.span(name.msgSend([*:0]const u8, "UTF8String", .{})));
        }
    }

    if (_NSGetProgname()) |progname_ptr| {
        if (progname_ptr.*) |progname| return copyApplicationName(buffer, std.mem.span(progname));
    }

    return "GLFW Application";
}

fn copyApplicationName(buffer: *[256:0]u8, value: []const u8) [:0]const u8 {
    const len = @min(value.len, buffer.len - 1);
    @memcpy(buffer[0..len], value[0..len]);
    buffer[len] = 0;
    return buffer[0..len :0];
}

fn trackWindow(window: *types.Window) void {
    for (&window_list) |*slot| {
        if (slot.* == null) {
            slot.* = window;
            return;
        }
    }
}

fn untrackWindow(window: *types.Window) void {
    for (&window_list) |*slot| {
        if (slot.* == window) {
            slot.* = null;
            return;
        }
    }
}

fn applicationShouldTerminate(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) c_long {
    for (window_list) |maybe_window| {
        if (maybe_window) |window| {
            window.should_close = true;
            callbacks().close(window.callback_id);
        }
    }
    return 0;
}

fn applicationDidChangeScreenParameters(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    callbacks().monitor_changed();
}

fn applicationWillFinishLaunching(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    const bundle = objc.getClass("NSBundle").?.msgSend(objc.Object, "mainBundle", .{});
    const main_menu = bundle.msgSend(objc.Object, "pathForResource:ofType:", .{
        nsString("MainMenu").value,
        nsString("nib").value,
    });
    if (main_menu.value != null) {
        _ = bundle.msgSend(bool, "loadNibNamed:owner:topLevelObjects:", .{
            nsString("MainMenu").value,
            sharedApplication().value,
            &nib_objects,
        });
    } else {
        createMenuBar();
    }
}

fn applicationDidFinishLaunching(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    @import("events.zig").postEmpty();
    sharedApplication().msgSend(void, "stop:", .{@as(objc.c.id, null)});
}

fn applicationDidHide(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    const count = monitor_module.count();
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        if (monitor_module.get(i)) |monitor| monitor_module.restoreVideoMode(monitor);
    }
}

fn windowCanBecomeKeyWindow(_: objc.c.id, _: objc.c.SEL) callconv(.c) bool {
    return true;
}

fn windowCanBecomeMainWindow(_: objc.c.id, _: objc.c.SEL) callconv(.c) bool {
    return true;
}

fn delegateInitWithZingWindow(self: objc.c.id, _: objc.c.SEL, window: objc.c.id) callconv(.c) objc.c.id {
    const object = objc.Object.fromId(self).msgSendSuper(objc.getClass("NSObject").?, objc.Object, "init", .{});
    if (object.value != null) setWindowIvar(object, window);
    return object.value;
}

fn delegateWindowShouldClose(self: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) bool {
    const window = windowFromObject(objc.Object.fromId(self));
    window.should_close = true;
    callbacks().close(window.callback_id);
    return false;
}

fn delegateWindowDidMove(self: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    const window = windowFromObject(objc.Object.fromId(self));
    if (disabled_cursor_window == window) centerCursorInContentArea(window);
    const pos = getPos(@ptrCast(window));
    callbacks().pos(window.callback_id, pos.x, pos.y);
}

fn delegateWindowDidResize(self: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    const window = windowFromObject(objc.Object.fromId(self));
    if (disabled_cursor_window == window) centerCursorInContentArea(window);
    const handle: *anyopaque = @ptrCast(window);
    const maximized = objc.Object.fromId(window.window).msgSend(bool, "isZoomed", .{});
    if (window.maximized != maximized) {
        window.maximized = maximized;
        callbacks().maximize(window.callback_id, maximized);
    }
    const content = viewObject(handle).msgSend(CGRect, "frame", .{});
    const framebuffer = viewObject(handle).msgSend(CGRect, "convertRectToBacking:", .{content});
    if (framebuffer.size.width != window.fb_width or framebuffer.size.height != window.fb_height) {
        window.fb_width = framebuffer.size.width;
        window.fb_height = framebuffer.size.height;
        callbacks().framebuffer_size(window.callback_id, @intFromFloat(framebuffer.size.width), @intFromFloat(framebuffer.size.height));
    }
    if (content.size.width != window.width or content.size.height != window.height) {
        window.width = content.size.width;
        window.height = content.size.height;
        callbacks().size(window.callback_id, @intFromFloat(content.size.width), @intFromFloat(content.size.height));
    }
}

fn delegateWindowDidBecomeKey(self: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    const window = windowFromObject(objc.Object.fromId(self));
    if (disabled_cursor_window == window) centerCursorInContentArea(window);
    callbacks().focus(window.callback_id, true);
    updateCursorMode(window);
}

fn delegateWindowDidResignKey(self: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    const window = windowFromObject(objc.Object.fromId(self));
    if (window.monitor != null and window.auto_iconify) iconify(@ptrCast(window));
    callbacks().focus(window.callback_id, false);
}

fn delegateWindowDidMiniaturize(self: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    const window = windowFromObject(objc.Object.fromId(self));
    releaseMonitor(window);
    callbacks().iconify(window.callback_id, true);
}

fn delegateWindowDidDeminiaturize(self: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    const window = windowFromObject(objc.Object.fromId(self));
    if (window.monitor) |monitor| acquireMonitor(window, monitor);
    callbacks().iconify(window.callback_id, false);
}

fn delegateWindowDidChangeOcclusionState(self: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    const window = windowFromObject(objc.Object.fromId(self));
    const ns_window = objc.Object.fromId(window.window);
    if (ns_window.msgSend(bool, "respondsToSelector:", .{objc.sel("occlusionState").value})) {
        window.occluded = (ns_window.msgSend(usize, "occlusionState", .{}) & NSWindowOcclusionStateVisible) == 0;
    }
}

fn viewInitWithFrame(self: objc.c.id, _: objc.c.SEL, frame: CGRect, window: objc.c.id) callconv(.c) objc.c.id {
    const object = objc.Object.fromId(self).msgSendSuper(objc.getClass("NSView").?, objc.Object, "initWithFrame:", .{frame});
    if (object.value == null) return null;

    setWindowIvar(object, window);
    setTrackingAreaIvar(object, null);
    windowFromObject(object).marked_text = objc.getClass("NSMutableAttributedString").?.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{}).value;
    viewUpdateTrackingAreas(object.value, undefined);
    object.msgSend(void, "registerForDraggedTypes:", .{objc.getClass("NSArray").?.msgSend(objc.Object, "arrayWithObject:", .{nsString("public.url").value}).value});
    return object.value;
}

fn viewDealloc(self: objc.c.id, _: objc.c.SEL) callconv(.c) void {
    const object = objc.Object.fromId(self);
    const window = windowFromObject(object);
    if (getTrackingAreaIvar(object)) |tracking_area| objc.Object.fromId(tracking_area).msgSend(void, "release", .{});
    if (window.marked_text) |marked_text| {
        objc.Object.fromId(marked_text).msgSend(void, "release", .{});
        window.marked_text = null;
    }
    object.msgSendSuper(objc.getClass("NSView").?, void, "dealloc", .{});
}

fn viewAcceptsFirstResponder(_: objc.c.id, _: objc.c.SEL) callconv(.c) bool {
    return true;
}

fn viewCanBecomeKeyView(_: objc.c.id, _: objc.c.SEL) callconv(.c) bool {
    return true;
}

fn viewAcceptsFirstMouse(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) bool {
    return true;
}

fn viewIsOpaque(self: objc.c.id, _: objc.c.SEL) callconv(.c) bool {
    const window = windowFromObject(objc.Object.fromId(self));
    return objc.Object.fromId(window.window).msgSend(bool, "isOpaque", .{});
}

fn viewWantsUpdateLayer(_: objc.c.id, _: objc.c.SEL) callconv(.c) bool {
    return true;
}

fn viewUpdateLayer(self: objc.c.id, _: objc.c.SEL) callconv(.c) void {
    callbacks().refresh(windowFromObject(objc.Object.fromId(self)).callback_id);
}

fn viewCursorUpdate(self: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    updateCursorImage(windowFromObject(objc.Object.fromId(self)));
}

fn viewDrawRect(self: objc.c.id, _: objc.c.SEL, _: CGRect) callconv(.c) void {
    callbacks().refresh(windowFromObject(objc.Object.fromId(self)).callback_id);
}

fn viewDidChangeBackingProperties(self: objc.c.id, _: objc.c.SEL) callconv(.c) void {
    const object = objc.Object.fromId(self);
    const window = windowFromObject(object);
    const handle: *anyopaque = @ptrCast(window);
    const content = viewObject(handle).msgSend(CGRect, "frame", .{});
    const framebuffer = viewObject(handle).msgSend(CGRect, "convertRectToBacking:", .{content});
    const xscale = framebuffer.size.width / content.size.width;
    const yscale = framebuffer.size.height / content.size.height;
    if (xscale != window.xscale or yscale != window.yscale) {
        if (window.scale_framebuffer and window.layer != null) {
            objc.Object.fromId(window.layer).msgSend(void, "setContentsScale:", .{windowObject(handle).msgSend(f64, "backingScaleFactor", .{})});
        }
        window.xscale = xscale;
        window.yscale = yscale;
        callbacks().content_scale(window.callback_id, @floatCast(xscale), @floatCast(yscale));
    }
    if (framebuffer.size.width != window.fb_width or framebuffer.size.height != window.fb_height) {
        window.fb_width = framebuffer.size.width;
        window.fb_height = framebuffer.size.height;
        callbacks().framebuffer_size(window.callback_id, @intFromFloat(framebuffer.size.width), @intFromFloat(framebuffer.size.height));
    }
}

fn viewKeyDown(self: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
    const window = windowFromObject(objc.Object.fromId(self));
    const event = objc.Object.fromId(event_id);
    const key_code: u16 = @intCast(event.msgSend(c_ushort, "keyCode", .{}));
    const mods = translateMods(event.msgSend(usize, "modifierFlags", .{}));
    callbacks().key(window.callback_id, input.translateKey(key_code), key_code, 1, mods);
    const events = objc.getClass("NSArray").?.msgSend(objc.Object, "arrayWithObject:", .{event_id});
    objc.Object.fromId(self).msgSend(void, "interpretKeyEvents:", .{events.value});
}

fn viewKeyUp(self: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
    const window = windowFromObject(objc.Object.fromId(self));
    const event = objc.Object.fromId(event_id);
    const key_code: u16 = @intCast(event.msgSend(c_ushort, "keyCode", .{}));
    callbacks().key(window.callback_id, input.translateKey(key_code), key_code, 0, translateMods(event.msgSend(usize, "modifierFlags", .{})));
}

fn viewFlagsChanged(self: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
    const window = windowFromObject(objc.Object.fromId(self));
    const event = objc.Object.fromId(event_id);
    const flags = event.msgSend(usize, "modifierFlags", .{}) & NSEventModifierFlagDeviceIndependentFlagsMask;
    const key_code: u16 = @intCast(event.msgSend(c_ushort, "keyCode", .{}));
    const key = input.translateKey(key_code);
    const key_flag = translateKeyToModifierFlag(key);
    const previous_state = callbacks().key_state(window.callback_id, key);
    const action: i32 = if (key_flag != 0 and (flags & key_flag) != 0)
        if (previous_state == 1) 0 else 1
    else
        0;
    callbacks().key(window.callback_id, key, key_code, action, translateMods(flags));
}

fn viewMouseDown(self: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
    mouseButtonCallback(self, event_id, 0, 1);
}

fn viewMouseUp(self: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
    mouseButtonCallback(self, event_id, 0, 0);
}

fn viewRightMouseDown(self: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
    mouseButtonCallback(self, event_id, 1, 1);
}

fn viewRightMouseUp(self: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
    mouseButtonCallback(self, event_id, 1, 0);
}

fn viewOtherMouseDown(self: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
    const button: i32 = @intCast(objc.Object.fromId(event_id).msgSend(isize, "buttonNumber", .{}));
    mouseButtonCallback(self, event_id, button, 1);
}

fn viewOtherMouseUp(self: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
    const button: i32 = @intCast(objc.Object.fromId(event_id).msgSend(isize, "buttonNumber", .{}));
    mouseButtonCallback(self, event_id, button, 0);
}

fn viewMouseMoved(self: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
    const window = windowFromObject(objc.Object.fromId(self));
    const event = objc.Object.fromId(event_id);
    if (window.cursor_mode == 2) {
        const dx = event.msgSend(f64, "deltaX", .{}) - window.cursor_warp_delta_x;
        const dy = event.msgSend(f64, "deltaY", .{}) - window.cursor_warp_delta_y;
        window.virtual_cursor_x += dx;
        window.virtual_cursor_y += dy;
        callbacks().cursor_pos(window.callback_id, window.virtual_cursor_x, window.virtual_cursor_y);
    } else {
        const pos = cursorPosFromEvent(window, event);
        callbacks().cursor_pos(window.callback_id, @floatFromInt(pos.x), @floatFromInt(pos.y));
    }
    window.cursor_warp_delta_x = 0.0;
    window.cursor_warp_delta_y = 0.0;
}

fn viewScrollWheel(self: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
    const window = windowFromObject(objc.Object.fromId(self));
    const event = objc.Object.fromId(event_id);
    var delta_x = event.msgSend(f64, "scrollingDeltaX", .{});
    var delta_y = event.msgSend(f64, "scrollingDeltaY", .{});
    if (event.msgSend(bool, "hasPreciseScrollingDeltas", .{})) {
        delta_x *= 0.1;
        delta_y *= 0.1;
    }
    if (@abs(delta_x) > 0.0 or @abs(delta_y) > 0.0) {
        callbacks().scroll(window.callback_id, delta_x, delta_y);
    }
}

fn viewUpdateTrackingAreas(self: objc.c.id, _: objc.c.SEL) callconv(.c) void {
    const object = objc.Object.fromId(self);
    if (getTrackingAreaIvar(object)) |tracking_area| {
        object.msgSend(void, "removeTrackingArea:", .{tracking_area});
        objc.Object.fromId(tracking_area).msgSend(void, "release", .{});
    }

    const options: usize = NSTrackingMouseEnteredAndExited |
        NSTrackingActiveInKeyWindow |
        NSTrackingEnabledDuringMouseDrag |
        NSTrackingCursorUpdate |
        NSTrackingInVisibleRect |
        NSTrackingAssumeInside;
    const tracking_area = objc.getClass("NSTrackingArea").?.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "initWithRect:options:owner:userInfo:", .{
        object.msgSend(CGRect, "bounds", .{}),
        options,
        self,
        @as(objc.c.id, null),
    });
    setTrackingAreaIvar(object, tracking_area.value);
    object.msgSend(void, "addTrackingArea:", .{tracking_area.value});
    object.msgSendSuper(objc.getClass("NSView").?, void, "updateTrackingAreas", .{});
}

fn viewMouseEntered(self: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    const window = windowFromObject(objc.Object.fromId(self));
    if (window.cursor_mode == 1) hideCursor();
    callbacks().cursor_enter(window.callback_id, true);
}

fn viewMouseExited(self: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    const window = windowFromObject(objc.Object.fromId(self));
    if (window.cursor_mode == 1) showCursor();
    callbacks().cursor_enter(window.callback_id, false);
}

fn viewDraggingEntered(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) c_ulong {
    return NSDragOperationGeneric;
}

fn viewPerformDragOperation(self: objc.c.id, _: objc.c.SEL, sender_id: objc.c.id) callconv(.c) bool {
    const window = windowFromObject(objc.Object.fromId(self));
    const content = objc.Object.fromId(window.view).msgSend(CGRect, "frame", .{});
    const pos = objc.Object.fromId(sender_id).msgSend(CGPoint, "draggingLocation", .{});
    callbacks().cursor_pos(window.callback_id, pos.x, content.size.height - pos.y);

    const pasteboard = objc.Object.fromId(sender_id).msgSend(objc.Object, "draggingPasteboard", .{});
    const classes = objc.getClass("NSArray").?.msgSend(objc.Object, "arrayWithObject:", .{objc.getClass("NSURL").?.value});
    const options = objc.getClass("NSDictionary").?.msgSend(objc.Object, "dictionaryWithObject:forKey:", .{
        objc.getClass("NSNumber").?.msgSend(objc.Object, "numberWithBool:", .{true}).value,
        NSPasteboardURLReadingFileURLsOnlyKey,
    });
    const urls = pasteboard.msgSend(objc.Object, "readObjectsForClasses:options:", .{ classes.value, options.value });
    const count = urls.msgSend(usize, "count", .{});
    if (count == 0) return true;

    const owned_paths = std.heap.c_allocator.alloc(?[:0]u8, count) catch return false;
    defer std.heap.c_allocator.free(owned_paths);
    @memset(owned_paths, null);
    const path_buffer = std.heap.c_allocator.alloc([*:0]const u8, count) catch return false;
    defer std.heap.c_allocator.free(path_buffer);
    defer {
        for (owned_paths) |maybe_path| {
            if (maybe_path) |path| std.heap.c_allocator.free(path);
        }
    }

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const path = urls.msgSend(objc.Object, "objectAtIndex:", .{i}).msgSend([*:0]const u8, "fileSystemRepresentation", .{});
        owned_paths[i] = std.heap.c_allocator.dupeZ(u8, std.mem.span(path)) catch return false;
        path_buffer[i] = owned_paths[i].?.ptr;
    }

    callbacks().drop(window.callback_id, count, path_buffer.ptr);
    return true;
}

fn viewHasMarkedText(self: objc.c.id, _: objc.c.SEL) callconv(.c) bool {
    const marked_text = objc.Object.fromId(windowFromObject(objc.Object.fromId(self)).marked_text);
    return marked_text.msgSend(usize, "length", .{}) > 0;
}

fn viewMarkedRange(self: objc.c.id, _: objc.c.SEL) callconv(.c) NSRange {
    const marked_text = objc.Object.fromId(windowFromObject(objc.Object.fromId(self)).marked_text);
    const len = marked_text.msgSend(usize, "length", .{});
    return if (len > 0) .{ .location = 0, .length = len - 1 } else empty_range;
}

fn viewSelectedRange(_: objc.c.id, _: objc.c.SEL) callconv(.c) NSRange {
    return empty_range;
}

fn viewSetMarkedText(self: objc.c.id, _: objc.c.SEL, string_id: objc.c.id, _: NSRange, _: NSRange) callconv(.c) void {
    const window = windowFromObject(objc.Object.fromId(self));
    if (window.marked_text) |marked_text| objc.Object.fromId(marked_text).msgSend(void, "release", .{});

    const string = objc.Object.fromId(string_id);
    if (string.msgSend(bool, "isKindOfClass:", .{objc.getClass("NSAttributedString").?.value})) {
        window.marked_text = objc.getClass("NSMutableAttributedString").?.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "initWithAttributedString:", .{string_id}).value;
    } else {
        window.marked_text = objc.getClass("NSMutableAttributedString").?.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "initWithString:", .{string_id}).value;
    }
}

fn viewUnmarkText(self: objc.c.id, _: objc.c.SEL) callconv(.c) void {
    objc.Object.fromId(windowFromObject(objc.Object.fromId(self)).marked_text)
        .msgSend(objc.Object, "mutableString", .{})
        .msgSend(void, "setString:", .{nsString("").value});
}

fn viewValidAttributesForMarkedText(_: objc.c.id, _: objc.c.SEL) callconv(.c) objc.c.id {
    return objc.getClass("NSArray").?.msgSend(objc.Object, "array", .{}).value;
}

fn viewAttributedSubstringForProposedRange(_: objc.c.id, _: objc.c.SEL, _: NSRange, _: ?*NSRange) callconv(.c) objc.c.id {
    return null;
}

fn viewCharacterIndexForPoint(_: objc.c.id, _: objc.c.SEL, _: CGPoint) callconv(.c) c_ulong {
    return 0;
}

fn viewFirstRectForCharacterRange(self: objc.c.id, _: objc.c.SEL, _: NSRange, _: ?*NSRange) callconv(.c) CGRect {
    const frame = objc.Object.fromId(windowFromObject(objc.Object.fromId(self)).view).msgSend(CGRect, "frame", .{});
    return .{ .origin = frame.origin, .size = .{ .width = 0.0, .height = 0.0 } };
}

fn viewInsertText(self: objc.c.id, _: objc.c.SEL, string_id: objc.c.id, _: NSRange) callconv(.c) void {
    const window = windowFromObject(objc.Object.fromId(self));
    const current_event = sharedApplication().msgSend(objc.Object, "currentEvent", .{});
    const mods = if (current_event.value) |_| translateMods(current_event.msgSend(usize, "modifierFlags", .{})) else 0;
    const plain = (mods & (1 << 3)) == 0;

    var characters = objc.Object.fromId(string_id);
    if (characters.msgSend(bool, "isKindOfClass:", .{objc.getClass("NSAttributedString").?.value})) {
        characters = characters.msgSend(objc.Object, "string", .{});
    }

    var range = NSRange{ .location = 0, .length = characters.msgSend(c_ulong, "length", .{}) };
    while (range.length != 0) {
        var codepoint: u32 = 0;
        var remaining = NSRange{ .location = 0, .length = 0 };
        if (characters.msgSend(bool, "getBytes:maxLength:usedLength:encoding:options:range:remainingRange:", .{
            &codepoint,
            @as(c_ulong, @sizeOf(u32)),
            @as(?*c_ulong, null),
            NSUTF32StringEncoding,
            @as(c_ulong, 0),
            range,
            &remaining,
        })) {
            range = remaining;
            if (codepoint >= 0xf700 and codepoint <= 0xf7ff) continue;
            callbacks().char_mods(window.callback_id, codepoint, mods);
            if (plain) callbacks().char(window.callback_id, codepoint);
        } else {
            break;
        }
    }
}

fn viewDoCommandBySelector(_: objc.c.id, _: objc.c.SEL, _: objc.c.SEL) callconv(.c) void {}

fn mouseButtonCallback(self: objc.c.id, event_id: objc.c.id, button: i32, action: i32) void {
    const window = windowFromObject(objc.Object.fromId(self));
    const event = objc.Object.fromId(event_id);
    callbacks().mouse_button(window.callback_id, button, action, translateMods(event.msgSend(usize, "modifierFlags", .{})));
}

fn translateMods(flags: usize) u8 {
    var mods: u8 = 0;
    if ((flags & NSEventModifierFlagShift) != 0) mods |= 1 << 0;
    if ((flags & NSEventModifierFlagControl) != 0) mods |= 1 << 1;
    if ((flags & NSEventModifierFlagOption) != 0) mods |= 1 << 2;
    if ((flags & NSEventModifierFlagCommand) != 0) mods |= 1 << 3;
    if ((flags & NSEventModifierFlagCapsLock) != 0) mods |= 1 << 4;
    return mods;
}

fn translateKeyToModifierFlag(key: i32) usize {
    return switch (key) {
        340, 344 => NSEventModifierFlagShift,
        341, 345 => NSEventModifierFlagControl,
        342, 346 => NSEventModifierFlagOption,
        343, 347 => NSEventModifierFlagCommand,
        280 => NSEventModifierFlagCapsLock,
        else => 0,
    };
}

fn cursorPosFromEvent(window: *types.Window, event: objc.Object) Pos {
    const content = objc.Object.fromId(window.view).msgSend(CGRect, "frame", .{});
    const pos = event.msgSend(CGPoint, "locationInWindow", .{});
    return .{
        .x = @intFromFloat(pos.x),
        .y = @intFromFloat(content.size.height - pos.y),
    };
}

fn windowFromObject(object: objc.Object) *types.Window {
    return @ptrCast(@alignCast(object.getInstanceVariable("zingWindow").value));
}

fn setWindowIvar(object: objc.Object, window: objc.c.id) void {
    object.setInstanceVariable("zingWindow", objc.Object.fromId(window));
}

fn getTrackingAreaIvar(object: objc.Object) objc.c.id {
    return object.getInstanceVariable("trackingArea").value;
}

fn setTrackingAreaIvar(object: objc.Object, tracking_area: objc.c.id) void {
    object.setInstanceVariable("trackingArea", objc.Object.fromId(tracking_area));
}

fn nsString(value: [:0]const u8) objc.Object {
    return objc.getClass("NSString").?.msgSend(objc.Object, "stringWithUTF8String:", .{value.ptr});
}

fn native(handle: *anyopaque) *types.Window {
    return @ptrCast(@alignCast(handle));
}

fn windowObject(handle: *anyopaque) objc.Object {
    return objc.Object.fromId(native(handle).window);
}

fn viewObject(handle: *anyopaque) objc.Object {
    return objc.Object.fromId(native(handle).view);
}

fn sharedApplication() objc.Object {
    return objc.getClass("NSApplication").?.msgSend(objc.Object, "sharedApplication", .{});
}

fn transformY(y: f64) f64 {
    return CGDisplayBounds(CGMainDisplayID()).size.height - y - 1.0;
}

fn isHovered(handle: *anyopaque) bool {
    const point = objc.getClass("NSEvent").?.msgSend(CGPoint, "mouseLocation", .{});
    const top_window_number = objc.getClass("NSWindow").?.msgSend(isize, "windowNumberAtPoint:belowWindowWithWindowNumber:", .{ point, @as(isize, 0) });
    if (top_window_number != windowObject(handle).msgSend(isize, "windowNumber", .{})) return false;
    return NSMouseInRect(point, windowObject(handle).msgSend(CGRect, "convertRectToScreen:", .{viewObject(handle).msgSend(CGRect, "frame", .{})}), false);
}

const CGPoint = extern struct {
    x: f64,
    y: f64,
};

const CGSize = extern struct {
    width: f64,
    height: f64,
};

const CGRect = extern struct {
    origin: CGPoint,
    size: CGSize,
};

const NSRange = extern struct {
    location: c_ulong,
    length: c_ulong,
};

const CGDirectDisplayID = u32;
const CGEventSourceRef = *anyopaque;

extern "c" fn _NSGetProgname() ?*?[*:0]u8;
extern "c" fn chdir(path: [*:0]const u8) c_int;
extern "c" fn CFRelease(object: *anyopaque) void;
extern "c" fn CGEventSourceCreate(state_id: c_int) ?CGEventSourceRef;
extern "c" fn CGEventSourceSetLocalEventsSuppressionInterval(source: CGEventSourceRef, seconds: f64) void;
extern "c" fn CGMainDisplayID() CGDirectDisplayID;
extern "c" fn CGDisplayBounds(display: CGDirectDisplayID) CGRect;
extern "c" fn CGDisplayMoveCursorToPoint(display: CGDirectDisplayID, point: CGPoint) void;
extern "c" fn CGWarpMouseCursorPosition(point: CGPoint) void;
extern "c" fn CGAssociateMouseAndMouseCursorPosition(connected: bool) void;
extern "c" fn NSMouseInRect(point: CGPoint, rect: CGRect, flipped: bool) bool;
extern "c" var NSPasteboardURLReadingFileURLsOnlyKey: objc.c.id;
