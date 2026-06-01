const std = @import("std");
const helper = @import("helper.zig");
const win32 = @import("types.zig");

pub const Joystick = struct {};

const poll_presence: u8 = 0;
const poll_axes: u8 = 1;
const poll_buttons: u8 = 2;

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

const max_joysticks = 16;
const max_di_objects = 192;
const XUSER_MAX_COUNT = 4;

const ERROR_SUCCESS: win32.DWORD = 0;
const ERROR_DEVICE_NOT_CONNECTED: win32.DWORD = 1167;
const ERROR_READ_FAULT: u32 = 30;
const ERROR_INVALID_ACCESS: u32 = 12;
const SEVERITY_ERROR: u32 = 1;
const FACILITY_WIN32: u32 = 7;
const DIERR_INPUTLOST: win32.HRESULT = @bitCast(makeHRESULT(SEVERITY_ERROR, FACILITY_WIN32, ERROR_READ_FAULT));
const DIERR_NOTACQUIRED: win32.HRESULT = @bitCast(makeHRESULT(SEVERITY_ERROR, FACILITY_WIN32, ERROR_INVALID_ACCESS));

const XINPUT_DEVTYPE_GAMEPAD: u8 = 1;
const XINPUT_DEVSUBTYPE_WHEEL: u8 = 2;
const XINPUT_DEVSUBTYPE_ARCADE_STICK: u8 = 3;
const XINPUT_DEVSUBTYPE_FLIGHT_STICK: u8 = 4;
const XINPUT_DEVSUBTYPE_DANCE_PAD: u8 = 5;
const XINPUT_DEVSUBTYPE_GUITAR: u8 = 6;
const XINPUT_DEVSUBTYPE_DRUM_KIT: u8 = 8;
const XINPUT_CAPS_WIRELESS: u16 = 0x0002;

const XINPUT_GAMEPAD_DPAD_UP: u16 = 0x0001;
const XINPUT_GAMEPAD_DPAD_DOWN: u16 = 0x0002;
const XINPUT_GAMEPAD_DPAD_LEFT: u16 = 0x0004;
const XINPUT_GAMEPAD_DPAD_RIGHT: u16 = 0x0008;
const XINPUT_GAMEPAD_START: u16 = 0x0010;
const XINPUT_GAMEPAD_BACK: u16 = 0x0020;
const XINPUT_GAMEPAD_LEFT_THUMB: u16 = 0x0040;
const XINPUT_GAMEPAD_RIGHT_THUMB: u16 = 0x0080;
const XINPUT_GAMEPAD_LEFT_SHOULDER: u16 = 0x0100;
const XINPUT_GAMEPAD_RIGHT_SHOULDER: u16 = 0x0200;
const XINPUT_GAMEPAD_A: u16 = 0x1000;
const XINPUT_GAMEPAD_B: u16 = 0x2000;
const XINPUT_GAMEPAD_X: u16 = 0x4000;
const XINPUT_GAMEPAD_Y: u16 = 0x8000;

const DIRECTINPUT_VERSION: win32.DWORD = 0x0800;
const DI8DEVCLASS_GAMECTRL: win32.DWORD = 4;
const DIEDFL_ALLDEVICES: win32.DWORD = 0;
const DIENUM_STOP: win32.BOOL = 0;
const DIENUM_CONTINUE: win32.BOOL = 1;
const DIDFT_AXIS: win32.DWORD = 0x00000003;
const DIDFT_ABSAXIS: win32.DWORD = 0x00000002;
const DIDFT_BUTTON: win32.DWORD = 0x0000000c;
const DIDFT_POV: win32.DWORD = 0x00000010;
const DIDFT_ANYINSTANCE: win32.DWORD = 0x00ffff00;
const DIDFT_OPTIONAL: win32.DWORD = 0x80000000;
const DIDOI_ASPECTPOSITION: win32.DWORD = 0x00000100;
const DIPH_DEVICE: win32.DWORD = 0;
const DIPH_BYID: win32.DWORD = 2;
const DIPROPAXISMODE_ABS: win32.DWORD = 0;
const DI_DEGREES: win32.DWORD = 100;
const RIM_TYPEHID: win32.DWORD = 2;
const RIDI_DEVICENAME: win32.UINT = 0x20000007;
const RIDI_DEVICEINFO: win32.UINT = 0x2000000b;

const ObjectType = enum(u8) {
    axis,
    slider,
    button,
    pov,
};

const JoyObject = struct {
    offset: usize,
    kind: ObjectType,
};

const SlotKind = enum {
    none,
    xinput,
    dinput,
};

const Slot = struct {
    kind: SlotKind = .none,
    xinput_index: win32.DWORD = 0,
    dinput_device: ?*IDirectInputDevice8W = null,
    dinput_guid: GUID = zero_guid,
    objects: [max_di_objects]JoyObject = @splat(.{ .offset = 0, .kind = .axis }),
    object_count: usize = 0,
};

const ObjectEnum = struct {
    device: *IDirectInputDevice8W,
    objects: *[max_di_objects]JoyObject,
    object_count: usize = 0,
    axis_count: usize = 0,
    slider_count: usize = 0,
    button_count: usize = 0,
    pov_count: usize = 0,
};

var callbacks: ?Callbacks = null;
var slots: [max_joysticks]Slot = @splat(.{});
var xinput_module: win32.HMODULE = null;
var xinput_get_state: ?XInputGetStateFn = null;
var xinput_get_capabilities: ?XInputGetCapabilitiesFn = null;
var dinput_module: win32.HMODULE = null;
var direct_input_create: ?DirectInput8CreateFn = null;
var dinput: ?*IDirectInput8W = null;

pub fn init(new_callbacks: Callbacks) !void {
    callbacks = new_callbacks;
    _ = helper.retain();
    helper.setDeviceChangeCallbacks(detectConnection, detectDisconnection);
    loadXInput();
    loadDirectInput();
    detectConnections();
}

pub fn deinit() void {
    for (0..max_joysticks) |index| closeSlot(index);
    if (dinput) |api| _ = api.lpVtbl.Release(api);
    if (dinput_module) |module| _ = win32.FreeLibrary(module);
    if (xinput_module) |module| _ = win32.FreeLibrary(module);

    callbacks = null;
    dinput = null;
    direct_input_create = null;
    dinput_module = null;
    xinput_module = null;
    xinput_get_state = null;
    xinput_get_capabilities = null;
    slots = @splat(.{});
    helper.setDeviceChangeCallbacks(null, null);
    helper.release();
}

pub fn poll(index: usize, mode: u8) !bool {
    if (index >= max_joysticks) return false;
    if (slots[index].kind == .none) detectConnections();

    return switch (slots[index].kind) {
        .none => false,
        .xinput => pollXInput(index, mode),
        .dinput => pollDirectInput(index, mode),
    };
}

pub fn updateGamepadGuid(guid: *[33:0]u8) void {
    if (std.mem.eql(u8, guid[20..32], "504944564944")) {
        const original = guid.*;
        _ = std.fmt.bufPrintSentinel(guid, "03000000{s}0000{s}000000000000", .{
            original[0..4],
            original[4..8],
        }, 0) catch {};
    }
}

fn loadXInput() void {
    const names = [_][*:0]const u8{
        "xinput1_4.dll",
        "xinput1_3.dll",
        "xinput9_1_0.dll",
    };

    for (names) |name| {
        const module = win32.LoadLibraryA(name) orelse continue;
        const get_state = win32.GetProcAddress(module, "XInputGetState") orelse {
            _ = win32.FreeLibrary(module);
            continue;
        };
        const get_capabilities = win32.GetProcAddress(module, "XInputGetCapabilities") orelse {
            _ = win32.FreeLibrary(module);
            continue;
        };

        xinput_module = module;
        xinput_get_state = @ptrCast(get_state);
        xinput_get_capabilities = @ptrCast(get_capabilities);
        return;
    }
}

fn loadDirectInput() void {
    const module = win32.LoadLibraryA("dinput8.dll") orelse return;
    const create_proc = win32.GetProcAddress(module, "DirectInput8Create") orelse {
        _ = win32.FreeLibrary(module);
        return;
    };

    dinput_module = module;
    direct_input_create = @ptrCast(create_proc);

    var api: ?*IDirectInput8W = null;
    const create = direct_input_create.?;
    if (failed(create(win32.instance, DIRECTINPUT_VERSION, &IID_IDirectInput8W, @ptrCast(&api), null))) {
        direct_input_create = null;
        dinput_module = null;
        _ = win32.FreeLibrary(module);
        return;
    }

    dinput = api;
}

fn detectConnections() void {
    detectXInputConnections();
    detectDirectInputConnections();
}

pub fn detectConnection() void {
    detectConnections();
}

pub fn detectDisconnection() void {
    for (0..max_joysticks) |index| {
        if (slots[index].kind != .none) _ = poll(index, poll_presence) catch false;
    }
}

fn detectXInputConnections() void {
    if (xinput_get_capabilities == null) return;

    for (0..XUSER_MAX_COUNT) |index| {
        if (findXInputSlot(@intCast(index)) != null) continue;
        connectXInput(index);
    }
}

fn connectXInput(index: usize) void {
    const get_capabilities = xinput_get_capabilities orelse return;

    var capabilities: XINPUT_CAPABILITIES = undefined;
    if (get_capabilities(@intCast(index), 0, &capabilities) != ERROR_SUCCESS) return;
    if (capabilities.Type != XINPUT_DEVTYPE_GAMEPAD) return;

    const slot_index = firstFreeSlot() orelse return;
    var guid: [33:0]u8 = @splat(0);
    _ = std.fmt.bufPrintSentinel(&guid, "78696e707574{x:0>2}000000000000000000", .{capabilities.SubType}, 0) catch return;

    slots[slot_index] = .{
        .kind = .xinput,
        .xinput_index = @intCast(index),
    };

    if (callbacks) |cb| {
        cb.connect(slot_index, getXInputDeviceDescription(capabilities), guid[0..32], 6, 10, 1);
    }
}

fn pollXInput(slot_index: usize, mode: u8) bool {
    const get_state = xinput_get_state orelse return false;

    var state: XINPUT_STATE = undefined;
    const result = get_state(slots[slot_index].xinput_index, &state);
    if (result != ERROR_SUCCESS) {
        if (result == ERROR_DEVICE_NOT_CONNECTED) closeSlot(slot_index);
        return false;
    }

    if (mode == poll_presence) return true;
    inputXInput(slot_index, state.Gamepad);
    return true;
}

fn inputXInput(index: usize, gamepad: XINPUT_GAMEPAD) void {
    const cb = callbacks orelse return;

    cb.axis(index, 0, (@as(f32, @floatFromInt(gamepad.sThumbLX)) + 0.5) / 32767.5);
    cb.axis(index, 1, -((@as(f32, @floatFromInt(gamepad.sThumbLY)) + 0.5) / 32767.5));
    cb.axis(index, 2, (@as(f32, @floatFromInt(gamepad.sThumbRX)) + 0.5) / 32767.5);
    cb.axis(index, 3, -((@as(f32, @floatFromInt(gamepad.sThumbRY)) + 0.5) / 32767.5));
    cb.axis(index, 4, @as(f32, @floatFromInt(gamepad.bLeftTrigger)) / 127.5 - 1.0);
    cb.axis(index, 5, @as(f32, @floatFromInt(gamepad.bRightTrigger)) / 127.5 - 1.0);

    const buttons = [_]u16{
        XINPUT_GAMEPAD_A,
        XINPUT_GAMEPAD_B,
        XINPUT_GAMEPAD_X,
        XINPUT_GAMEPAD_Y,
        XINPUT_GAMEPAD_LEFT_SHOULDER,
        XINPUT_GAMEPAD_RIGHT_SHOULDER,
        XINPUT_GAMEPAD_BACK,
        XINPUT_GAMEPAD_START,
        XINPUT_GAMEPAD_LEFT_THUMB,
        XINPUT_GAMEPAD_RIGHT_THUMB,
    };

    for (buttons, 0..) |mask, button| {
        cb.button(index, button, (gamepad.wButtons & mask) != 0);
    }

    var dpad: u8 = 0;
    if ((gamepad.wButtons & XINPUT_GAMEPAD_DPAD_UP) != 0) dpad |= 0x01;
    if ((gamepad.wButtons & XINPUT_GAMEPAD_DPAD_RIGHT) != 0) dpad |= 0x02;
    if ((gamepad.wButtons & XINPUT_GAMEPAD_DPAD_DOWN) != 0) dpad |= 0x04;
    if ((gamepad.wButtons & XINPUT_GAMEPAD_DPAD_LEFT) != 0) dpad |= 0x08;
    if ((dpad & 0x02) != 0 and (dpad & 0x08) != 0) dpad &= ~@as(u8, 0x02 | 0x08);
    if ((dpad & 0x01) != 0 and (dpad & 0x04) != 0) dpad &= ~@as(u8, 0x01 | 0x04);
    cb.hat(index, 0, dpad);
}

fn detectDirectInputConnections() void {
    const api = dinput orelse return;
    _ = api.lpVtbl.EnumDevices(api, DI8DEVCLASS_GAMECTRL, deviceCallback, null, DIEDFL_ALLDEVICES);
}

fn deviceCallback(instance: *const DIDEVICEINSTANCEW, _: ?*anyopaque) callconv(.winapi) win32.BOOL {
    if (findDirectInputSlot(instance.guidInstance) != null) return DIENUM_CONTINUE;
    if (supportsXInput(instance.guidProduct)) return DIENUM_CONTINUE;

    const api = dinput orelse return DIENUM_STOP;
    const slot_index = firstFreeSlot() orelse return DIENUM_STOP;
    var device: ?*IDirectInputDevice8W = null;
    if (failed(api.lpVtbl.CreateDevice(api, &instance.guidInstance, &device, null)) or device == null) {
        return DIENUM_CONTINUE;
    }
    errdefer _ = device.?.lpVtbl.Release(device.?);

    if (failed(device.?.lpVtbl.SetDataFormat(device.?, &data_format))) return DIENUM_CONTINUE;

    var caps = DIDEVCAPS{};
    caps.dwSize = @sizeOf(DIDEVCAPS);
    if (failed(device.?.lpVtbl.GetCapabilities(device.?, &caps))) return DIENUM_CONTINUE;

    var axis_mode = DIPROPDWORD{
        .diph = .{
            .dwSize = @sizeOf(DIPROPDWORD),
            .dwHeaderSize = @sizeOf(DIPROPHEADER),
            .dwHow = DIPH_DEVICE,
        },
        .dwData = DIPROPAXISMODE_ABS,
    };
    if (failed(device.?.lpVtbl.SetProperty(device.?, diprop(2), &axis_mode.diph))) return DIENUM_CONTINUE;

    var objects: [max_di_objects]JoyObject = @splat(.{ .offset = 0, .kind = .axis });
    var data = ObjectEnum{
        .device = device.?,
        .objects = &objects,
    };

    if (failed(device.?.lpVtbl.EnumObjects(device.?, deviceObjectCallback, &data, DIDFT_AXIS | DIDFT_BUTTON | DIDFT_POV))) {
        return DIENUM_CONTINUE;
    }

    std.mem.sort(JoyObject, objects[0..data.object_count], {}, struct {
        fn lessThan(_: void, a: JoyObject, b: JoyObject) bool {
            if (a.kind != b.kind) return @intFromEnum(a.kind) < @intFromEnum(b.kind);
            return a.offset < b.offset;
        }
    }.lessThan);

    var name: [256:0]u8 = @splat(0);
    const name_len = std.unicode.wtf16LeToWtf8(name[0 .. name.len - 1], std.mem.sliceTo(&instance.tszInstanceName, 0));
    name[name_len] = 0;

    var guid: [33:0]u8 = @splat(0);
    if (std.mem.eql(u8, instance.guidProduct.Data4[2..8], "PIDVID")) {
        _ = std.fmt.bufPrintSentinel(&guid, "03000000{x:0>2}{x:0>2}0000{x:0>2}{x:0>2}000000000000", .{
            @as(u8, @truncate(instance.guidProduct.Data1)),
            @as(u8, @truncate(instance.guidProduct.Data1 >> 8)),
            @as(u8, @truncate(instance.guidProduct.Data1 >> 16)),
            @as(u8, @truncate(instance.guidProduct.Data1 >> 24)),
        }, 0) catch return DIENUM_CONTINUE;
    } else {
        _ = std.fmt.bufPrintSentinel(&guid, "05000000{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}00", .{
            name[0], name[1], name[2], name[3], name[4], name[5], name[6], name[7], name[8], name[9], name[10],
        }, 0) catch return DIENUM_CONTINUE;
    }

    slots[slot_index] = .{
        .kind = .dinput,
        .dinput_device = device.?,
        .dinput_guid = instance.guidInstance,
        .objects = objects,
        .object_count = data.object_count,
    };

    if (callbacks) |cb| {
        cb.connect(slot_index, std.mem.sliceTo(&name, 0), guid[0..32], data.axis_count + data.slider_count, data.button_count, data.pov_count);
    }

    return DIENUM_CONTINUE;
}

fn deviceObjectCallback(object_instance: *const DIDEVICEOBJECTINSTANCEW, user: ?*anyopaque) callconv(.winapi) win32.BOOL {
    const data: *ObjectEnum = @ptrCast(@alignCast(user.?));
    if (data.object_count >= max_di_objects) return DIENUM_STOP;

    var object = JoyObject{ .offset = 0, .kind = .axis };
    const object_type = object_instance.dwType & 0xff;

    if ((object_type & DIDFT_AXIS) != 0) {
        if (std.meta.eql(object_instance.guidType, GUID_Slider)) {
            object.offset = dijofsSlider(data.slider_count);
            object.kind = .slider;
            data.slider_count += 1;
        } else if (std.meta.eql(object_instance.guidType, GUID_XAxis)) {
            object.offset = @offsetOf(DIJOYSTATE, "lX");
            object.kind = .axis;
            data.axis_count += 1;
        } else if (std.meta.eql(object_instance.guidType, GUID_YAxis)) {
            object.offset = @offsetOf(DIJOYSTATE, "lY");
            object.kind = .axis;
            data.axis_count += 1;
        } else if (std.meta.eql(object_instance.guidType, GUID_ZAxis)) {
            object.offset = @offsetOf(DIJOYSTATE, "lZ");
            object.kind = .axis;
            data.axis_count += 1;
        } else if (std.meta.eql(object_instance.guidType, GUID_RxAxis)) {
            object.offset = @offsetOf(DIJOYSTATE, "lRx");
            object.kind = .axis;
            data.axis_count += 1;
        } else if (std.meta.eql(object_instance.guidType, GUID_RyAxis)) {
            object.offset = @offsetOf(DIJOYSTATE, "lRy");
            object.kind = .axis;
            data.axis_count += 1;
        } else if (std.meta.eql(object_instance.guidType, GUID_RzAxis)) {
            object.offset = @offsetOf(DIJOYSTATE, "lRz");
            object.kind = .axis;
            data.axis_count += 1;
        } else {
            return DIENUM_CONTINUE;
        }

        var range = DIPROPRANGE{
            .diph = .{
                .dwSize = @sizeOf(DIPROPRANGE),
                .dwHeaderSize = @sizeOf(DIPROPHEADER),
                .dwObj = object_instance.dwType,
                .dwHow = DIPH_BYID,
            },
            .lMin = -32768,
            .lMax = 32767,
        };
        if (failed(data.device.lpVtbl.SetProperty(data.device, diprop(4), &range.diph))) return DIENUM_CONTINUE;
    } else if ((object_type & DIDFT_BUTTON) != 0) {
        object.offset = dijofsButton(data.button_count);
        object.kind = .button;
        data.button_count += 1;
    } else if ((object_type & DIDFT_POV) != 0) {
        object.offset = dijofsPov(data.pov_count);
        object.kind = .pov;
        data.pov_count += 1;
    } else {
        return DIENUM_CONTINUE;
    }

    data.objects[data.object_count] = object;
    data.object_count += 1;
    return DIENUM_CONTINUE;
}

fn pollDirectInput(slot_index: usize, mode: u8) bool {
    const device = slots[slot_index].dinput_device orelse return false;
    _ = device.lpVtbl.Poll(device);

    var state: DIJOYSTATE = .{};
    var result = device.lpVtbl.GetDeviceState(device, @sizeOf(DIJOYSTATE), &state);
    if (result == DIERR_NOTACQUIRED or result == DIERR_INPUTLOST) {
        _ = device.lpVtbl.Acquire(device);
        _ = device.lpVtbl.Poll(device);
        result = device.lpVtbl.GetDeviceState(device, @sizeOf(DIJOYSTATE), &state);
    }

    if (failed(result)) {
        closeSlot(slot_index);
        return false;
    }

    if (mode == poll_presence) return true;

    const bytes = std.mem.asBytes(&state);
    var axis_index: usize = 0;
    var button_index: usize = 0;
    var pov_index: usize = 0;

    for (slots[slot_index].objects[0..slots[slot_index].object_count]) |object| {
        switch (object.kind) {
            .axis, .slider => {
                if ((mode & poll_axes) == 0) continue;
                const raw: *const win32.LONG = @ptrCast(@alignCast(bytes[object.offset..].ptr));
                const value = (@as(f32, @floatFromInt(raw.*)) + 0.5) / 32767.5;
                if (callbacks) |cb| cb.axis(slot_index, axis_index, value);
                axis_index += 1;
            },
            .button => {
                if ((mode & poll_buttons) == 0) continue;
                const pressed = (bytes[object.offset] & 0x80) != 0;
                if (callbacks) |cb| cb.button(slot_index, button_index, pressed);
                button_index += 1;
            },
            .pov => {
                if ((mode & poll_buttons) == 0) continue;
                const states = [_]u8{ 0x01, 0x03, 0x02, 0x06, 0x04, 0x0c, 0x08, 0x09, 0x00 };
                const raw: *const win32.DWORD = @ptrCast(@alignCast(bytes[object.offset..].ptr));
                var state_index = raw.* / (45 * DI_DEGREES);
                if (state_index > 8) state_index = 8;
                if (callbacks) |cb| cb.hat(slot_index, pov_index, states[state_index]);
                pov_index += 1;
            },
        }
    }

    return true;
}

fn closeSlot(index: usize) void {
    const old_kind = slots[index].kind;
    if (slots[index].dinput_device) |device| {
        _ = device.lpVtbl.Unacquire(device);
        _ = device.lpVtbl.Release(device);
    }

    slots[index] = .{};
    if (old_kind != .none) {
        if (callbacks) |cb| cb.disconnect(index);
    }
}

fn firstFreeSlot() ?usize {
    for (slots, 0..) |slot, index| {
        if (slot.kind == .none) return index;
    }
    return null;
}

fn findXInputSlot(index: win32.DWORD) ?usize {
    for (slots, 0..) |slot, slot_index| {
        if (slot.kind == .xinput and slot.xinput_index == index) return slot_index;
    }
    return null;
}

fn findDirectInputSlot(guid: GUID) ?usize {
    for (slots, 0..) |slot, slot_index| {
        if (slot.kind == .dinput and std.meta.eql(slot.dinput_guid, guid)) return slot_index;
    }
    return null;
}

fn getXInputDeviceDescription(capabilities: XINPUT_CAPABILITIES) []const u8 {
    return switch (capabilities.SubType) {
        XINPUT_DEVSUBTYPE_WHEEL => "XInput Wheel",
        XINPUT_DEVSUBTYPE_ARCADE_STICK => "XInput Arcade Stick",
        XINPUT_DEVSUBTYPE_FLIGHT_STICK => "XInput Flight Stick",
        XINPUT_DEVSUBTYPE_DANCE_PAD => "XInput Dance Pad",
        XINPUT_DEVSUBTYPE_GUITAR => "XInput Guitar",
        XINPUT_DEVSUBTYPE_DRUM_KIT => "XInput Drum Kit",
        1 => if ((capabilities.Flags & XINPUT_CAPS_WIRELESS) != 0) "Wireless Xbox Controller" else "Xbox Controller",
        else => "Unknown XInput Device",
    };
}

fn supportsXInput(guid: GUID) bool {
    var count: win32.UINT = 0;
    if (GetRawInputDeviceList(null, &count, @sizeOf(RAWINPUTDEVICELIST)) != 0) return false;

    const allocator = std.heap.c_allocator;
    const list = allocator.alloc(RAWINPUTDEVICELIST, count) catch return false;
    defer allocator.free(list);

    if (GetRawInputDeviceList(list.ptr, &count, @sizeOf(RAWINPUTDEVICELIST)) == std.math.maxInt(win32.UINT)) return false;

    for (list[0..count]) |item| {
        if (item.dwType != RIM_TYPEHID) continue;

        var info: RID_DEVICE_INFO = .{ .cbSize = @sizeOf(RID_DEVICE_INFO), .dwType = 0, .u = .{ .hid = .{} } };
        var info_size: win32.UINT = @sizeOf(RID_DEVICE_INFO);
        if (GetRawInputDeviceInfoA(item.hDevice, RIDI_DEVICEINFO, &info, &info_size) == @as(win32.UINT, @bitCast(@as(c_int, -1)))) continue;
        if (makeLong(info.u.hid.dwVendorId, info.u.hid.dwProductId) != @as(win32.LONG, @bitCast(guid.Data1))) continue;

        var name: [256:0]u8 = @splat(0);
        var name_size: win32.UINT = name.len;
        if (GetRawInputDeviceInfoA(item.hDevice, RIDI_DEVICENAME, &name, &name_size) == @as(win32.UINT, @bitCast(@as(c_int, -1)))) break;
        if (std.mem.indexOf(u8, std.mem.sliceTo(&name, 0), "IG_") != null) return true;
    }

    return false;
}

fn makeHRESULT(severity: u32, facility: u32, code: u32) u32 {
    return (severity << 31) | (facility << 16) | code;
}

fn failed(result: win32.HRESULT) bool {
    return result < 0;
}

fn makeLong(low: win32.WORD, high: win32.WORD) win32.LONG {
    return @bitCast(@as(u32, low) | (@as(u32, high) << 16));
}

fn diprop(value: usize) *const GUID {
    return @ptrFromInt(value);
}

fn dijofsSlider(index: usize) usize {
    return @offsetOf(DIJOYSTATE, "rglSlider") + index * @sizeOf(win32.LONG);
}

fn dijofsPov(index: usize) usize {
    return @offsetOf(DIJOYSTATE, "rgdwPOV") + index * @sizeOf(win32.DWORD);
}

fn dijofsButton(index: usize) usize {
    return @offsetOf(DIJOYSTATE, "rgbButtons") + index;
}

const XINPUT_GAMEPAD = extern struct {
    wButtons: u16,
    bLeftTrigger: u8,
    bRightTrigger: u8,
    sThumbLX: i16,
    sThumbLY: i16,
    sThumbRX: i16,
    sThumbRY: i16,
};

const XINPUT_STATE = extern struct {
    dwPacketNumber: win32.DWORD,
    Gamepad: XINPUT_GAMEPAD,
};

const XINPUT_CAPABILITIES = extern struct {
    Type: u8,
    SubType: u8,
    Flags: u16,
    Gamepad: XINPUT_GAMEPAD,
    Vibration: extern struct {
        wLeftMotorSpeed: u16,
        wRightMotorSpeed: u16,
    },
};

const GUID = extern struct {
    Data1: u32,
    Data2: u16,
    Data3: u16,
    Data4: [8]u8,
};

const IDirectInput8W = extern struct {
    lpVtbl: *const VTable,

    const VTable = extern struct {
        QueryInterface: *const fn (*IDirectInput8W, *const GUID, *?*anyopaque) callconv(.winapi) win32.HRESULT,
        AddRef: *const fn (*IDirectInput8W) callconv(.winapi) win32.ULONG,
        Release: *const fn (*IDirectInput8W) callconv(.winapi) win32.ULONG,
        CreateDevice: *const fn (*IDirectInput8W, *const GUID, *?*IDirectInputDevice8W, ?*anyopaque) callconv(.winapi) win32.HRESULT,
        EnumDevices: *const fn (*IDirectInput8W, win32.DWORD, EnumDevicesCallback, ?*anyopaque, win32.DWORD) callconv(.winapi) win32.HRESULT,
        GetDeviceStatus: *const fn (*IDirectInput8W, *const GUID) callconv(.winapi) win32.HRESULT,
        RunControlPanel: *const fn (*IDirectInput8W, win32.HWND, win32.DWORD) callconv(.winapi) win32.HRESULT,
        Initialize: *const fn (*IDirectInput8W, win32.HINSTANCE, win32.DWORD) callconv(.winapi) win32.HRESULT,
        FindDevice: *const fn (*IDirectInput8W, *const GUID, win32.LPCWSTR, *GUID) callconv(.winapi) win32.HRESULT,
        EnumDevicesBySemantics: *const anyopaque,
        ConfigureDevices: *const anyopaque,
    };
};

const IDirectInputDevice8W = extern struct {
    lpVtbl: *const VTable,

    const VTable = extern struct {
        QueryInterface: *const fn (*IDirectInputDevice8W, *const GUID, *?*anyopaque) callconv(.winapi) win32.HRESULT,
        AddRef: *const fn (*IDirectInputDevice8W) callconv(.winapi) win32.ULONG,
        Release: *const fn (*IDirectInputDevice8W) callconv(.winapi) win32.ULONG,
        GetCapabilities: *const fn (*IDirectInputDevice8W, *DIDEVCAPS) callconv(.winapi) win32.HRESULT,
        EnumObjects: *const fn (*IDirectInputDevice8W, EnumObjectsCallback, ?*anyopaque, win32.DWORD) callconv(.winapi) win32.HRESULT,
        GetProperty: *const fn (*IDirectInputDevice8W, *const GUID, *DIPROPHEADER) callconv(.winapi) win32.HRESULT,
        SetProperty: *const fn (*IDirectInputDevice8W, *const GUID, *const DIPROPHEADER) callconv(.winapi) win32.HRESULT,
        Acquire: *const fn (*IDirectInputDevice8W) callconv(.winapi) win32.HRESULT,
        Unacquire: *const fn (*IDirectInputDevice8W) callconv(.winapi) win32.HRESULT,
        GetDeviceState: *const fn (*IDirectInputDevice8W, win32.DWORD, ?*anyopaque) callconv(.winapi) win32.HRESULT,
        GetDeviceData: *const fn (*IDirectInputDevice8W, win32.DWORD, ?*anyopaque, *win32.DWORD, win32.DWORD) callconv(.winapi) win32.HRESULT,
        SetDataFormat: *const fn (*IDirectInputDevice8W, *const DIDATAFORMAT) callconv(.winapi) win32.HRESULT,
        SetEventNotification: *const fn (*IDirectInputDevice8W, win32.HANDLE) callconv(.winapi) win32.HRESULT,
        SetCooperativeLevel: *const fn (*IDirectInputDevice8W, win32.HWND, win32.DWORD) callconv(.winapi) win32.HRESULT,
        GetObjectInfo: *const fn (*IDirectInputDevice8W, *DIDEVICEOBJECTINSTANCEW, win32.DWORD, win32.DWORD) callconv(.winapi) win32.HRESULT,
        GetDeviceInfo: *const fn (*IDirectInputDevice8W, *DIDEVICEINSTANCEW) callconv(.winapi) win32.HRESULT,
        RunControlPanel: *const fn (*IDirectInputDevice8W, win32.HWND, win32.DWORD) callconv(.winapi) win32.HRESULT,
        Initialize: *const fn (*IDirectInputDevice8W, win32.HINSTANCE, win32.DWORD, *const GUID) callconv(.winapi) win32.HRESULT,
        CreateEffect: *const anyopaque,
        EnumEffects: *const anyopaque,
        GetEffectInfo: *const anyopaque,
        GetForceFeedbackState: *const anyopaque,
        SendForceFeedbackCommand: *const anyopaque,
        EnumCreatedEffectObjects: *const anyopaque,
        Escape: *const anyopaque,
        Poll: *const fn (*IDirectInputDevice8W) callconv(.winapi) win32.HRESULT,
        SendDeviceData: *const anyopaque,
        EnumEffectsInFile: *const anyopaque,
        WriteEffectToFile: *const anyopaque,
        BuildActionMap: *const anyopaque,
        SetActionMap: *const anyopaque,
        GetImageInfo: *const anyopaque,
    };
};

const EnumDevicesCallback = *const fn (*const DIDEVICEINSTANCEW, ?*anyopaque) callconv(.winapi) win32.BOOL;
const EnumObjectsCallback = *const fn (*const DIDEVICEOBJECTINSTANCEW, ?*anyopaque) callconv(.winapi) win32.BOOL;
const XInputGetStateFn = *const fn (win32.DWORD, *XINPUT_STATE) callconv(.winapi) win32.DWORD;
const XInputGetCapabilitiesFn = *const fn (win32.DWORD, win32.DWORD, *XINPUT_CAPABILITIES) callconv(.winapi) win32.DWORD;
const DirectInput8CreateFn = *const fn (win32.HINSTANCE, win32.DWORD, *const GUID, *?*anyopaque, ?*anyopaque) callconv(.winapi) win32.HRESULT;

const DIDEVICEINSTANCEW = extern struct {
    dwSize: win32.DWORD = @sizeOf(DIDEVICEINSTANCEW),
    guidInstance: GUID,
    guidProduct: GUID,
    dwDevType: win32.DWORD,
    tszInstanceName: [260:0]win32.WCHAR,
    tszProductName: [260:0]win32.WCHAR,
    guidFFDriver: GUID,
    wUsagePage: win32.WORD,
    wUsage: win32.WORD,
};

const DIDEVICEOBJECTINSTANCEW = extern struct {
    dwSize: win32.DWORD,
    guidType: GUID,
    dwOfs: win32.DWORD,
    dwType: win32.DWORD,
    dwFlags: win32.DWORD,
    tszName: [260:0]win32.WCHAR,
    dwFFMaxForce: win32.DWORD,
    dwFFForceResolution: win32.DWORD,
    wCollectionNumber: win32.WORD,
    wDesignatorIndex: win32.WORD,
    wUsagePage: win32.WORD,
    wUsage: win32.WORD,
    dwDimension: win32.DWORD,
    wExponent: win32.WORD,
    wReportId: win32.WORD,
};

const DIDEVCAPS = extern struct {
    dwSize: win32.DWORD = @sizeOf(DIDEVCAPS),
    dwFlags: win32.DWORD = 0,
    dwDevType: win32.DWORD = 0,
    dwAxes: win32.DWORD = 0,
    dwButtons: win32.DWORD = 0,
    dwPOVs: win32.DWORD = 0,
    dwFFSamplePeriod: win32.DWORD = 0,
    dwFFMinTimeResolution: win32.DWORD = 0,
    dwFirmwareRevision: win32.DWORD = 0,
    dwHardwareRevision: win32.DWORD = 0,
    dwFFDriverVersion: win32.DWORD = 0,
};

const DIPROPHEADER = extern struct {
    dwSize: win32.DWORD = 0,
    dwHeaderSize: win32.DWORD = 0,
    dwObj: win32.DWORD = 0,
    dwHow: win32.DWORD = 0,
};

const DIPROPDWORD = extern struct {
    diph: DIPROPHEADER,
    dwData: win32.DWORD,
};

const DIPROPRANGE = extern struct {
    diph: DIPROPHEADER,
    lMin: win32.LONG,
    lMax: win32.LONG,
};

const DIOBJECTDATAFORMAT = extern struct {
    pguid: ?*const GUID,
    dwOfs: win32.DWORD,
    dwType: win32.DWORD,
    dwFlags: win32.DWORD,
};

const DIDATAFORMAT = extern struct {
    dwSize: win32.DWORD,
    dwObjSize: win32.DWORD,
    dwFlags: win32.DWORD,
    dwDataSize: win32.DWORD,
    dwNumObjs: win32.DWORD,
    rgodf: [*]DIOBJECTDATAFORMAT,
};

const DIJOYSTATE = extern struct {
    lX: win32.LONG = 0,
    lY: win32.LONG = 0,
    lZ: win32.LONG = 0,
    lRx: win32.LONG = 0,
    lRy: win32.LONG = 0,
    lRz: win32.LONG = 0,
    rglSlider: [2]win32.LONG = @splat(0),
    rgdwPOV: [4]win32.DWORD = @splat(0xffffffff),
    rgbButtons: [32]win32.BYTE = @splat(0),
};

const RAWINPUTDEVICELIST = extern struct {
    hDevice: win32.HANDLE,
    dwType: win32.DWORD,
};

const RID_DEVICE_INFO = extern struct {
    cbSize: win32.DWORD,
    dwType: win32.DWORD,
    u: extern union {
        mouse: extern struct {
            dwId: win32.DWORD = 0,
            dwNumberOfButtons: win32.DWORD = 0,
            dwSampleRate: win32.DWORD = 0,
            fHasHorizontalWheel: win32.BOOL = 0,
        },
        keyboard: extern struct {
            dwType: win32.DWORD = 0,
            dwSubType: win32.DWORD = 0,
            dwKeyboardMode: win32.DWORD = 0,
            dwNumberOfFunctionKeys: win32.DWORD = 0,
            dwNumberOfIndicators: win32.DWORD = 0,
            dwNumberOfKeysTotal: win32.DWORD = 0,
        },
        hid: extern struct {
            dwVendorId: win32.DWORD = 0,
            dwProductId: win32.DWORD = 0,
            dwVersionNumber: win32.DWORD = 0,
            usUsagePage: win32.WORD = 0,
            usUsage: win32.WORD = 0,
        },
    },
};

extern "user32" fn GetRawInputDeviceList(?[*]RAWINPUTDEVICELIST, *win32.UINT, win32.UINT) callconv(.winapi) win32.UINT;
extern "user32" fn GetRawInputDeviceInfoA(win32.HANDLE, win32.UINT, ?*anyopaque, *win32.UINT) callconv(.winapi) win32.UINT;

const zero_guid = GUID{ .Data1 = 0, .Data2 = 0, .Data3 = 0, .Data4 = @splat(0) };
const IID_IDirectInput8W = GUID{ .Data1 = 0xbf798031, .Data2 = 0x483a, .Data3 = 0x4da2, .Data4 = .{ 0xaa, 0x99, 0x5d, 0x64, 0xed, 0x36, 0x97, 0x00 } };
const GUID_XAxis = GUID{ .Data1 = 0xa36d02e0, .Data2 = 0xc9f3, .Data3 = 0x11cf, .Data4 = .{ 0xbf, 0xc7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00 } };
const GUID_YAxis = GUID{ .Data1 = 0xa36d02e1, .Data2 = 0xc9f3, .Data3 = 0x11cf, .Data4 = .{ 0xbf, 0xc7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00 } };
const GUID_ZAxis = GUID{ .Data1 = 0xa36d02e2, .Data2 = 0xc9f3, .Data3 = 0x11cf, .Data4 = .{ 0xbf, 0xc7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00 } };
const GUID_RxAxis = GUID{ .Data1 = 0xa36d02f4, .Data2 = 0xc9f3, .Data3 = 0x11cf, .Data4 = .{ 0xbf, 0xc7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00 } };
const GUID_RyAxis = GUID{ .Data1 = 0xa36d02f5, .Data2 = 0xc9f3, .Data3 = 0x11cf, .Data4 = .{ 0xbf, 0xc7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00 } };
const GUID_RzAxis = GUID{ .Data1 = 0xa36d02e3, .Data2 = 0xc9f3, .Data3 = 0x11cf, .Data4 = .{ 0xbf, 0xc7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00 } };
const GUID_Slider = GUID{ .Data1 = 0xa36d02e4, .Data2 = 0xc9f3, .Data3 = 0x11cf, .Data4 = .{ 0xbf, 0xc7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00 } };
const GUID_POV = GUID{ .Data1 = 0xa36d02f2, .Data2 = 0xc9f3, .Data3 = 0x11cf, .Data4 = .{ 0xbf, 0xc7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00 } };

var object_data_formats = [_]DIOBJECTDATAFORMAT{
    .{ .pguid = &GUID_XAxis, .dwOfs = @offsetOf(DIJOYSTATE, "lX"), .dwType = DIDFT_AXIS | DIDFT_OPTIONAL | DIDFT_ANYINSTANCE, .dwFlags = DIDOI_ASPECTPOSITION },
    .{ .pguid = &GUID_YAxis, .dwOfs = @offsetOf(DIJOYSTATE, "lY"), .dwType = DIDFT_AXIS | DIDFT_OPTIONAL | DIDFT_ANYINSTANCE, .dwFlags = DIDOI_ASPECTPOSITION },
    .{ .pguid = &GUID_ZAxis, .dwOfs = @offsetOf(DIJOYSTATE, "lZ"), .dwType = DIDFT_AXIS | DIDFT_OPTIONAL | DIDFT_ANYINSTANCE, .dwFlags = DIDOI_ASPECTPOSITION },
    .{ .pguid = &GUID_RxAxis, .dwOfs = @offsetOf(DIJOYSTATE, "lRx"), .dwType = DIDFT_AXIS | DIDFT_OPTIONAL | DIDFT_ANYINSTANCE, .dwFlags = DIDOI_ASPECTPOSITION },
    .{ .pguid = &GUID_RyAxis, .dwOfs = @offsetOf(DIJOYSTATE, "lRy"), .dwType = DIDFT_AXIS | DIDFT_OPTIONAL | DIDFT_ANYINSTANCE, .dwFlags = DIDOI_ASPECTPOSITION },
    .{ .pguid = &GUID_RzAxis, .dwOfs = @offsetOf(DIJOYSTATE, "lRz"), .dwType = DIDFT_AXIS | DIDFT_OPTIONAL | DIDFT_ANYINSTANCE, .dwFlags = DIDOI_ASPECTPOSITION },
    .{ .pguid = &GUID_Slider, .dwOfs = dijofsSlider(0), .dwType = DIDFT_AXIS | DIDFT_OPTIONAL | DIDFT_ANYINSTANCE, .dwFlags = DIDOI_ASPECTPOSITION },
    .{ .pguid = &GUID_Slider, .dwOfs = dijofsSlider(1), .dwType = DIDFT_AXIS | DIDFT_OPTIONAL | DIDFT_ANYINSTANCE, .dwFlags = DIDOI_ASPECTPOSITION },
    .{ .pguid = &GUID_POV, .dwOfs = dijofsPov(0), .dwType = DIDFT_POV | DIDFT_OPTIONAL | DIDFT_ANYINSTANCE, .dwFlags = 0 },
    .{ .pguid = &GUID_POV, .dwOfs = dijofsPov(1), .dwType = DIDFT_POV | DIDFT_OPTIONAL | DIDFT_ANYINSTANCE, .dwFlags = 0 },
    .{ .pguid = &GUID_POV, .dwOfs = dijofsPov(2), .dwType = DIDFT_POV | DIDFT_OPTIONAL | DIDFT_ANYINSTANCE, .dwFlags = 0 },
    .{ .pguid = &GUID_POV, .dwOfs = dijofsPov(3), .dwType = DIDFT_POV | DIDFT_OPTIONAL | DIDFT_ANYINSTANCE, .dwFlags = 0 },
} ++ buttonFormats();

const data_format = DIDATAFORMAT{
    .dwSize = @sizeOf(DIDATAFORMAT),
    .dwObjSize = @sizeOf(DIOBJECTDATAFORMAT),
    .dwFlags = DIDFT_ABSAXIS,
    .dwDataSize = @sizeOf(DIJOYSTATE),
    .dwNumObjs = object_data_formats.len,
    .rgodf = &object_data_formats,
};

fn buttonFormats() [32]DIOBJECTDATAFORMAT {
    var result: [32]DIOBJECTDATAFORMAT = undefined;
    for (&result, 0..) |*format, i| {
        format.* = .{
            .pguid = null,
            .dwOfs = dijofsButton(i),
            .dwType = DIDFT_BUTTON | DIDFT_OPTIONAL | DIDFT_ANYINSTANCE,
            .dwFlags = 0,
        };
    }
    return result;
}
