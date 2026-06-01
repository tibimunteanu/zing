const std = @import("std");
const builtin = @import("builtin");

const Errors = @import("errors.zig");
const Input = @import("input.zig");
const GamepadMappings = @import("gamepad_mappings");
const platform = @import("platform.zig");

const max_joysticks = 16;
const max_axes = 64;
const max_buttons = 128;
const max_hats = 16;
const max_mappings = 1024;

const poll_presence: u8 = 0;
const poll_axes: u8 = 1;
const poll_buttons: u8 = 2;
const poll_all: u8 = 3;

var initialized = false;
var callback: ?Callback = null;
var devices: [max_joysticks]Device = @splat(.{});
var mappings: [max_mappings]Mapping = undefined;
var mapping_count: usize = 0;
var default_mappings_loaded = false;

const Backend = platform.Joystick;

pub const Joystick = struct {
    id: Id,

    pub const Id = enum(u8) {
        one,
        two,
        three,
        four,
        five,
        six,
        seven,
        eight,
        nine,
        ten,
        eleven,
        twelve,
        thirteen,
        fourteen,
        fifteen,
        sixteen,
    };

    pub fn present(self: Joystick) !bool {
        try ensureInitialized();
        const index = @intFromEnum(self.id);
        if (!devices[index].connected) return false;
        return try Backend.poll(index, poll_presence);
    }

    pub fn getAxes(self: Joystick) ![]const f32 {
        try ensureInitialized();
        const index = @intFromEnum(self.id);
        if (!devices[index].connected) return &.{};
        if (!try Backend.poll(index, poll_axes)) return &.{};
        return devices[index].axes[0..devices[index].axis_count];
    }

    pub fn getButtons(self: Joystick) ![]const Input.Action {
        try ensureInitialized();
        const index = @intFromEnum(self.id);
        if (!devices[index].connected) return &.{};
        if (!try Backend.poll(index, poll_buttons)) return &.{};
        const device = &devices[index];
        return device.buttons[0 .. device.button_count + device.hat_count * 4];
    }

    pub fn getHats(self: Joystick) ![]const Hat {
        try ensureInitialized();
        const index = @intFromEnum(self.id);
        if (!devices[index].connected) return &.{};
        if (!try Backend.poll(index, poll_buttons)) return &.{};
        return devices[index].hats[0..devices[index].hat_count];
    }

    pub fn getName(self: Joystick) ![:0]const u8 {
        try ensureInitialized();
        const index = @intFromEnum(self.id);
        if (!devices[index].connected) return error.NotConnected;
        if (!try Backend.poll(index, poll_presence)) return error.NotConnected;
        return std.mem.sliceTo(&devices[index].name, 0);
    }

    pub fn getGuid(self: Joystick) ![:0]const u8 {
        try ensureInitialized();
        const index = @intFromEnum(self.id);
        if (!devices[index].connected) return error.NotConnected;
        if (!try Backend.poll(index, poll_presence)) return error.NotConnected;
        return std.mem.sliceTo(&devices[index].guid, 0);
    }

    pub fn setUserPointer(self: Joystick, pointer: ?*anyopaque) !void {
        devices[@intFromEnum(self.id)].user_pointer = pointer;
    }

    pub fn getUserPointer(self: Joystick) !?*anyopaque {
        return devices[@intFromEnum(self.id)].user_pointer;
    }

    pub fn isGamepad(self: Joystick) !bool {
        try ensureInitialized();
        const index = @intFromEnum(self.id);
        if (!devices[index].connected) return false;
        if (!try Backend.poll(index, poll_presence)) return false;
        devices[index].mapping = findValidMapping(&devices[index]);
        return devices[index].mapping != null;
    }

    pub fn getGamepadName(self: Joystick) ![:0]const u8 {
        try ensureInitialized();
        const index = @intFromEnum(self.id);
        if (!devices[index].connected) return error.NotConnected;
        if (!try Backend.poll(index, poll_presence)) return error.NotConnected;
        const mapping_index = devices[index].mapping orelse return error.NotGamepad;
        return std.mem.sliceTo(&mappings[mapping_index].name, 0);
    }

    pub fn getGamepadState(self: Joystick) !GamepadState {
        try ensureInitialized();
        const index = @intFromEnum(self.id);
        if (!devices[index].connected) return error.NotConnected;
        if (!try Backend.poll(index, poll_all)) return error.NotConnected;

        const device = &devices[index];
        const mapping_index = device.mapping orelse return error.NotGamepad;
        const mapping = &mappings[mapping_index];
        var state = GamepadState{
            .buttons = @splat(.release),
            .axes = @splat(0),
        };

        for (mapping.buttons, 0..) |element, i| {
            state.buttons[i] = buttonState(device, element);
        }

        for (mapping.axes, 0..) |element, i| {
            state.axes[i] = axisState(device, element);
        }

        return state;
    }
};

pub const Hat = packed struct(u8) {
    up: bool = false,
    right: bool = false,
    down: bool = false,
    left: bool = false,
    _reserved: u4 = 0,
};

pub const Event = enum {
    connected,
    disconnected,
};

pub const GamepadAxis = enum(u8) {
    left_x,
    left_y,
    right_x,
    right_y,
    left_trigger,
    right_trigger,
};

pub const GamepadButton = enum(u8) {
    a,
    b,
    x,
    y,
    left_bumper,
    right_bumper,
    back,
    start,
    guide,
    left_thumb,
    right_thumb,
    dpad_up,
    dpad_right,
    dpad_down,
    dpad_left,
};

pub const GamepadState = struct {
    buttons: [15]Input.Action,
    axes: [6]f32,
};

pub const Callback = *const fn (Joystick, Event) void;

const Device = struct {
    allocated: bool = false,
    connected: bool = false,
    axes: [max_axes]f32 = @splat(0),
    buttons: [max_buttons + max_hats * 4]Input.Action = @splat(.release),
    hats: [max_hats]Hat = @splat(.{}),
    axis_count: usize = 0,
    button_count: usize = 0,
    hat_count: usize = 0,
    name: [128:0]u8 = @splat(0),
    guid: [33:0]u8 = @splat(0),
    mapping: ?usize = null,
    user_pointer: ?*anyopaque = null,
};

pub fn initSystem() !void {
    if (initialized) return;
    try loadDefaultMappings();
    try Backend.init(.{
        .connect = inputConnect,
        .disconnect = inputDisconnect,
        .axis = inputAxis,
        .button = inputButton,
        .hat = inputHat,
    });
    initialized = true;
}

pub fn deinitSystem() void {
    if (initialized) Backend.deinit();
    initialized = false;
    callback = null;
    devices = @splat(.{});
}

pub fn setCallback(new_callback: ?Callback) !?Callback {
    try ensureInitialized();
    const previous = callback;
    callback = new_callback;

    if (new_callback) |cb| {
        for (0..max_joysticks) |index| {
            _ = Backend.poll(index, poll_presence) catch false;
            if (devices[index].connected) cb(.{ .id = @enumFromInt(index) }, .connected);
        }
    }

    return previous;
}

pub fn updateGamepadMappings(mapping_string: [:0]const u8) !void {
    try ensureInitialized();
    try updateGamepadMappingsBytes(mapping_string);
    refreshMappings();
}

pub fn gamepadMappingCount() usize {
    return mapping_count;
}

pub const testing = if (builtin.is_test) struct {
    pub fn connect(index: usize, name: []const u8, guid: []const u8, axis_count: usize, button_count: usize, hat_count: usize) void {
        inputConnect(index, name, guid, axis_count, button_count, hat_count);
    }

    pub fn disconnect(index: usize) void {
        inputDisconnect(index);
    }

    pub fn axis(index: usize, axis_index: usize, value: f32) void {
        inputAxis(index, axis_index, value);
    }

    pub fn button(index: usize, button_index: usize, pressed: bool) void {
        inputButton(index, button_index, pressed);
    }

    pub fn hat(index: usize, hat_index: usize, value: u8) void {
        inputHat(index, hat_index, value);
    }

    pub fn isGamepad(index: usize) bool {
        if (index >= devices.len) return false;
        devices[index].mapping = findValidMapping(&devices[index]);
        return devices[index].mapping != null;
    }

    pub fn gamepadName(index: usize) ?[:0]const u8 {
        if (!isGamepad(index)) return null;
        return std.mem.sliceTo(&mappings[devices[index].mapping.?].name, 0);
    }

    pub fn gamepadState(index: usize) ?GamepadState {
        if (index >= devices.len) return null;
        const device = &devices[index];
        const mapping_index = device.mapping orelse return null;
        const mapping = &mappings[mapping_index];
        var state = GamepadState{
            .buttons = @splat(.release),
            .axes = @splat(0),
        };
        for (mapping.buttons, 0..) |element, i| state.buttons[i] = buttonState(device, element);
        for (mapping.axes, 0..) |element, i| state.axes[i] = axisState(device, element);
        return state;
    }
} else struct {};

fn ensureInitialized() !void {
    if (!initialized) try initSystem();
}

fn loadDefaultMappings() !void {
    if (default_mappings_loaded) return;
    default_mappings_loaded = true;

    var rest: []const u8 = GamepadMappings.text;
    while (std.mem.indexOfScalar(u8, rest, '"')) |start| {
        rest = rest[start + 1 ..];
        const end = std.mem.indexOfScalar(u8, rest, '"') orelse break;
        const line = rest[0..end];
        try addMappingLine(line);
        rest = rest[end + 1 ..];
    }
}

fn updateGamepadMappingsBytes(mapping_string: []const u8) !void {
    var rest: []const u8 = mapping_string;
    while (rest.len > 0) {
        const line_end = std.mem.indexOfAny(u8, rest, "\r\n") orelse rest.len;
        const line = rest[0..line_end];
        try addMappingLine(line);

        rest = rest[line_end..];
        while (rest.len > 0 and (rest[0] == '\r' or rest[0] == '\n')) rest = rest[1..];
    }
}

fn addMappingLine(line: []const u8) !void {
    if (line.len == 0 or line.len >= 1024 or !isHex(line[0])) return;
    const mapping = parseMapping(line) orelse return;

    if (findMapping(mapping.guid[0..32])) |index| {
        mappings[index] = mapping;
    } else if (mapping_count < mappings.len) {
        mappings[mapping_count] = mapping;
        mapping_count += 1;
    } else {
        Errors.report(.out_of_memory, "gamepad mapping table is full", .{});
        return error.OutOfMemory;
    }
}

fn refreshMappings() void {
    for (&devices) |*device| {
        if (device.connected) device.mapping = findValidMapping(device);
    }
}

const MapElementType = enum(u8) {
    none,
    axis,
    button,
    hat_bit,
};

const MapElement = struct {
    kind: MapElementType = .none,
    index: u8 = 0,
    axis_scale: f32 = 0,
    axis_offset: f32 = 0,
};

const Mapping = struct {
    name: [128:0]u8 = @splat(0),
    guid: [33:0]u8 = @splat(0),
    buttons: [15]MapElement = @splat(.{}),
    axes: [6]MapElement = @splat(.{}),
};

fn parseMapping(line: []const u8) ?Mapping {
    var mapping = Mapping{};
    var parts = std.mem.splitScalar(u8, line, ',');

    const guid = parts.next() orelse return null;
    if (guid.len != 32) return null;
    for (guid) |char| if (!isHex(char)) return null;
    @memcpy(mapping.guid[0..32], guid);
    lowercaseAscii(mapping.guid[0..32]);
    Backend.updateGamepadGuid(&mapping.guid);
    lowercaseAscii(mapping.guid[0..32]);

    const name = parts.next() orelse return null;
    if (name.len >= mapping.name.len) return null;
    @memcpy(mapping.name[0..name.len], name);

    while (parts.next()) |field| {
        if (field.len == 0) continue;
        if (field[0] == '+' or field[0] == '-') return null;
        const colon = std.mem.indexOfScalar(u8, field, ':') orelse continue;
        const key = field[0..colon];
        const value = field[colon + 1 ..];

        if (std.mem.eql(u8, key, "platform")) {
            if (!mappingPlatformMatches(value)) return null;
            continue;
        }

        const target = mappingElementPtr(&mapping, key) orelse continue;
        target.* = parseElement(value) orelse return null;
    }

    return mapping;
}

fn mappingElementPtr(mapping: *Mapping, key: []const u8) ?*MapElement {
    if (std.mem.eql(u8, key, "a")) return &mapping.buttons[@intFromEnum(GamepadButton.a)];
    if (std.mem.eql(u8, key, "b")) return &mapping.buttons[@intFromEnum(GamepadButton.b)];
    if (std.mem.eql(u8, key, "x")) return &mapping.buttons[@intFromEnum(GamepadButton.x)];
    if (std.mem.eql(u8, key, "y")) return &mapping.buttons[@intFromEnum(GamepadButton.y)];
    if (std.mem.eql(u8, key, "back")) return &mapping.buttons[@intFromEnum(GamepadButton.back)];
    if (std.mem.eql(u8, key, "start")) return &mapping.buttons[@intFromEnum(GamepadButton.start)];
    if (std.mem.eql(u8, key, "guide")) return &mapping.buttons[@intFromEnum(GamepadButton.guide)];
    if (std.mem.eql(u8, key, "leftshoulder")) return &mapping.buttons[@intFromEnum(GamepadButton.left_bumper)];
    if (std.mem.eql(u8, key, "rightshoulder")) return &mapping.buttons[@intFromEnum(GamepadButton.right_bumper)];
    if (std.mem.eql(u8, key, "leftstick")) return &mapping.buttons[@intFromEnum(GamepadButton.left_thumb)];
    if (std.mem.eql(u8, key, "rightstick")) return &mapping.buttons[@intFromEnum(GamepadButton.right_thumb)];
    if (std.mem.eql(u8, key, "dpup")) return &mapping.buttons[@intFromEnum(GamepadButton.dpad_up)];
    if (std.mem.eql(u8, key, "dpright")) return &mapping.buttons[@intFromEnum(GamepadButton.dpad_right)];
    if (std.mem.eql(u8, key, "dpdown")) return &mapping.buttons[@intFromEnum(GamepadButton.dpad_down)];
    if (std.mem.eql(u8, key, "dpleft")) return &mapping.buttons[@intFromEnum(GamepadButton.dpad_left)];
    if (std.mem.eql(u8, key, "lefttrigger")) return &mapping.axes[@intFromEnum(GamepadAxis.left_trigger)];
    if (std.mem.eql(u8, key, "righttrigger")) return &mapping.axes[@intFromEnum(GamepadAxis.right_trigger)];
    if (std.mem.eql(u8, key, "leftx")) return &mapping.axes[@intFromEnum(GamepadAxis.left_x)];
    if (std.mem.eql(u8, key, "lefty")) return &mapping.axes[@intFromEnum(GamepadAxis.left_y)];
    if (std.mem.eql(u8, key, "rightx")) return &mapping.axes[@intFromEnum(GamepadAxis.right_x)];
    if (std.mem.eql(u8, key, "righty")) return &mapping.axes[@intFromEnum(GamepadAxis.right_y)];
    return null;
}

fn parseElement(value: []const u8) ?MapElement {
    if (value.len == 0) return null;
    var index: usize = 0;
    var minimum: f32 = -1;
    var maximum: f32 = 1;
    if (value[index] == '+') {
        minimum = 0;
        index += 1;
    } else if (value[index] == '-') {
        maximum = 0;
        index += 1;
    }
    if (index >= value.len) return null;

    var element = MapElement{};
    switch (value[index]) {
        'a' => element.kind = .axis,
        'b' => element.kind = .button,
        'h' => element.kind = .hat_bit,
        else => return null,
    }
    index += 1;

    if (element.kind == .hat_bit) {
        const hat_start = index;
        while (index < value.len and std.ascii.isDigit(value[index])) index += 1;
        if (hat_start == index or index >= value.len or value[index] != '.') return null;
        const hat = std.fmt.parseUnsigned(u8, value[hat_start..index], 10) catch return null;
        index += 1;
        const bit_start = index;
        while (index < value.len and std.ascii.isDigit(value[index])) index += 1;
        if (bit_start == index) return null;
        const bit = std.fmt.parseUnsigned(u8, value[bit_start..index], 10) catch return null;
        element.index = (hat << 4) | bit;
        return element;
    }

    const source_start = index;
    while (index < value.len and std.ascii.isDigit(value[index])) index += 1;
    if (source_start == index) return null;
    element.index = std.fmt.parseUnsigned(u8, value[source_start..index], 10) catch return null;

    if (element.kind == .axis) {
        element.axis_scale = 2.0 / (maximum - minimum);
        element.axis_offset = -(maximum + minimum);
        if (index < value.len and value[index] == '~') {
            element.axis_scale = -element.axis_scale;
            element.axis_offset = -element.axis_offset;
        }
    }

    return element;
}

fn findMapping(guid: []const u8) ?usize {
    for (mappings[0..mapping_count], 0..) |mapping, i| {
        if (std.mem.eql(u8, mapping.guid[0..32], guid)) return i;
    }
    return null;
}

fn findValidMapping(device: *const Device) ?usize {
    const mapping_index = findMapping(std.mem.sliceTo(&device.guid, 0)) orelse return null;
    const mapping = &mappings[mapping_index];

    for (mapping.buttons) |element| {
        if (!isValidElementForDevice(element, device)) return null;
    }

    for (mapping.axes) |element| {
        if (!isValidElementForDevice(element, device)) return null;
    }

    return mapping_index;
}

fn isValidElementForDevice(element: MapElement, device: *const Device) bool {
    return switch (element.kind) {
        .none => true,
        .axis => element.index < device.axis_count,
        .button => element.index < device.button_count,
        .hat_bit => (element.index >> 4) < device.hat_count,
    };
}

fn buttonState(device: *const Device, element: MapElement) Input.Action {
    return switch (element.kind) {
        .none => .release,
        .axis => {
            const value = device.axes[element.index] * element.axis_scale + element.axis_offset;
            if (element.axis_offset < 0 or (element.axis_offset == 0 and element.axis_scale > 0)) {
                return if (value >= 0) .press else .release;
            }
            return if (value <= 0) .press else .release;
        },
        .button => device.buttons[element.index],
        .hat_bit => if ((hatByte(device.hats[element.index >> 4]) & (element.index & 0x0f)) != 0) .press else .release,
    };
}

fn axisState(device: *const Device, element: MapElement) f32 {
    return switch (element.kind) {
        .none => 0,
        .axis => std.math.clamp(device.axes[element.index] * element.axis_scale + element.axis_offset, -1, 1),
        .button => if (device.buttons[element.index] == .press) 1 else -1,
        .hat_bit => if ((hatByte(device.hats[element.index >> 4]) & (element.index & 0x0f)) != 0) 1 else -1,
    };
}

fn inputConnect(index: usize, name: []const u8, guid: []const u8, axis_count: usize, button_count: usize, hat_count: usize) void {
    if (index >= max_joysticks) return;
    const device = &devices[index];
    const preserved_user_pointer = device.user_pointer;
    device.* = .{};
    device.allocated = true;
    device.connected = true;
    device.axis_count = @min(axis_count, max_axes);
    device.button_count = @min(button_count, max_buttons);
    device.hat_count = @min(hat_count, max_hats);
    device.user_pointer = preserved_user_pointer;

    const name_len = @min(name.len, device.name.len - 1);
    @memcpy(device.name[0..name_len], name[0..name_len]);
    const guid_len = @min(guid.len, 32);
    @memcpy(device.guid[0..guid_len], guid[0..guid_len]);
    lowercaseAscii(device.guid[0..32]);
    device.mapping = findValidMapping(device);

    if (callback) |cb| cb(.{ .id = @enumFromInt(index) }, .connected);
}

fn inputDisconnect(index: usize) void {
    if (index >= max_joysticks) return;
    const user_pointer = devices[index].user_pointer;
    const was_connected = devices[index].connected;
    devices[index] = .{ .user_pointer = user_pointer };
    if (was_connected) {
        if (callback) |cb| cb(.{ .id = @enumFromInt(index) }, .disconnected);
    }
}

fn inputAxis(index: usize, axis: usize, value: f32) void {
    if (index >= max_joysticks or axis >= devices[index].axis_count) return;
    devices[index].axes[axis] = value;
}

fn inputButton(index: usize, button: usize, pressed: bool) void {
    if (index >= max_joysticks or button >= devices[index].button_count) return;
    devices[index].buttons[button] = if (pressed) .press else .release;
}

fn inputHat(index: usize, hat: usize, value: u8) void {
    if (index >= max_joysticks or hat >= devices[index].hat_count) return;
    const normalized = normalizeHat(value);
    const base = devices[index].button_count + hat * 4;
    devices[index].buttons[base + 0] = if ((normalized & 0x01) != 0) .press else .release;
    devices[index].buttons[base + 1] = if ((normalized & 0x02) != 0) .press else .release;
    devices[index].buttons[base + 2] = if ((normalized & 0x04) != 0) .press else .release;
    devices[index].buttons[base + 3] = if ((normalized & 0x08) != 0) .press else .release;
    devices[index].hats[hat] = @bitCast(normalized);
}

fn normalizeHat(value: u8) u8 {
    var result = value & 0x0f;
    if ((result & 0x02) != 0 and (result & 0x08) != 0) result &= ~@as(u8, 0x02 | 0x08);
    if ((result & 0x01) != 0 and (result & 0x04) != 0) result &= ~@as(u8, 0x01 | 0x04);
    return result;
}

fn hatByte(hat: Hat) u8 {
    return @bitCast(hat);
}

fn mappingPlatformMatches(value: []const u8) bool {
    return switch (builtin.os.tag) {
        .macos => std.mem.eql(u8, value, "Mac OS X"),
        .windows => std.mem.eql(u8, value, "Windows"),
        .linux => std.mem.eql(u8, value, "Linux"),
        else => false,
    };
}

fn isHex(char: u8) bool {
    return (char >= '0' and char <= '9') or
        (char >= 'a' and char <= 'f') or
        (char >= 'A' and char <= 'F');
}

fn lowercaseAscii(value: []u8) void {
    for (value) |*char| char.* = std.ascii.toLower(char.*);
}
