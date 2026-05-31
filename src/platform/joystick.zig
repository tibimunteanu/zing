const std = @import("std");

const Errors = @import("errors.zig");
const Input = @import("input.zig");

const max_joysticks = 16;
const max_mappings = 512;

var callback: ?Callback = null;
var user_pointers: [max_joysticks]?*anyopaque = @splat(null);
var mappings: [max_mappings]Mapping = undefined;
var mapping_count: usize = 0;

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
        _ = self;
        return false;
    }

    pub fn getAxes(self: Joystick) ![]const f32 {
        _ = self;
        return &.{};
    }

    pub fn getButtons(self: Joystick) ![]const Input.Action {
        _ = self;
        return &.{};
    }

    pub fn getHats(self: Joystick) ![]const Hat {
        _ = self;
        return &.{};
    }

    pub fn getName(self: Joystick) ![:0]const u8 {
        _ = self;
        return error.NotConnected;
    }

    pub fn getGuid(self: Joystick) ![:0]const u8 {
        _ = self;
        return error.NotConnected;
    }

    pub fn setUserPointer(self: Joystick, pointer: ?*anyopaque) !void {
        user_pointers[@intFromEnum(self.id)] = pointer;
        return;
    }

    pub fn getUserPointer(self: Joystick) !?*anyopaque {
        return user_pointers[@intFromEnum(self.id)];
    }

    pub fn isGamepad(self: Joystick) !bool {
        _ = self;
        return false;
    }

    pub fn getGamepadName(self: Joystick) ![:0]const u8 {
        _ = self;
        return error.NotConnected;
    }

    pub fn getGamepadState(self: Joystick) !GamepadState {
        _ = self;
        return error.NotConnected;
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

pub fn initSystem() !void {
    return;
}

pub fn deinitSystem() void {}

pub fn setCallback(new_callback: ?Callback) !?Callback {
    const previous = callback;
    callback = new_callback;
    return previous;
}

pub fn updateGamepadMappings(mapping_string: [:0]const u8) !void {
    var rest: []const u8 = mapping_string;
    while (rest.len > 0) {
        const line_end = std.mem.indexOfAny(u8, rest, "\r\n") orelse rest.len;
        const line = rest[0..line_end];
        if (line.len > 0 and line.len < 1024 and isHex(line[0])) {
            if (parseMapping(line)) |mapping| {
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
        }

        rest = rest[line_end..];
        while (rest.len > 0 and (rest[0] == '\r' or rest[0] == '\n')) rest = rest[1..];
    }
}

pub fn gamepadMappingCount() usize {
    return mapping_count;
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
    axis_scale: i8 = 0,
    axis_offset: i8 = 0,
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

    const name = parts.next() orelse return null;
    if (name.len >= mapping.name.len) return null;
    @memcpy(mapping.name[0..name.len], name);

    while (parts.next()) |field| {
        if (field.len == 0) continue;
        const colon = std.mem.indexOfScalar(u8, field, ':') orelse continue;
        const key = field[0..colon];
        const value = field[colon + 1 ..];

        if (std.mem.eql(u8, key, "platform")) {
            if (!std.mem.eql(u8, value, "Mac OS X")) return null;
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
    var minimum: i8 = -1;
    var maximum: i8 = 1;
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
        if (hat_start == index or index >= value.len) return null;
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
        element.axis_scale = @intCast(@divTrunc(2, maximum - minimum));
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

fn isHex(char: u8) bool {
    return (char >= '0' and char <= '9') or
        (char >= 'a' and char <= 'f') or
        (char >= 'A' and char <= 'F');
}

fn lowercaseAscii(value: []u8) void {
    for (value) |*char| char.* = std.ascii.toLower(char.*);
}
