const objc = @import("objc.zig");

pub fn poll() void {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const app = sharedApplication();
    while (true) {
        const event = nextEvent(NSDate.distantPast());
        if (event.value == null) break;
        app.msgSend(void, "sendEvent:", .{event.value});
    }
}

pub fn wait() void {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const app = sharedApplication();
    const event = nextEvent(NSDate.distantFuture());
    app.msgSend(void, "sendEvent:", .{event.value});

    poll();
}

pub fn waitTimeout(timeout: f64) void {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const app = sharedApplication();
    const event = nextEvent(NSDate.dateWithTimeIntervalSinceNow(timeout));
    if (event.value != null) app.msgSend(void, "sendEvent:", .{event.value});

    poll();
}

pub fn postEmpty() void {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

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

fn nextEvent(limit: objc.Object) objc.Object {
    const mode = nsString("kCFRunLoopDefaultMode");
    return sharedApplication().msgSend(objc.Object, "nextEventMatchingMask:untilDate:inMode:dequeue:", .{
        @as(usize, ~@as(usize, 0)),
        limit.value,
        mode.value,
        true,
    });
}

fn sharedApplication() objc.Object {
    return objc.getClass("NSApplication").?.msgSend(objc.Object, "sharedApplication", .{});
}

const NSDate = struct {
    fn distantPast() objc.Object {
        return objc.getClass("NSDate").?.msgSend(objc.Object, "distantPast", .{});
    }

    fn distantFuture() objc.Object {
        return objc.getClass("NSDate").?.msgSend(objc.Object, "distantFuture", .{});
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
