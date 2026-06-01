const std = @import("std");
const x11 = @import("types.zig");
const xkb_unicode = @import("xkb_unicode.zig");

var keycodes: [349]c_int = @splat(-1);
var scancode_to_key: [256]c_int = @splat(-1);
var names: [349][5:0]u8 = @splat(@splat(0));

const KeyNameMapping = struct {
    key: c_int,
    name: [x11.XkbKeyNameLength]u8,
};

const xkb_key_name_map = [_]KeyNameMapping{
    .{ .key = 96, .name = "TLDE".* },
    .{ .key = 49, .name = "AE01".* },
    .{ .key = 50, .name = "AE02".* },
    .{ .key = 51, .name = "AE03".* },
    .{ .key = 52, .name = "AE04".* },
    .{ .key = 53, .name = "AE05".* },
    .{ .key = 54, .name = "AE06".* },
    .{ .key = 55, .name = "AE07".* },
    .{ .key = 56, .name = "AE08".* },
    .{ .key = 57, .name = "AE09".* },
    .{ .key = 48, .name = "AE10".* },
    .{ .key = 45, .name = "AE11".* },
    .{ .key = 61, .name = "AE12".* },
    .{ .key = 81, .name = "AD01".* },
    .{ .key = 87, .name = "AD02".* },
    .{ .key = 69, .name = "AD03".* },
    .{ .key = 82, .name = "AD04".* },
    .{ .key = 84, .name = "AD05".* },
    .{ .key = 89, .name = "AD06".* },
    .{ .key = 85, .name = "AD07".* },
    .{ .key = 73, .name = "AD08".* },
    .{ .key = 79, .name = "AD09".* },
    .{ .key = 80, .name = "AD10".* },
    .{ .key = 91, .name = "AD11".* },
    .{ .key = 93, .name = "AD12".* },
    .{ .key = 65, .name = "AC01".* },
    .{ .key = 83, .name = "AC02".* },
    .{ .key = 68, .name = "AC03".* },
    .{ .key = 70, .name = "AC04".* },
    .{ .key = 71, .name = "AC05".* },
    .{ .key = 72, .name = "AC06".* },
    .{ .key = 74, .name = "AC07".* },
    .{ .key = 75, .name = "AC08".* },
    .{ .key = 76, .name = "AC09".* },
    .{ .key = 59, .name = "AC10".* },
    .{ .key = 39, .name = "AC11".* },
    .{ .key = 90, .name = "AB01".* },
    .{ .key = 88, .name = "AB02".* },
    .{ .key = 67, .name = "AB03".* },
    .{ .key = 86, .name = "AB04".* },
    .{ .key = 66, .name = "AB05".* },
    .{ .key = 78, .name = "AB06".* },
    .{ .key = 77, .name = "AB07".* },
    .{ .key = 44, .name = "AB08".* },
    .{ .key = 46, .name = "AB09".* },
    .{ .key = 47, .name = "AB10".* },
    .{ .key = 92, .name = "BKSL".* },
    .{ .key = 161, .name = "LSGT".* },
    .{ .key = 32, .name = "SPCE".* },
    .{ .key = 256, .name = .{ 'E', 'S', 'C', 0 } },
    .{ .key = 257, .name = "RTRN".* },
    .{ .key = 258, .name = .{ 'T', 'A', 'B', 0 } },
    .{ .key = 259, .name = "BKSP".* },
    .{ .key = 260, .name = .{ 'I', 'N', 'S', 0 } },
    .{ .key = 261, .name = "DELE".* },
    .{ .key = 262, .name = "RGHT".* },
    .{ .key = 263, .name = "LEFT".* },
    .{ .key = 264, .name = "DOWN".* },
    .{ .key = 265, .name = .{ 'U', 'P', 0, 0 } },
    .{ .key = 266, .name = "PGUP".* },
    .{ .key = 267, .name = "PGDN".* },
    .{ .key = 268, .name = "HOME".* },
    .{ .key = 269, .name = .{ 'E', 'N', 'D', 0 } },
    .{ .key = 280, .name = "CAPS".* },
    .{ .key = 281, .name = "SCLK".* },
    .{ .key = 282, .name = "NMLK".* },
    .{ .key = 283, .name = "PRSC".* },
    .{ .key = 284, .name = "PAUS".* },
    .{ .key = 290, .name = "FK01".* },
    .{ .key = 291, .name = "FK02".* },
    .{ .key = 292, .name = "FK03".* },
    .{ .key = 293, .name = "FK04".* },
    .{ .key = 294, .name = "FK05".* },
    .{ .key = 295, .name = "FK06".* },
    .{ .key = 296, .name = "FK07".* },
    .{ .key = 297, .name = "FK08".* },
    .{ .key = 298, .name = "FK09".* },
    .{ .key = 299, .name = "FK10".* },
    .{ .key = 300, .name = "FK11".* },
    .{ .key = 301, .name = "FK12".* },
    .{ .key = 302, .name = "FK13".* },
    .{ .key = 303, .name = "FK14".* },
    .{ .key = 304, .name = "FK15".* },
    .{ .key = 305, .name = "FK16".* },
    .{ .key = 306, .name = "FK17".* },
    .{ .key = 307, .name = "FK18".* },
    .{ .key = 308, .name = "FK19".* },
    .{ .key = 309, .name = "FK20".* },
    .{ .key = 310, .name = "FK21".* },
    .{ .key = 311, .name = "FK22".* },
    .{ .key = 312, .name = "FK23".* },
    .{ .key = 313, .name = "FK24".* },
    .{ .key = 314, .name = "FK25".* },
    .{ .key = 320, .name = .{ 'K', 'P', '0', 0 } },
    .{ .key = 321, .name = .{ 'K', 'P', '1', 0 } },
    .{ .key = 322, .name = .{ 'K', 'P', '2', 0 } },
    .{ .key = 323, .name = .{ 'K', 'P', '3', 0 } },
    .{ .key = 324, .name = .{ 'K', 'P', '4', 0 } },
    .{ .key = 325, .name = .{ 'K', 'P', '5', 0 } },
    .{ .key = 326, .name = .{ 'K', 'P', '6', 0 } },
    .{ .key = 327, .name = .{ 'K', 'P', '7', 0 } },
    .{ .key = 328, .name = .{ 'K', 'P', '8', 0 } },
    .{ .key = 329, .name = .{ 'K', 'P', '9', 0 } },
    .{ .key = 330, .name = "KPDL".* },
    .{ .key = 331, .name = "KPDV".* },
    .{ .key = 332, .name = "KPMU".* },
    .{ .key = 333, .name = "KPSU".* },
    .{ .key = 334, .name = "KPAD".* },
    .{ .key = 335, .name = "KPEN".* },
    .{ .key = 336, .name = "KPEQ".* },
    .{ .key = 340, .name = "LFSH".* },
    .{ .key = 341, .name = "LCTL".* },
    .{ .key = 342, .name = "LALT".* },
    .{ .key = 343, .name = "LWIN".* },
    .{ .key = 344, .name = "RTSH".* },
    .{ .key = 345, .name = "RCTL".* },
    .{ .key = 346, .name = "RALT".* },
    .{ .key = 346, .name = "LVL3".* },
    .{ .key = 346, .name = "MDSW".* },
    .{ .key = 347, .name = "RWIN".* },
    .{ .key = 348, .name = "MENU".* },
};

pub fn rawMouseMotionSupported() bool {
    return x11.xi_available;
}

pub fn updateKeyNames() void {}

pub fn initKeyboard() void {
    const display = x11.display orelse return;
    const lib = &(x11.xlib orelse return);
    var major_opcode: c_int = 0;
    var event_base: c_int = 0;
    var error_base: c_int = 0;
    var major: c_int = 1;
    var minor: c_int = 0;

    x11.xkb_available = lib.XkbQueryExtension(display, &major_opcode, &event_base, &error_base, &major, &minor) != 0;
    if (!x11.xkb_available) return;

    x11.xkb_event_base = event_base;

    var supported: x11.Bool = 0;
    x11.detectable_autorepeat = lib.XkbSetDetectableAutoRepeat(display, 1, &supported) != 0 and supported != 0;

    var state: x11.XkbStateRec = undefined;
    if (lib.XkbGetState(display, x11.XkbUseCoreKbd, &state) == x11.Success) {
        x11.xkb_group = state.group;
    }

    _ = lib.XkbSelectEventDetails(
        display,
        x11.XkbUseCoreKbd,
        x11.XkbStateNotify,
        x11.XkbGroupStateMask,
        x11.XkbGroupStateMask,
    );
}

pub fn handleEvent(event: *const x11.XEvent) bool {
    if (!x11.xkb_available) return false;
    if (event.type != x11.xkb_event_base + x11.XkbEventCode) return false;

    const xkb_event: *const x11.XkbEvent = @ptrCast(@alignCast(event));
    if (xkb_event.state.xkb_type == x11.XkbStateNotify and
        (xkb_event.state.changed & x11.XkbGroupStateMask) != 0)
    {
        x11.xkb_group = @intCast(xkb_event.state.group);
    }

    return true;
}

pub fn getKeyScancode(key: c_int) c_int {
    initKeycodes();
    if (key < 0 or key >= keycodes.len) return -1;
    return keycodes[@intCast(key)];
}

pub fn translateScancode(scancode: c_uint) c_int {
    initKeycodes();
    if (scancode >= scancode_to_key.len) return 0;
    const key = scancode_to_key[@intCast(scancode)];
    return if (key >= 0) key else 0;
}

pub fn getScancodeName(scancode: c_int) ?[*:0]const u8 {
    const display = x11.display orelse return null;
    const xlib = &(x11.xlib orelse return null);
    initKeycodes();
    if (!x11.xkb_available) return null;
    if (scancode < 0 or scancode > 255) return null;
    const key = scancode_to_key[@intCast(scancode)];
    if (key <= 0 or key >= names.len) return null;

    const sym = xlib.XkbKeycodeToKeysym(display, @intCast(scancode), x11.xkb_group, 0);
    const codepoint = xkb_unicode.keySymToUnicode(sym) orelse return null;

    const index: usize = @intCast(key);
    @memset(&names[index], 0);
    const len = std.unicode.utf8Encode(codepoint, names[index][0..]) catch return null;
    names[index][len] = 0;
    return &names[index];
}

fn keyForName(name: [x11.XkbKeyNameLength]u8) c_int {
    for (xkb_key_name_map) |mapping| {
        if (std.mem.eql(u8, &name, &mapping.name)) return mapping.key;
    }
    return 0;
}

fn translateKeySym(keysym: x11.KeySym) c_int {
    return switch (keysym) {
        0x020 => 32,
        0x027 => 39,
        0x03c => 161,
        0x02c => 44,
        0x02d => 45,
        0x02e => 46,
        0x02f => 47,
        0x030...0x039 => @intCast(keysym),
        0x03b => 59,
        0x03d => 61,
        0x041...0x05a => @intCast(keysym),
        0x061...0x07a => @intCast(keysym - 32),
        0x05b => 91,
        0x05c => 92,
        0x05d => 93,
        0x060 => 96,
        0xff1b => 256,
        0xff0d => 257,
        0xff09 => 258,
        0xff08 => 259,
        0xff63 => 260,
        0xffff => 261,
        0xff53 => 262,
        0xff51 => 263,
        0xff54 => 264,
        0xff52 => 265,
        0xff55 => 266,
        0xff56 => 267,
        0xff50 => 268,
        0xff57 => 269,
        0xffe5 => 280,
        0xff14 => 281,
        0xff7f => 282,
        0xff61 => 283,
        0xff13 => 284,
        0xffbe...0xffd5 => @intCast(290 + keysym - 0xffbe),
        0xffb0...0xffb9 => @intCast(320 + keysym - 0xffb0),
        0xffae => 330,
        0xffaf => 331,
        0xffaa => 332,
        0xffad => 333,
        0xffab => 334,
        0xff8d => 335,
        0xffbd => 336,
        0xffe1 => 340,
        0xffe3 => 341,
        0xffe9 => 342,
        0xffeb => 343,
        0xffe2 => 344,
        0xffe4 => 345,
        0xffea => 346,
        0xffec => 347,
        0xff67 => 348,
        else => 0,
    };
}

fn translateKeySyms(keysyms: []const x11.KeySym) c_int {
    if (keysyms.len > 1) {
        switch (keysyms[1]) {
            0xffb0...0xffb9 => return @intCast(320 + keysyms[1] - 0xffb0),
            0xffac, 0xffae => return 330,
            0xffbd => return 336,
            0xff8d => return 335,
            else => {},
        }
    }

    return switch (keysyms[0]) {
        0xff1b => 256,
        0xff09 => 258,
        0xffe1 => 340,
        0xffe2 => 344,
        0xffe3 => 341,
        0xffe4 => 345,
        0xffe7, 0xffe9 => 342,
        0xff7e, 0xfe03, 0xffe8, 0xffea => 346,
        0xffeb => 343,
        0xffec => 347,
        0xff67 => 348,
        0xff7f => 282,
        0xffe5 => 280,
        0xff61 => 283,
        0xff14 => 281,
        0xff13 => 284,
        0xffff => 261,
        0xff08 => 259,
        0xff0d => 257,
        0xff50 => 268,
        0xff57 => 269,
        0xff55 => 266,
        0xff56 => 267,
        0xff63 => 260,
        0xff51 => 263,
        0xff53 => 262,
        0xff54 => 264,
        0xff52 => 265,
        0xffbe...0xffd5 => @intCast(290 + keysyms[0] - 0xffbe),
        0xffaf => 331,
        0xffaa => 332,
        0xffad => 333,
        0xffab => 334,
        0xff9e => 320,
        0xff9c => 321,
        0xff99 => 322,
        0xff9b => 323,
        0xff96 => 324,
        0xff98 => 326,
        0xff95 => 327,
        0xff97 => 328,
        0xff9a => 329,
        0xff9f => 330,
        0xffbd => 336,
        0xff8d => 335,
        else => translateKeySym(keysyms[0]),
    };
}

pub fn initKeycodes() void {
    const display = x11.display orelse return;
    const xlib = &(x11.xlib orelse return);
    if (keycodes[32] != -1) return;
    for (&keycodes) |*keycode| keycode.* = -1;
    for (&scancode_to_key) |*key| key.* = -1;

    var min_scancode: c_int = 0;
    var max_scancode: c_int = 0;

    if (x11.xkb_available) {
        if (xlib.XkbGetMap(display, 0, x11.XkbUseCoreKbd)) |desc| {
            defer xlib.XkbFreeKeyboard(desc, 0, 1);
            _ = xlib.XkbGetNames(display, x11.XkbKeyNamesMask | x11.XkbKeyAliasesMask, desc);

            min_scancode = desc.min_key_code;
            max_scancode = desc.max_key_code;

            if (desc.names) |xkb_names| {
                var scancode = min_scancode;
                while (scancode <= max_scancode and scancode <= 255) : (scancode += 1) {
                    if (scancode < 0) continue;
                    const name = xkb_names.keys[@intCast(scancode)].name;
                    var key = keyForName(name);

                    var i: usize = 0;
                    while (key == 0 and i < xkb_names.num_key_aliases) : (i += 1) {
                        const alias = xkb_names.key_aliases[i];
                        if (!std.mem.eql(u8, &alias.real, &name)) continue;
                        key = keyForName(alias.alias);
                    }

                    scancode_to_key[@intCast(scancode)] = key;
                }

                xlib.XkbFreeNames(desc, x11.XkbKeyNamesMask, 1);
            }
        }
    } else {
        _ = xlib.XDisplayKeycodes(display, &min_scancode, &max_scancode);
    }

    if (min_scancode < 0) min_scancode = 0;
    if (max_scancode > 255) max_scancode = 255;
    if (max_scancode < min_scancode) return;

    var width: c_int = 0;
    const keysyms = xlib.XGetKeyboardMapping(
        display,
        @intCast(min_scancode),
        max_scancode - min_scancode + 1,
        &width,
    ) orelse return;
    defer _ = xlib.XFree(@ptrCast(keysyms));
    if (width <= 0) return;

    var scancode = min_scancode;
    while (scancode <= max_scancode) : (scancode += 1) {
        const base: usize = @intCast((scancode - min_scancode) * width);
        const key = if (scancode_to_key[@intCast(scancode)] < 0)
            translateKeySyms(keysyms[base .. base + @as(usize, @intCast(width))])
        else
            scancode_to_key[@intCast(scancode)];

        scancode_to_key[@intCast(scancode)] = key;
        if (key > 0 and key < keycodes.len) {
            keycodes[@intCast(key)] = scancode;
        }
    }
}
