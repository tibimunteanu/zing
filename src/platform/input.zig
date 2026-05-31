const std = @import("std");
const Errors = @import("errors.zig");
const platform = @import("platform.zig");

pub const Action = enum {
    release,
    press,
    repeat,
};

pub const Key = enum(u16) {
    unknown = 0,
    space = 32,
    apostrophe = 39,
    comma = 44,
    minus = 45,
    period = 46,
    slash = 47,
    zero = 48,
    one = 49,
    two = 50,
    three = 51,
    four = 52,
    five = 53,
    six = 54,
    seven = 55,
    eight = 56,
    nine = 57,
    semicolon = 59,
    equal = 61,
    a = 65,
    b = 66,
    c = 67,
    d = 68,
    e = 69,
    f = 70,
    g = 71,
    h = 72,
    i = 73,
    j = 74,
    k = 75,
    l = 76,
    m = 77,
    n = 78,
    o = 79,
    p = 80,
    q = 81,
    r = 82,
    s = 83,
    t = 84,
    u = 85,
    v = 86,
    w = 87,
    x = 88,
    y = 89,
    z = 90,
    left_bracket = 91,
    backslash = 92,
    right_bracket = 93,
    grave_accent = 96,
    world_1 = 161,
    world_2 = 162,
    escape = 256,
    enter = 257,
    tab = 258,
    backspace = 259,
    insert = 260,
    delete = 261,
    right = 262,
    left = 263,
    down = 264,
    up = 265,
    page_up = 266,
    page_down = 267,
    home = 268,
    end = 269,
    caps_lock = 280,
    scroll_lock = 281,
    num_lock = 282,
    print_screen = 283,
    pause = 284,
    f1 = 290,
    f2 = 291,
    f3 = 292,
    f4 = 293,
    f5 = 294,
    f6 = 295,
    f7 = 296,
    f8 = 297,
    f9 = 298,
    f10 = 299,
    f11 = 300,
    f12 = 301,
    f13 = 302,
    f14 = 303,
    f15 = 304,
    f16 = 305,
    f17 = 306,
    f18 = 307,
    f19 = 308,
    f20 = 309,
    f21 = 310,
    f22 = 311,
    f23 = 312,
    f24 = 313,
    f25 = 314,
    kp_0 = 320,
    kp_1 = 321,
    kp_2 = 322,
    kp_3 = 323,
    kp_4 = 324,
    kp_5 = 325,
    kp_6 = 326,
    kp_7 = 327,
    kp_8 = 328,
    kp_9 = 329,
    kp_decimal = 330,
    kp_divide = 331,
    kp_multiply = 332,
    kp_subtract = 333,
    kp_add = 334,
    kp_enter = 335,
    kp_equal = 336,
    left_shift = 340,
    left_control = 341,
    left_alt = 342,
    left_super = 343,
    right_shift = 344,
    right_control = 345,
    right_alt = 346,
    right_super = 347,
    menu = 348,
};

pub const key_count = @intFromEnum(Key.menu) + 1;

pub const MouseButton = enum {
    one,
    two,
    three,
    four,
    five,
    six,
    seven,
    eight,
    left,
    right,
    middle,
};

pub const mouse_button_count = 8;

pub fn mouseButtonIndex(button: MouseButton) usize {
    return switch (button) {
        .one, .left => 0,
        .two, .right => 1,
        .three, .middle => 2,
        .four => 3,
        .five => 4,
        .six => 5,
        .seven => 6,
        .eight => 7,
    };
}

pub fn mouseButtonFromIndex(index: usize) MouseButton {
    return switch (index) {
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

pub const CursorMode = enum {
    normal,
    hidden,
    disabled,
    captured,
};

pub const StickyMode = enum {
    disabled,
    enabled,
};

pub const LockKeyModsMode = enum {
    disabled,
    enabled,
};

pub const RawMouseMotionMode = enum {
    disabled,
    enabled,
};

pub const Modifiers = packed struct(u8) {
    shift: bool = false,
    control: bool = false,
    alt: bool = false,
    super: bool = false,
    caps_lock: bool = false,
    num_lock: bool = false,
    _reserved: u2 = 0,
};

pub const CursorPos = struct {
    x: f64,
    y: f64,
};

pub const ScrollOffset = struct {
    x: f64,
    y: f64,
};

pub fn initSystem() !void {
    return;
}

pub fn deinitSystem() void {}

pub fn rawMouseMotionSupported() !bool {
    return platform.Input.rawMouseMotionSupported();
}

pub fn getKeyScancode(key: Key) !i32 {
    const scancode = platform.Input.getKeyScancode(@intFromEnum(key));
    if (scancode < 0) return error.InvalidValue;
    return scancode;
}

pub fn getKeyName(key: Key, scancode: ?i32) !?[:0]const u8 {
    const native_scancode = if (scancode) |value| value else try getKeyScancode(key);
    if (native_scancode < 0 or native_scancode > 0xff) {
        Errors.report(.invalid_value, "invalid scancode {d}", .{native_scancode});
        return error.InvalidValue;
    }

    const name = platform.Input.getScancodeName(native_scancode) orelse return null;
    return std.mem.span(name);
}
