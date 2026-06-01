const std = @import("std");

const poll_axes: u8 = 1;
const poll_buttons: u8 = 2;

const max_joysticks = 16;

const ConnectFn = *const fn (usize, []const u8, []const u8, usize, usize, usize) void;
const DisconnectFn = *const fn (usize) void;
const AxisFn = *const fn (usize, usize, f32) void;
const ButtonFn = *const fn (usize, usize, bool) void;
const HatFn = *const fn (usize, usize, u8) void;

const Callbacks = struct {
    connect: ConnectFn,
    disconnect: DisconnectFn,
    axis: AxisFn,
    button: ButtonFn,
    hat: HatFn,
};

const Element = struct {
    native: IOHIDElementRef,
    usage: u32,
    index: usize,
    minimum: c_long,
    maximum: c_long,
};

const Slot = struct {
    device: ?IOHIDDeviceRef = null,
    axes: std.ArrayList(Element) = .empty,
    buttons: std.ArrayList(Element) = .empty,
    hats: std.ArrayList(Element) = .empty,
};

var callbacks: ?Callbacks = null;
var hid_manager: ?IOHIDManagerRef = null;
var slots: [max_joysticks]Slot = @splat(.{});

pub fn init(new_callbacks: Callbacks) !void {
    callbacks = new_callbacks;

    hid_manager = IOHIDManagerCreate(null, kIOHIDOptionsTypeNone) orelse return error.PlatformError;
    errdefer {
        if (hid_manager) |manager| CFRelease(manager);
        hid_manager = null;
    }

    const matching = CFArrayCreateMutable(null, 0, &kCFTypeArrayCallBacks) orelse return error.PlatformError;
    defer CFRelease(matching);

    const usages = [_]c_long{
        kHIDUsage_GD_Joystick,
        kHIDUsage_GD_GamePad,
        kHIDUsage_GD_MultiAxisController,
    };

    for (usages) |usage| {
        const dict = createMatchingDictionary(kHIDPage_GenericDesktop, usage) orelse continue;
        CFArrayAppendValue(matching, dict);
        CFRelease(dict);
    }

    IOHIDManagerSetDeviceMatchingMultiple(hid_manager.?, matching);
    IOHIDManagerRegisterDeviceMatchingCallback(hid_manager.?, matchCallback, null);
    IOHIDManagerRegisterDeviceRemovalCallback(hid_manager.?, removeCallback, null);
    IOHIDManagerScheduleWithRunLoop(hid_manager.?, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    _ = IOHIDManagerOpen(hid_manager.?, kIOHIDOptionsTypeNone);

    _ = CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.0, false);
}

pub fn deinit() void {
    for (0..max_joysticks) |index| closeSlot(index);
    if (hid_manager) |manager| {
        CFRelease(manager);
        hid_manager = null;
    }
    callbacks = null;
    slots = @splat(.{});
}

pub fn poll(index: usize, mode: u8) !bool {
    if (index >= max_joysticks) return false;
    if (slots[index].device == null) return false;

    const slot = &slots[index];
    if ((mode & poll_axes) != 0) {
        for (slot.axes.items, 0..) |*axis, axis_index| {
            const raw = getElementValue(slot, axis);
            if (raw < axis.minimum) axis.minimum = raw;
            if (raw > axis.maximum) axis.maximum = raw;

            const size = axis.maximum - axis.minimum;
            const value: f32 = if (size == 0)
                0
            else
                (2.0 * @as(f32, @floatFromInt(raw - axis.minimum)) / @as(f32, @floatFromInt(size))) - 1.0;
            callbacks.?.axis(index, axis_index, value);
        }
    }

    if ((mode & poll_buttons) != 0) {
        for (slot.buttons.items, 0..) |*button, button_index| {
            callbacks.?.button(index, button_index, getElementValue(slot, button) - button.minimum > 0);
        }

        const states = [_]u8{
            0x01,
            0x03,
            0x02,
            0x06,
            0x04,
            0x0c,
            0x08,
            0x09,
            0x00,
        };
        for (slot.hats.items, 0..) |*hat, hat_index| {
            var state = getElementValue(slot, hat) - hat.minimum;
            if (state < 0 or state > 8) state = 8;
            callbacks.?.hat(index, hat_index, states[@intCast(state)]);
        }
    }

    return true;
}

pub fn updateGamepadGuid(guid: *[33:0]u8) void {
    if (std.mem.eql(u8, guid[4..16], "000000000000") and std.mem.eql(u8, guid[20..32], "000000000000")) {
        const original = guid.*;
        _ = std.fmt.bufPrintSentinel(guid, "03000000{s}0000{s}000000000000", .{
            original[0..4],
            original[16..20],
        }, 0) catch {};
    }
}

fn matchCallback(_: ?*anyopaque, _: IOReturn, _: ?*anyopaque, device: IOHIDDeviceRef) callconv(.c) void {
    for (slots) |slot| {
        if (slot.device == device) return;
    }

    const elements = IOHIDDeviceCopyMatchingElements(device, null, kIOHIDOptionsTypeNone) orelse return;
    defer CFRelease(elements);

    const slot_index = firstFreeSlot() orelse return;
    const slot = &slots[slot_index];

    var name: [256:0]u8 = @splat(0);
    readStringProperty(device, "Product", &name) orelse @memcpy(name[0.."Unknown".len], "Unknown");

    const vendor = readU32Property(device, "VendorID");
    const product = readU32Property(device, "ProductID");
    const version = readU32Property(device, "VersionNumber");
    var guid: [33:0]u8 = @splat(0);
    if (vendor != 0 and product != 0) {
        _ = std.fmt.bufPrintSentinel(&guid, "03000000{x:0>2}{x:0>2}0000{x:0>2}{x:0>2}0000{x:0>2}{x:0>2}0000", .{
            @as(u8, @truncate(vendor)),
            @as(u8, @truncate(vendor >> 8)),
            @as(u8, @truncate(product)),
            @as(u8, @truncate(product >> 8)),
            @as(u8, @truncate(version)),
            @as(u8, @truncate(version >> 8)),
        }, 0) catch return;
    } else {
        _ = std.fmt.bufPrintSentinel(&guid, "05000000{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}00", .{
            name[0], name[1], name[2], name[3], name[4], name[5], name[6], name[7], name[8], name[9], name[10],
        }, 0) catch return;
    }

    const count = CFArrayGetCount(elements);
    var i: CFIndex = 0;
    while (i < count) : (i += 1) {
        const element: IOHIDElementRef = @ptrCast(@alignCast(CFArrayGetValueAtIndex(elements, i) orelse continue));
        if (CFGetTypeID(element) != IOHIDElementGetTypeID()) continue;

        const element_type = IOHIDElementGetType(element);
        if (element_type != kIOHIDElementTypeInput_Axis and
            element_type != kIOHIDElementTypeInput_Button and
            element_type != kIOHIDElementTypeInput_Misc)
        {
            continue;
        }

        const usage = IOHIDElementGetUsage(element);
        const page = IOHIDElementGetUsagePage(element);
        const target = targetForUsage(slot, page, usage) orelse continue;
        appendElement(target.list, element, usage);
    }

    sortElements(slot.axes.items);
    sortElements(slot.buttons.items);
    sortElements(slot.hats.items);

    _ = CFRetain(device);
    slot.device = device;
    callbacks.?.connect(slot_index, std.mem.sliceTo(&name, 0), guid[0..32], slot.axes.items.len, slot.buttons.items.len, slot.hats.items.len);
}

fn removeCallback(_: ?*anyopaque, _: IOReturn, _: ?*anyopaque, device: IOHIDDeviceRef) callconv(.c) void {
    for (slots, 0..) |slot, index| {
        if (slot.device == device) {
            closeSlot(index);
            return;
        }
    }
}

fn closeSlot(index: usize) void {
    if (slots[index].device) |device| {
        callbacks.?.disconnect(index);
        CFRelease(device);
        slots[index].axes.deinit(std.heap.c_allocator);
        slots[index].buttons.deinit(std.heap.c_allocator);
        slots[index].hats.deinit(std.heap.c_allocator);
        slots[index] = .{};
    }
}

fn getElementValue(slot: *const Slot, element: *const Element) c_long {
    const device = slot.device orelse return 0;
    var value_ref: ?IOHIDValueRef = null;
    if (IOHIDDeviceGetValue(device, element.native, &value_ref) == kIOReturnSuccess) {
        if (value_ref) |value| return IOHIDValueGetIntegerValue(value);
    }
    return 0;
}

const Target = struct {
    list: *std.ArrayList(Element),
};

fn targetForUsage(slot: *Slot, page: u32, usage: u32) ?Target {
    if (page == kHIDPage_GenericDesktop) {
        switch (usage) {
            kHIDUsage_GD_X,
            kHIDUsage_GD_Y,
            kHIDUsage_GD_Z,
            kHIDUsage_GD_Rx,
            kHIDUsage_GD_Ry,
            kHIDUsage_GD_Rz,
            kHIDUsage_GD_Slider,
            kHIDUsage_GD_Dial,
            kHIDUsage_GD_Wheel,
            => return .{ .list = &slot.axes },
            kHIDUsage_GD_Hatswitch => return .{ .list = &slot.hats },
            kHIDUsage_GD_DPadUp,
            kHIDUsage_GD_DPadRight,
            kHIDUsage_GD_DPadDown,
            kHIDUsage_GD_DPadLeft,
            kHIDUsage_GD_SystemMainMenu,
            kHIDUsage_GD_Select,
            kHIDUsage_GD_Start,
            => return .{ .list = &slot.buttons },
            else => {},
        }
    } else if (page == kHIDPage_Simulation) {
        switch (usage) {
            kHIDUsage_Sim_Accelerator,
            kHIDUsage_Sim_Brake,
            kHIDUsage_Sim_Throttle,
            kHIDUsage_Sim_Rudder,
            kHIDUsage_Sim_Steering,
            => return .{ .list = &slot.axes },
            else => {},
        }
    } else if (page == kHIDPage_Button or page == kHIDPage_Consumer) {
        return .{ .list = &slot.buttons };
    }
    return null;
}

fn appendElement(list: *std.ArrayList(Element), native: IOHIDElementRef, usage: u32) void {
    list.append(std.heap.c_allocator, .{
        .native = native,
        .usage = usage,
        .index = list.items.len,
        .minimum = IOHIDElementGetLogicalMin(native),
        .maximum = IOHIDElementGetLogicalMax(native),
    }) catch {};
}

fn sortElements(elements: []Element) void {
    std.mem.sort(Element, elements, {}, struct {
        fn lessThan(_: void, lhs: Element, rhs: Element) bool {
            if (lhs.usage != rhs.usage) return lhs.usage < rhs.usage;
            return lhs.index < rhs.index;
        }
    }.lessThan);
}

fn firstFreeSlot() ?usize {
    for (slots, 0..) |slot, index| {
        if (slot.device == null) return index;
    }
    return null;
}

fn createMatchingDictionary(page: c_long, usage: c_long) ?CFMutableDictionaryRef {
    const dict = CFDictionaryCreateMutable(null, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks) orelse return null;
    errdefer CFRelease(dict);

    const page_ref = CFNumberCreate(null, kCFNumberLongType, &page);
    defer if (page_ref) |value| CFRelease(value);
    const usage_ref = CFNumberCreate(null, kCFNumberLongType, &usage);
    defer if (usage_ref) |value| CFRelease(value);
    if (page_ref == null or usage_ref == null) return null;

    setDictionaryNumber(dict, "DeviceUsagePage", page_ref.?);
    setDictionaryNumber(dict, "DeviceUsage", usage_ref.?);
    return dict;
}

fn setDictionaryNumber(dict: CFMutableDictionaryRef, key_text: [:0]const u8, value: CFNumberRef) void {
    const key = CFStringCreateWithCString(null, key_text.ptr, kCFStringEncodingUTF8) orelse return;
    defer CFRelease(key);
    CFDictionarySetValue(dict, key, value);
}

fn readStringProperty(device: IOHIDDeviceRef, key_text: [:0]const u8, out: *[256:0]u8) ?void {
    const key = CFStringCreateWithCString(null, key_text.ptr, kCFStringEncodingUTF8) orelse return null;
    defer CFRelease(key);
    const property = IOHIDDeviceGetProperty(device, key) orelse return null;
    if (!CFStringGetCString(@ptrCast(property), out, out.len, kCFStringEncodingUTF8)) return null;
}

fn readU32Property(device: IOHIDDeviceRef, key_text: [:0]const u8) u32 {
    const key = CFStringCreateWithCString(null, key_text.ptr, kCFStringEncodingUTF8) orelse return 0;
    defer CFRelease(key);
    const property = IOHIDDeviceGetProperty(device, key) orelse return 0;
    var value: i32 = 0;
    if (!CFNumberGetValue(@ptrCast(property), kCFNumberSInt32Type, &value)) return 0;
    return @bitCast(value);
}

const CFTypeRef = *const anyopaque;
const CFStringRef = *const anyopaque;
const CFNumberRef = *const anyopaque;
const CFMutableArrayRef = *anyopaque;
const CFMutableDictionaryRef = *anyopaque;
const CFRunLoopRef = *anyopaque;
const CFRunLoopMode = CFStringRef;
const CFIndex = isize;
const CFTypeID = usize;
const IOReturn = c_int;
const IOHIDManagerRef = *opaque {};
const IOHIDDeviceRef = *opaque {};
const IOHIDElementRef = *const opaque {};
const IOHIDValueRef = *opaque {};
const IOOptionBits = u32;

const CFArrayCallBacks = opaque {};
const CFDictionaryKeyCallBacks = opaque {};
const CFDictionaryValueCallBacks = opaque {};

const kIOReturnSuccess: IOReturn = 0;
const kIOHIDOptionsTypeNone: IOOptionBits = 0;
const kCFNumberSInt32Type: c_int = 3;
const kCFNumberLongType: c_int = 10;
const kCFStringEncodingUTF8: u32 = 0x08000100;

const kIOHIDElementTypeInput_Misc: u32 = 1;
const kIOHIDElementTypeInput_Button: u32 = 2;
const kIOHIDElementTypeInput_Axis: u32 = 3;

const kHIDPage_GenericDesktop: c_long = 0x01;
const kHIDPage_Simulation: c_long = 0x02;
const kHIDPage_Button: c_long = 0x09;
const kHIDPage_Consumer: c_long = 0x0c;

const kHIDUsage_GD_Joystick: c_long = 0x04;
const kHIDUsage_GD_GamePad: c_long = 0x05;
const kHIDUsage_GD_MultiAxisController: c_long = 0x08;
const kHIDUsage_GD_X: u32 = 0x30;
const kHIDUsage_GD_Y: u32 = 0x31;
const kHIDUsage_GD_Z: u32 = 0x32;
const kHIDUsage_GD_Rx: u32 = 0x33;
const kHIDUsage_GD_Ry: u32 = 0x34;
const kHIDUsage_GD_Rz: u32 = 0x35;
const kHIDUsage_GD_Slider: u32 = 0x36;
const kHIDUsage_GD_Dial: u32 = 0x37;
const kHIDUsage_GD_Wheel: u32 = 0x38;
const kHIDUsage_GD_Hatswitch: u32 = 0x39;
const kHIDUsage_GD_Start: u32 = 0x3d;
const kHIDUsage_GD_Select: u32 = 0x3e;
const kHIDUsage_GD_SystemMainMenu: u32 = 0x85;
const kHIDUsage_GD_DPadUp: u32 = 0x90;
const kHIDUsage_GD_DPadDown: u32 = 0x91;
const kHIDUsage_GD_DPadRight: u32 = 0x92;
const kHIDUsage_GD_DPadLeft: u32 = 0x93;

const kHIDUsage_Sim_Rudder: u32 = 0xba;
const kHIDUsage_Sim_Throttle: u32 = 0xbb;
const kHIDUsage_Sim_Accelerator: u32 = 0xc4;
const kHIDUsage_Sim_Brake: u32 = 0xc5;
const kHIDUsage_Sim_Steering: u32 = 0xc8;

extern "c" var kCFTypeArrayCallBacks: CFArrayCallBacks;
extern "c" var kCFTypeDictionaryKeyCallBacks: CFDictionaryKeyCallBacks;
extern "c" var kCFTypeDictionaryValueCallBacks: CFDictionaryValueCallBacks;
extern "c" var kCFRunLoopDefaultMode: CFRunLoopMode;

extern "c" fn CFRelease(cf: CFTypeRef) void;
extern "c" fn CFRetain(cf: CFTypeRef) CFTypeRef;
extern "c" fn CFGetTypeID(cf: CFTypeRef) CFTypeID;
extern "c" fn CFArrayCreateMutable(allocator: ?CFTypeRef, capacity: CFIndex, callbacks: ?*const CFArrayCallBacks) ?CFMutableArrayRef;
extern "c" fn CFArrayAppendValue(array: CFMutableArrayRef, value: CFTypeRef) void;
extern "c" fn CFArrayGetCount(array: CFTypeRef) CFIndex;
extern "c" fn CFArrayGetValueAtIndex(array: CFTypeRef, index: CFIndex) ?CFTypeRef;
extern "c" fn CFDictionaryCreateMutable(allocator: ?CFTypeRef, capacity: CFIndex, key_callbacks: ?*const CFDictionaryKeyCallBacks, value_callbacks: ?*const CFDictionaryValueCallBacks) ?CFMutableDictionaryRef;
extern "c" fn CFDictionarySetValue(dictionary: CFMutableDictionaryRef, key: CFTypeRef, value: CFTypeRef) void;
extern "c" fn CFNumberCreate(allocator: ?CFTypeRef, number_type: c_int, value: *const c_long) ?CFNumberRef;
extern "c" fn CFNumberGetValue(number: CFNumberRef, number_type: c_int, value: *i32) bool;
extern "c" fn CFStringCreateWithCString(allocator: ?CFTypeRef, c_string: [*:0]const u8, encoding: u32) ?CFStringRef;
extern "c" fn CFStringGetCString(string: CFStringRef, buffer: [*]u8, buffer_size: CFIndex, encoding: u32) bool;
extern "c" fn CFRunLoopGetMain() CFRunLoopRef;
extern "c" fn CFRunLoopRunInMode(mode: CFRunLoopMode, seconds: f64, return_after_source_handled: bool) c_int;

extern "c" fn IOHIDManagerCreate(allocator: ?CFTypeRef, options: IOOptionBits) ?IOHIDManagerRef;
extern "c" fn IOHIDManagerSetDeviceMatchingMultiple(manager: IOHIDManagerRef, multiple: CFTypeRef) void;
extern "c" fn IOHIDManagerRegisterDeviceMatchingCallback(manager: IOHIDManagerRef, callback: *const fn (?*anyopaque, IOReturn, ?*anyopaque, IOHIDDeviceRef) callconv(.c) void, context: ?*anyopaque) void;
extern "c" fn IOHIDManagerRegisterDeviceRemovalCallback(manager: IOHIDManagerRef, callback: *const fn (?*anyopaque, IOReturn, ?*anyopaque, IOHIDDeviceRef) callconv(.c) void, context: ?*anyopaque) void;
extern "c" fn IOHIDManagerScheduleWithRunLoop(manager: IOHIDManagerRef, run_loop: CFRunLoopRef, mode: CFRunLoopMode) void;
extern "c" fn IOHIDManagerOpen(manager: IOHIDManagerRef, options: IOOptionBits) IOReturn;
extern "c" fn IOHIDDeviceCopyMatchingElements(device: IOHIDDeviceRef, matching: ?CFTypeRef, options: IOOptionBits) ?CFTypeRef;
extern "c" fn IOHIDDeviceGetProperty(device: IOHIDDeviceRef, key: CFStringRef) ?CFTypeRef;
extern "c" fn IOHIDDeviceGetValue(device: IOHIDDeviceRef, element: IOHIDElementRef, value: *?IOHIDValueRef) IOReturn;
extern "c" fn IOHIDElementGetTypeID() CFTypeID;
extern "c" fn IOHIDElementGetType(element: IOHIDElementRef) u32;
extern "c" fn IOHIDElementGetUsage(element: IOHIDElementRef) u32;
extern "c" fn IOHIDElementGetUsagePage(element: IOHIDElementRef) u32;
extern "c" fn IOHIDElementGetLogicalMin(element: IOHIDElementRef) c_long;
extern "c" fn IOHIDElementGetLogicalMax(element: IOHIDElementRef) c_long;
extern "c" fn IOHIDValueGetIntegerValue(value: IOHIDValueRef) c_long;
