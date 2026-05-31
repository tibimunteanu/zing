const std = @import("std");

const input = @import("input.zig");
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
    floating: bool,
    maximized: bool,
    transparent_framebuffer: bool,
    mouse_passthrough: bool,
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

const NSWindowStyleMaskBorderless: usize = 0;
const NSWindowStyleMaskTitled: usize = 1 << 0;
const NSWindowStyleMaskClosable: usize = 1 << 1;
const NSWindowStyleMaskMiniaturizable: usize = 1 << 2;
const NSWindowStyleMaskResizable: usize = 1 << 3;
const NSBackingStoreBuffered: usize = 2;
const NSNormalWindowLevel: isize = 0;
const NSFloatingWindowLevel: isize = 3;
const NSApplicationActivationPolicyRegular: isize = 0;
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

var app_initialized = false;
var classes_registered = false;
var window_class: ?objc.Class = null;
var delegate_class: ?objc.Class = null;
var view_class: ?objc.Class = null;

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
    char: *const fn (usize, u32) void,
    char_mods: *const fn (usize, u32, u8) void,
    mouse_button: *const fn (usize, i32, i32, u8) void,
    cursor_pos: *const fn (usize, f64, f64) void,
    cursor_enter: *const fn (usize, bool) void,
    scroll: *const fn (usize, f64, f64) void,
    refresh: *const fn (usize) void,
    drop: *const fn (usize, usize, [*][*:0]const u8) void,
};

var event_callbacks: ?EventCallbacks = null;

pub fn setEventCallbacks(new_callbacks: EventCallbacks) void {
    event_callbacks = new_callbacks;
}

pub fn init() bool {
    if (app_initialized) return true;
    registerClasses();
    const app = sharedApplication();
    _ = app.msgSend(bool, "setActivationPolicy:", .{@as(isize, NSApplicationActivationPolicyRegular)});
    app.msgSend(void, "finishLaunching", .{});
    app_initialized = true;
    return true;
}

pub fn deinit() void {
    app_initialized = false;
}

pub fn create(config: *const Config) ?*anyopaque {
    registerClasses();

    var style: usize = NSWindowStyleMaskMiniaturizable;
    if (!config.decorated) {
        style |= NSWindowStyleMaskBorderless;
    } else {
        style |= NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
        if (config.resizable) style |= NSWindowStyleMaskResizable;
    }

    const rect = CGRect{
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
        .should_close = false,
        .maximized = false,
        .user_pointer = null,
        .callback_id = 0,
        .cursor_mode = 0,
        .modifier_flags = 0,
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
    ns_window.msgSend(void, "center", .{});

    if (config.transparent_framebuffer) {
        ns_window.msgSend(void, "setOpaque:", .{false});
        ns_window.msgSend(void, "setHasShadow:", .{false});
        ns_window.msgSend(void, "setBackgroundColor:", .{objc.getClass("NSColor").?.msgSend(objc.Object, "clearColor", .{}).value});
    }
    if (config.mouse_passthrough) ns_window.msgSend(void, "setIgnoresMouseEvents:", .{true});
    if (config.floating) ns_window.msgSend(void, "setLevel:", .{@as(isize, NSFloatingWindowLevel)});
    if (config.maximized) ns_window.msgSend(void, "zoom:", .{@as(objc.c.id, null)});
    result.maximized = ns_window.msgSend(bool, "isZoomed", .{});
    if (config.visible) ns_window.msgSend(void, "orderFront:", .{@as(objc.c.id, null)});
    if (config.focused) {
        sharedApplication().msgSend(void, "activateIgnoringOtherApps:", .{true});
        ns_window.msgSend(void, "makeKeyAndOrderFront:", .{@as(objc.c.id, null)});
    }

    return @ptrCast(result);
}

pub fn destroy(handle: *anyopaque) void {
    const window = native(handle);
    const ns_window = objc.Object.fromId(window.window);
    ns_window.msgSend(void, "orderOut:", .{@as(objc.c.id, null)});
    ns_window.msgSend(void, "setDelegate:", .{@as(objc.c.id, null)});
    ns_window.msgSend(void, "setContentView:", .{@as(objc.c.id, null)});
    if (window.delegate) |delegate| objc.Object.fromId(delegate).msgSend(void, "release", .{});
    if (window.view) |view| objc.Object.fromId(view).msgSend(void, "release", .{});
    ns_window.msgSend(void, "close", .{});
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
    const ns_window = windowObject(handle);
    var content = ns_window.msgSend(CGRect, "contentRectForFrameRect:", .{ns_window.msgSend(CGRect, "frame", .{})});
    content.origin.y += content.size.height - @as(f64, @floatFromInt(size.height));
    content.size = .{
        .width = @floatFromInt(size.width),
        .height = @floatFromInt(size.height),
    };
    ns_window.msgSend(void, "setFrame:display:", .{ ns_window.msgSend(CGRect, "frameRectForContentRect:", .{content}), true });
}

pub fn setSizeLimits(handle: *anyopaque, min_size: Size, max_size: Size) void {
    const ns_window = windowObject(handle);
    ns_window.msgSend(void, "setContentMinSize:", .{if (min_size.width == 0 or min_size.height == 0)
        CGSize{ .width = 0.0, .height = 0.0 }
    else
        CGSize{ .width = @floatFromInt(min_size.width), .height = @floatFromInt(min_size.height) }});
    ns_window.msgSend(void, "setContentMaxSize:", .{if (max_size.width == 0 or max_size.height == 0)
        CGSize{ .width = std.math.floatMax(f64), .height = std.math.floatMax(f64) }
    else
        CGSize{ .width = @floatFromInt(max_size.width), .height = @floatFromInt(max_size.height) }});
}

pub fn setAspectRatio(handle: *anyopaque, numerator: u32, denominator: u32) void {
    windowObject(handle).msgSend(void, "setContentAspectRatio:", .{CGSize{
        .width = @floatFromInt(numerator),
        .height = @floatFromInt(denominator),
    }});
}

pub fn clearAspectRatio(handle: *anyopaque) void {
    windowObject(handle).msgSend(void, "setResizeIncrements:", .{CGSize{ .width = 1.0, .height = 1.0 }});
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

pub fn requestAttention() void {
    sharedApplication().msgSend(void, "requestUserAttention:", .{@as(c_int, 10)});
}

pub fn getAttribute(handle: *anyopaque, attr: c_int) bool {
    const ns_window = windowObject(handle);
    return switch (attr) {
        0 => ns_window.msgSend(bool, "isKeyWindow", .{}),
        1 => ns_window.msgSend(bool, "isMiniaturized", .{}),
        2 => ns_window.msgSend(bool, "isZoomed", .{}),
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
    var style = ns_window.msgSend(usize, "styleMask", .{});
    switch (attr) {
        5 => ns_window.msgSend(void, "setStyleMask:", .{if (value) style | NSWindowStyleMaskResizable else style & ~NSWindowStyleMaskResizable}),
        6 => {
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
        8 => ns_window.msgSend(void, "setLevel:", .{if (value) NSFloatingWindowLevel else NSNormalWindowLevel}),
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
    const content = viewObject(handle).msgSend(CGRect, "frame", .{});
    const local = CGRect{
        .origin = .{ .x = x, .y = content.size.height - y - 1.0 },
        .size = .{ .width = 0.0, .height = 0.0 },
    };
    const global = windowObject(handle).msgSend(CGRect, "convertRectToScreen:", .{local});
    CGWarpMouseCursorPosition(.{ .x = global.origin.x, .y = transformY(global.origin.y) });
    CGAssociateMouseAndMouseCursorPosition(true);
}

pub fn setCursor(handle: *anyopaque, cursor_handle: ?*anyopaque) void {
    _ = handle;
    const cursor = if (cursor_handle) |value|
        objc.Object.fromId((@as(*types.Cursor, @ptrCast(@alignCast(value)))).cursor)
    else
        objc.getClass("NSCursor").?.msgSend(objc.Object, "arrowCursor", .{});
    cursor.msgSend(void, "set", .{});
}

pub fn setInputMode(handle: *anyopaque, mode: c_int, value: c_int) void {
    if (mode != 0) return;
    native(handle).cursor_mode = value;
    const cursor_class = objc.getClass("NSCursor").?;
    if (value == 1 or value == 2) {
        cursor_class.msgSend(void, "hide", .{});
    } else {
        cursor_class.msgSend(void, "unhide", .{});
    }
}

pub fn setClipboardString(value: [*:0]const u8) void {
    const ns_string = objc.getClass("NSString").?.msgSend(objc.Object, "stringWithUTF8String:", .{value});
    const pasteboard = objc.getClass("NSPasteboard").?.msgSend(objc.Object, "generalPasteboard", .{});
    _ = pasteboard.msgSend(usize, "clearContents", .{});
    _ = pasteboard.msgSend(bool, "setString:forType:", .{ ns_string.value, nsString("public.utf8-plain-text").value });
}

pub fn getClipboardString() ?[*:0]const u8 {
    const pasteboard = objc.getClass("NSPasteboard").?.msgSend(objc.Object, "generalPasteboard", .{});
    const value = pasteboard.msgSend(objc.Object, "stringForType:", .{nsString("public.utf8-plain-text").value});
    if (value.value == null) return null;
    return value.msgSend([*:0]const u8, "UTF8String", .{});
}

fn callbacks() EventCallbacks {
    return event_callbacks.?;
}

fn registerClasses() void {
    if (classes_registered) return;

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
    objc.registerClassPair(delegate_class.?);

    view_class = objc.allocateClassPair(objc.getClass("NSView"), "ZingZigContentView").?;
    _ = view_class.?.addIvar("zingWindow");
    _ = view_class.?.addIvar("trackingArea");
    _ = view_class.?.addMethod("initWithFrame:zingWindow:", viewInitWithFrame);
    _ = view_class.?.addMethod("dealloc", viewDealloc);
    _ = view_class.?.addMethod("acceptsFirstResponder", viewAcceptsFirstResponder);
    _ = view_class.?.addMethod("canBecomeKeyView", viewCanBecomeKeyView);
    _ = view_class.?.addMethod("acceptsFirstMouse:", viewAcceptsFirstMouse);
    _ = view_class.?.addMethod("wantsUpdateLayer", viewWantsUpdateLayer);
    _ = view_class.?.addMethod("updateLayer", viewUpdateLayer);
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
    objc.registerClassPair(view_class.?);

    classes_registered = true;
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
    const pos = getPos(@ptrCast(window));
    callbacks().pos(window.callback_id, pos.x, pos.y);
}

fn delegateWindowDidResize(self: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    const window = windowFromObject(objc.Object.fromId(self));
    const handle: *anyopaque = @ptrCast(window);
    const maximized = objc.Object.fromId(window.window).msgSend(bool, "isZoomed", .{});
    if (window.maximized != maximized) {
        window.maximized = maximized;
        callbacks().maximize(window.callback_id, maximized);
    }
    const size = getSize(handle);
    const framebuffer = getFramebufferSize(handle);
    const scale = getContentScale(handle);
    callbacks().size(window.callback_id, size.width, size.height);
    callbacks().framebuffer_size(window.callback_id, framebuffer.width, framebuffer.height);
    callbacks().content_scale(window.callback_id, scale.x_scale, scale.y_scale);
}

fn delegateWindowDidBecomeKey(self: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    callbacks().focus(windowFromObject(objc.Object.fromId(self)).callback_id, true);
}

fn delegateWindowDidResignKey(self: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    callbacks().focus(windowFromObject(objc.Object.fromId(self)).callback_id, false);
}

fn delegateWindowDidMiniaturize(self: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    callbacks().iconify(windowFromObject(objc.Object.fromId(self)).callback_id, true);
}

fn delegateWindowDidDeminiaturize(self: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    callbacks().iconify(windowFromObject(objc.Object.fromId(self)).callback_id, false);
}

fn viewInitWithFrame(self: objc.c.id, _: objc.c.SEL, frame: CGRect, window: objc.c.id) callconv(.c) objc.c.id {
    const object = objc.Object.fromId(self).msgSendSuper(objc.getClass("NSView").?, objc.Object, "initWithFrame:", .{frame});
    if (object.value == null) return null;

    setWindowIvar(object, window);
    setTrackingAreaIvar(object, null);
    object.msgSend(void, "setWantsLayer:", .{true});
    viewUpdateTrackingAreas(object.value, undefined);
    object.msgSend(void, "registerForDraggedTypes:", .{objc.getClass("NSArray").?.msgSend(objc.Object, "arrayWithObject:", .{nsString("public.file-url").value}).value});
    return object.value;
}

fn viewDealloc(self: objc.c.id, _: objc.c.SEL) callconv(.c) void {
    const object = objc.Object.fromId(self);
    if (getTrackingAreaIvar(object)) |tracking_area| objc.Object.fromId(tracking_area).msgSend(void, "release", .{});
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

fn viewWantsUpdateLayer(_: objc.c.id, _: objc.c.SEL) callconv(.c) bool {
    return true;
}

fn viewUpdateLayer(self: objc.c.id, _: objc.c.SEL) callconv(.c) void {
    callbacks().refresh(windowFromObject(objc.Object.fromId(self)).callback_id);
}

fn viewDrawRect(self: objc.c.id, _: objc.c.SEL, _: CGRect) callconv(.c) void {
    callbacks().refresh(windowFromObject(objc.Object.fromId(self)).callback_id);
}

fn viewDidChangeBackingProperties(self: objc.c.id, _: objc.c.SEL) callconv(.c) void {
    const object = objc.Object.fromId(self);
    object.msgSendSuper(objc.getClass("NSView").?, void, "viewDidChangeBackingProperties", .{});
    const window = windowFromObject(object);
    const handle: *anyopaque = @ptrCast(window);
    const framebuffer = getFramebufferSize(handle);
    const scale = getContentScale(handle);
    callbacks().framebuffer_size(window.callback_id, framebuffer.width, framebuffer.height);
    callbacks().content_scale(window.callback_id, scale.x_scale, scale.y_scale);
}

fn viewKeyDown(self: objc.c.id, _: objc.c.SEL, event_id: objc.c.id) callconv(.c) void {
    const window = windowFromObject(objc.Object.fromId(self));
    const event = objc.Object.fromId(event_id);
    const key_code: u16 = @intCast(event.msgSend(c_ushort, "keyCode", .{}));
    const mods = translateMods(event.msgSend(usize, "modifierFlags", .{}));
    callbacks().key(window.callback_id, input.translateKey(key_code), key_code, 1, mods);

    const chars = event.msgSend(objc.Object, "characters", .{});
    const len = chars.msgSend(usize, "length", .{});
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const codepoint: u32 = @intCast(chars.msgSend(c_ushort, "characterAtIndex:", .{i}));
        callbacks().char_mods(window.callback_id, codepoint, mods);
        callbacks().char(window.callback_id, codepoint);
    }
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
    const action: i32 = if (key_flag != 0 and (flags & key_flag) != 0 and (window.modifier_flags & key_flag) == 0) 1 else 0;
    window.modifier_flags = flags;
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
    const pos = cursorPosFromEvent(window, objc.Object.fromId(event_id));
    callbacks().cursor_pos(window.callback_id, @floatFromInt(pos.x), @floatFromInt(pos.y));
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
    callbacks().cursor_enter(windowFromObject(objc.Object.fromId(self)).callback_id, true);
}

fn viewMouseExited(self: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    callbacks().cursor_enter(windowFromObject(objc.Object.fromId(self)).callback_id, false);
}

fn viewDraggingEntered(_: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) c_ulong {
    return 4;
}

fn viewPerformDragOperation(self: objc.c.id, _: objc.c.SEL, sender_id: objc.c.id) callconv(.c) bool {
    const pasteboard = objc.Object.fromId(sender_id).msgSend(objc.Object, "draggingPasteboard", .{});
    const classes = objc.getClass("NSArray").?.msgSend(objc.Object, "arrayWithObject:", .{objc.getClass("NSURL").?.value});
    const options = objc.getClass("NSDictionary").?.msgSend(objc.Object, "dictionaryWithObject:forKey:", .{
        objc.getClass("NSNumber").?.msgSend(objc.Object, "numberWithBool:", .{true}).value,
        NSPasteboardURLReadingFileURLsOnlyKey,
    });
    const urls = pasteboard.msgSend(objc.Object, "readObjectsForClasses:options:", .{ classes.value, options.value });
    const count = urls.msgSend(usize, "count", .{});
    if (count == 0) return true;

    var path_buffer: [64][*:0]const u8 = undefined;
    const len = @min(count, path_buffer.len);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        path_buffer[i] = urls.msgSend(objc.Object, "objectAtIndex:", .{i}).msgSend([*:0]const u8, "fileSystemRepresentation", .{});
    }

    callbacks().drop(windowFromObject(objc.Object.fromId(self)).callback_id, len, &path_buffer);
    return true;
}

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

const CGDirectDisplayID = u32;

extern "c" fn CGMainDisplayID() CGDirectDisplayID;
extern "c" fn CGDisplayBounds(display: CGDirectDisplayID) CGRect;
extern "c" fn CGWarpMouseCursorPosition(point: CGPoint) void;
extern "c" fn CGAssociateMouseAndMouseCursorPosition(connected: bool) void;
extern "c" fn NSMouseInRect(point: CGPoint, rect: CGRect, flipped: bool) bool;
extern "c" var NSPasteboardURLReadingFileURLsOnlyKey: objc.c.id;
