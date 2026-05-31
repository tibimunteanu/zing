const objc = @import("objc.zig");

const distant_future: f64 = 63113904000.0;

pub fn poll() void {
    drainEvents(false, 0.0);
}

pub fn wait() void {
    drainEvents(true, distant_future);
}

pub fn waitTimeout(timeout: f64) void {
    drainEvents(true, timeout);
}

pub fn postEmpty() void {
    const event = objc.getClass("NSEvent").?.msgSend(objc.Object, "otherEventWithType:location:modifierFlags:timestamp:windowNumber:context:subtype:data1:data2:", .{
        @as(isize, 15),
        CGPoint{ .x = 0.0, .y = 0.0 },
        @as(usize, 0),
        @as(f64, 0.0),
        @as(isize, 0),
        @as(objc.c.id, null),
        @as(c_short, 0),
        @as(isize, 0),
        @as(isize, 0),
    });
    sharedApplication().msgSend(void, "postEvent:atStart:", .{ event.value, true });
}

fn drainEvents(block: bool, timeout: f64) void {
    const mode = nsString("kCFRunLoopDefaultMode");
    const limit = if (block) NSDate.dateWithTimeIntervalSinceNow(timeout) else NSDate.distantPast();
    const app = sharedApplication();

    while (true) {
        const event = app.msgSend(objc.Object, "nextEventMatchingMask:untilDate:inMode:dequeue:", .{
            @as(usize, ~@as(usize, 0)),
            limit.value,
            mode.value,
            true,
        });
        if (event.value == null) break;

        app.msgSend(void, "sendEvent:", .{event.value});
        app.msgSend(void, "updateWindows", .{});
        if (block) break;
    }
}

fn sharedApplication() objc.Object {
    return objc.getClass("NSApplication").?.msgSend(objc.Object, "sharedApplication", .{});
}

const NSDate = struct {
    fn distantPast() objc.Object {
        return objc.getClass("NSDate").?.msgSend(objc.Object, "distantPast", .{});
    }

    fn dateWithTimeIntervalSinceNow(seconds: f64) objc.Object {
        return objc.getClass("NSDate").?.msgSend(objc.Object, "dateWithTimeIntervalSinceNow:", .{seconds});
    }
};

fn nsString(value: [:0]const u8) objc.Object {
    const cls = objc.getClass("NSString").?;
    return cls.msgSend(objc.Object, "stringWithUTF8String:", .{value.ptr});
}

const CGPoint = extern struct {
    x: f64,
    y: f64,
};
