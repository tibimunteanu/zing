const input = @import("input.zig");
const objc = @import("objc.zig");
const types = @import("types.zig");

const NSEventTypeLeftMouseDown: isize = 1;
const NSEventTypeLeftMouseUp: isize = 2;
const NSEventTypeRightMouseDown: isize = 3;
const NSEventTypeRightMouseUp: isize = 4;
const NSEventTypeMouseMoved: isize = 5;
const NSEventTypeKeyDown: isize = 10;
const NSEventTypeKeyUp: isize = 11;
const NSEventTypeOtherMouseDown: isize = 25;
const NSEventTypeOtherMouseUp: isize = 26;

const NSEventModifierFlagCapsLock: usize = 1 << 16;
const NSEventModifierFlagShift: usize = 1 << 17;
const NSEventModifierFlagControl: usize = 1 << 18;
const NSEventModifierFlagOption: usize = 1 << 19;
const NSEventModifierFlagCommand: usize = 1 << 20;

pub fn pumpEvents(timeout: f64) void {
    const until = objc.getClass("NSDate").?.msgSend(objc.Object, "dateWithTimeIntervalSinceNow:", .{timeout});
    while (true) {
        const event = sharedApplication().msgSend(objc.Object, "nextEventMatchingMask:untilDate:inMode:dequeue:", .{
            @as(usize, ~@as(usize, 0)),
            objc.getClass("NSDate").?.msgSend(objc.Object, "distantPast", .{}).value,
            nsString("kCFRunLoopDefaultMode").value,
            true,
        });
        if (event.value != null) {
            sharedApplication().msgSend(void, "sendEvent:", .{event.value});
        } else if (until.msgSend(f64, "timeIntervalSinceNow", .{}) <= 0.0) {
            break;
        } else {
            _ = objc.getClass("NSRunLoop").?.msgSend(objc.Object, "currentRunLoop", .{}).msgSend(bool, "runMode:beforeDate:", .{
                nsString("kCFRunLoopDefaultMode").value,
                objc.getClass("NSDate").?.msgSend(objc.Object, "dateWithTimeIntervalSinceNow:", .{@as(f64, 0.001)}).value,
            });
        }
    }
}

pub fn postKey(handle: *anyopaque, scancode: c_int, pressed: bool, mods: u8) bool {
    if (scancode < 0 or scancode > 0xffff) return false;

    const flags = nativeMods(mods);
    const chars = charactersForScancode(@intCast(scancode), flags);
    const event = objc.getClass("NSEvent").?.msgSend(objc.Object, "keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:", .{
        if (pressed) @as(isize, NSEventTypeKeyDown) else @as(isize, NSEventTypeKeyUp),
        CGPoint{ .x = 0.0, .y = 0.0 },
        flags,
        objc.getClass("NSDate").?.msgSend(f64, "timeIntervalSinceReferenceDate", .{}),
        windowObject(handle).msgSend(isize, "windowNumber", .{}),
        @as(objc.c.id, null),
        chars.value,
        chars.value,
        false,
        @as(c_ushort, @intCast(scancode)),
    });
    if (event.value == null) return false;
    sharedApplication().msgSend(void, "postEvent:atStart:", .{ event.value, false });
    return true;
}

pub fn postMouseMove(handle: *anyopaque, x: f64, y: f64) bool {
    const content = viewObject(handle).msgSend(CGRect, "frame", .{});
    const event = objc.getClass("NSEvent").?.msgSend(objc.Object, "mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:", .{
        @as(isize, NSEventTypeMouseMoved),
        CGPoint{ .x = x, .y = content.size.height - y },
        @as(usize, 0),
        objc.getClass("NSDate").?.msgSend(f64, "timeIntervalSinceReferenceDate", .{}),
        windowObject(handle).msgSend(isize, "windowNumber", .{}),
        @as(objc.c.id, null),
        @as(isize, 0),
        @as(isize, 0),
        @as(f64, 0.0),
    });
    if (event.value == null) return false;
    sharedApplication().msgSend(void, "postEvent:atStart:", .{ event.value, false });
    return true;
}

pub fn postMouseButton(handle: *anyopaque, button: c_int, pressed: bool, x: f64, y: f64, mods: u8) bool {
    const content = viewObject(handle).msgSend(CGRect, "frame", .{});
    const event_type: isize = if (button == 0)
        if (pressed) NSEventTypeLeftMouseDown else NSEventTypeLeftMouseUp
    else if (button == 1)
        if (pressed) NSEventTypeRightMouseDown else NSEventTypeRightMouseUp
    else if (pressed) NSEventTypeOtherMouseDown else NSEventTypeOtherMouseUp;

    const event = objc.getClass("NSEvent").?.msgSend(objc.Object, "mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:", .{
        event_type,
        CGPoint{ .x = x, .y = content.size.height - y },
        nativeMods(mods),
        objc.getClass("NSDate").?.msgSend(f64, "timeIntervalSinceReferenceDate", .{}),
        windowObject(handle).msgSend(isize, "windowNumber", .{}),
        @as(objc.c.id, null),
        @as(isize, 0),
        @as(isize, 1),
        if (pressed) @as(f64, 1.0) else @as(f64, 0.0),
    });
    if (event.value == null) return false;

    const view = viewObject(handle);
    if (button == 0) {
        view.msgSend(void, if (pressed) "mouseDown:" else "mouseUp:", .{event.value});
    } else if (button == 1) {
        view.msgSend(void, if (pressed) "rightMouseDown:" else "rightMouseUp:", .{event.value});
    } else {
        view.msgSend(void, if (pressed) "otherMouseDown:" else "otherMouseUp:", .{event.value});
    }
    return true;
}

pub fn postScroll(handle: *anyopaque, xoffset: f64, yoffset: f64) bool {
    const cg_event = CGEventCreateScrollWheelEvent(null, 0, 2, @intFromFloat(yoffset), @intFromFloat(xoffset)) orelse return false;
    defer CFRelease(cg_event);

    const event = objc.getClass("NSEvent").?.msgSend(objc.Object, "eventWithCGEvent:", .{cg_event});
    if (event.value == null) return false;
    viewObject(handle).msgSend(void, "scrollWheel:", .{event.value});
    return true;
}

fn nativeMods(mods: u8) usize {
    var flags: usize = 0;
    if ((mods & (1 << 0)) != 0) flags |= NSEventModifierFlagShift;
    if ((mods & (1 << 1)) != 0) flags |= NSEventModifierFlagControl;
    if ((mods & (1 << 2)) != 0) flags |= NSEventModifierFlagOption;
    if ((mods & (1 << 3)) != 0) flags |= NSEventModifierFlagCommand;
    if ((mods & (1 << 4)) != 0) flags |= NSEventModifierFlagCapsLock;
    return flags;
}

fn charactersForScancode(scancode: u16, flags: usize) objc.Object {
    const key = input.translateKey(scancode);
    var text = [_:0]u8{ 0, 0 };
    if (key >= 65 and key <= 90) {
        text[0] = @intCast(if ((flags & NSEventModifierFlagShift) != 0) key else key + ('a' - 'A'));
        return nsString(text[0..1 :0]);
    }
    if (key >= 48 and key <= 57) {
        text[0] = @intCast(key);
        return nsString(text[0..1 :0]);
    }

    return nsString(switch (key) {
        32 => " ",
        39 => "'",
        44 => ",",
        45 => "-",
        46 => ".",
        47 => "/",
        59 => ";",
        61 => "=",
        91 => "[",
        92 => "\\",
        93 => "]",
        96 => "`",
        else => "",
    });
}

fn windowObject(handle: *anyopaque) objc.Object {
    const window: *types.Window = @ptrCast(@alignCast(handle));
    return objc.Object.fromId(window.window);
}

fn viewObject(handle: *anyopaque) objc.Object {
    const window: *types.Window = @ptrCast(@alignCast(handle));
    return objc.Object.fromId(window.view);
}

fn sharedApplication() objc.Object {
    return objc.getClass("NSApplication").?.msgSend(objc.Object, "sharedApplication", .{});
}

fn nsString(value: [:0]const u8) objc.Object {
    return objc.getClass("NSString").?.msgSend(objc.Object, "stringWithUTF8String:", .{value.ptr});
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

const CGEventRef = *opaque {};

extern "c" fn CGEventCreateScrollWheelEvent(source: ?*anyopaque, units: u32, wheel_count: u32, wheel1: i32, wheel2: i32) ?CGEventRef;
extern "c" fn CFRelease(object: *anyopaque) void;
