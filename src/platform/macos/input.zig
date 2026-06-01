pub fn getKeyScancode(key: c_int) c_int {
    return switch (key) {
        48 => 0x1d,
        49 => 0x12,
        50 => 0x13,
        51 => 0x14,
        52 => 0x15,
        53 => 0x17,
        54 => 0x16,
        55 => 0x1a,
        56 => 0x1c,
        57 => 0x19,
        65 => 0x00,
        66 => 0x0b,
        67 => 0x08,
        68 => 0x02,
        69 => 0x0e,
        70 => 0x03,
        71 => 0x05,
        72 => 0x04,
        73 => 0x22,
        74 => 0x26,
        75 => 0x28,
        76 => 0x25,
        77 => 0x2e,
        78 => 0x2d,
        79 => 0x1f,
        80 => 0x23,
        81 => 0x0c,
        82 => 0x0f,
        83 => 0x01,
        84 => 0x11,
        85 => 0x20,
        86 => 0x09,
        87 => 0x0d,
        88 => 0x07,
        89 => 0x10,
        90 => 0x06,
        39 => 0x27,
        92 => 0x2a,
        44 => 0x2b,
        61 => 0x18,
        96 => 0x32,
        91 => 0x21,
        45 => 0x1b,
        46 => 0x2f,
        93 => 0x1e,
        59 => 0x29,
        47 => 0x2c,
        161 => 0x0a,
        259 => 0x33,
        280 => 0x39,
        261 => 0x75,
        264 => 0x7d,
        269 => 0x77,
        257 => 0x24,
        256 => 0x35,
        290 => 0x7a,
        291 => 0x78,
        292 => 0x63,
        293 => 0x76,
        294 => 0x60,
        295 => 0x61,
        296 => 0x62,
        297 => 0x64,
        298 => 0x65,
        299 => 0x6d,
        300 => 0x67,
        301 => 0x6f,
        283 => 0x69,
        303 => 0x6b,
        304 => 0x71,
        305 => 0x6a,
        306 => 0x40,
        307 => 0x4f,
        308 => 0x50,
        309 => 0x5a,
        268 => 0x73,
        260 => 0x72,
        263 => 0x7b,
        342 => 0x3a,
        341 => 0x3b,
        340 => 0x38,
        343 => 0x37,
        348 => 0x6e,
        282 => 0x47,
        267 => 0x79,
        266 => 0x74,
        262 => 0x7c,
        346 => 0x3d,
        345 => 0x3e,
        344 => 0x3c,
        347 => 0x36,
        32 => 0x31,
        258 => 0x30,
        265 => 0x7e,
        320 => 0x52,
        321 => 0x53,
        322 => 0x54,
        323 => 0x55,
        324 => 0x56,
        325 => 0x57,
        326 => 0x58,
        327 => 0x59,
        328 => 0x5b,
        329 => 0x5c,
        334 => 0x45,
        330 => 0x41,
        331 => 0x4b,
        335 => 0x4c,
        336 => 0x51,
        332 => 0x43,
        333 => 0x4e,
        else => -1,
    };
}

pub fn rawMouseMotionSupported() bool {
    return false;
}

pub fn init() bool {
    return initializeTIS();
}

pub fn deinit() void {
    if (input_source) |source| {
        CFRelease(source);
        input_source = null;
    }
    unicode_data = null;
}

pub fn updateUnicodeData() bool {
    if (input_source) |source| {
        CFRelease(source);
        input_source = null;
        unicode_data = null;
    }

    const copy_current = tis.CopyCurrentKeyboardLayoutInputSource orelse return false;
    const get_property = tis.GetInputSourceProperty orelse return false;
    const property = tis.kPropertyUnicodeKeyLayoutData orelse return false;

    const source = copy_current() orelse return false;
    input_source = source;
    unicode_data = get_property(source, property) orelse return false;
    return true;
}

pub fn getScancodeName(scancode: c_int) ?[*:0]const u8 {
    if (scancode < 0 or scancode > 0xff) return null;
    const key = translateKey(@intCast(scancode));
    if (key == 0) return null;

    if (unicode_data == null and !updateUnicodeData()) return null;
    const data = unicode_data orelse return null;
    const layout = CFDataGetBytePtr(data) orelse return null;

    var dead_key_state: u32 = 0;
    var chars: [4]u16 = @splat(0);
    var char_count: u32 = 0;
    if (UCKeyTranslate(
        layout,
        @intCast(scancode),
        kUCKeyActionDisplay,
        0,
        (tis.GetKbdType orelse return null)(),
        kUCKeyTranslateNoDeadKeysBit,
        &dead_key_state,
        chars.len,
        &char_count,
        &chars,
    ) != noErr or char_count == 0) {
        return null;
    }

    const key_index: usize = @intCast(key);
    @memset(&key_names[key_index], 0);
    const utf8_len = std.unicode.utf16LeToUtf8(&key_names[key_index], chars[0..char_count]) catch return null;
    if (utf8_len == 0) return null;
    key_names[key_index][utf8_len] = 0;
    return &key_names[key_index];
}

pub fn translateKey(scancode: u16) c_int {
    return switch (scancode) {
        0x1d => 48,
        0x12 => 49,
        0x13 => 50,
        0x14 => 51,
        0x15 => 52,
        0x17 => 53,
        0x16 => 54,
        0x1a => 55,
        0x1c => 56,
        0x19 => 57,
        0x00 => 65,
        0x0b => 66,
        0x08 => 67,
        0x02 => 68,
        0x0e => 69,
        0x03 => 70,
        0x05 => 71,
        0x04 => 72,
        0x22 => 73,
        0x26 => 74,
        0x28 => 75,
        0x25 => 76,
        0x2e => 77,
        0x2d => 78,
        0x1f => 79,
        0x23 => 80,
        0x0c => 81,
        0x0f => 82,
        0x01 => 83,
        0x11 => 84,
        0x20 => 85,
        0x09 => 86,
        0x0d => 87,
        0x07 => 88,
        0x10 => 89,
        0x06 => 90,
        0x27 => 39,
        0x2a => 92,
        0x2b => 44,
        0x18 => 61,
        0x32 => 96,
        0x21 => 91,
        0x1b => 45,
        0x2f => 46,
        0x1e => 93,
        0x29 => 59,
        0x2c => 47,
        0x0a => 161,
        0x33 => 259,
        0x39 => 280,
        0x75 => 261,
        0x7d => 264,
        0x77 => 269,
        0x24 => 257,
        0x35 => 256,
        0x7a => 290,
        0x78 => 291,
        0x63 => 292,
        0x76 => 293,
        0x60 => 294,
        0x61 => 295,
        0x62 => 296,
        0x64 => 297,
        0x65 => 298,
        0x6d => 299,
        0x67 => 300,
        0x6f => 301,
        0x69 => 283,
        0x6b => 303,
        0x71 => 304,
        0x6a => 305,
        0x40 => 306,
        0x4f => 307,
        0x50 => 308,
        0x5a => 309,
        0x73 => 268,
        0x72 => 260,
        0x7b => 263,
        0x3a => 342,
        0x3b => 341,
        0x38 => 340,
        0x37 => 343,
        0x6e => 348,
        0x47 => 282,
        0x79 => 267,
        0x74 => 266,
        0x7c => 262,
        0x3d => 346,
        0x3e => 345,
        0x3c => 344,
        0x36 => 347,
        0x31 => 32,
        0x30 => 258,
        0x7e => 265,
        0x52 => 320,
        0x53 => 321,
        0x54 => 322,
        0x55 => 323,
        0x56 => 324,
        0x57 => 325,
        0x58 => 326,
        0x59 => 327,
        0x5b => 328,
        0x5c => 329,
        0x45 => 334,
        0x41 => 330,
        0x4b => 331,
        0x4c => 335,
        0x51 => 336,
        0x43 => 332,
        0x4e => 333,
        else => 0,
    };
}

const std = @import("std");

const CFTypeRef = *const anyopaque;
const CFDataRef = *const anyopaque;
const CFStringRef = *const anyopaque;
const CFBundleRef = *const anyopaque;
const TISInputSourceRef = *const anyopaque;

const kUCKeyActionDisplay: u16 = 3;
const kUCKeyTranslateNoDeadKeysBit: u32 = 1;
const kCFStringEncodingUTF8: u32 = 0x08000100;
const noErr: i32 = 0;

const TIS = struct {
    bundle: ?CFBundleRef = null,
    kPropertyUnicodeKeyLayoutData: ?CFTypeRef = null,
    CopyCurrentKeyboardLayoutInputSource: ?*const fn () callconv(.c) ?TISInputSourceRef = null,
    GetInputSourceProperty: ?*const fn (TISInputSourceRef, CFTypeRef) callconv(.c) ?CFDataRef = null,
    GetKbdType: ?*const fn () callconv(.c) u32 = null,
};

var tis: TIS = .{};
var key_names: [512][17:0]u8 = @splat(@splat(0));
var input_source: ?TISInputSourceRef = null;
var unicode_data: ?CFDataRef = null;

extern "c" fn UCKeyTranslate(
    key_layout_ptr: [*]const u8,
    virtual_key_code: u16,
    key_action: u16,
    modifier_key_state: u32,
    keyboard_type: u32,
    key_translate_options: u32,
    dead_key_state: *u32,
    max_string_length: usize,
    actual_string_length: *u32,
    unicode_string: *[4]u16,
) i32;
extern "c" fn CFDataGetBytePtr(data: CFDataRef) ?[*]const u8;
extern "c" fn CFRelease(object: CFTypeRef) void;
extern "c" fn CFStringCreateWithCString(allocator: ?CFTypeRef, c_string: [*:0]const u8, encoding: u32) ?CFStringRef;
extern "c" fn CFBundleGetBundleWithIdentifier(bundle_id: CFStringRef) ?CFBundleRef;
extern "c" fn CFBundleGetDataPointerForName(bundle: CFBundleRef, symbol_name: CFStringRef) ?*anyopaque;
extern "c" fn CFBundleGetFunctionPointerForName(bundle: CFBundleRef, function_name: CFStringRef) ?*const anyopaque;

fn initializeTIS() bool {
    const bundle_id = cfString("com.apple.HIToolbox") orelse return false;
    defer CFRelease(bundle_id);

    const bundle = CFBundleGetBundleWithIdentifier(bundle_id) orelse return false;
    tis.bundle = bundle;

    const property_name = cfString("kTISPropertyUnicodeKeyLayoutData") orelse return false;
    defer CFRelease(property_name);
    const copy_name = cfString("TISCopyCurrentKeyboardLayoutInputSource") orelse return false;
    defer CFRelease(copy_name);
    const get_property_name = cfString("TISGetInputSourceProperty") orelse return false;
    defer CFRelease(get_property_name);
    const get_kbd_type_name = cfString("LMGetKbdType") orelse return false;
    defer CFRelease(get_kbd_type_name);

    const property_pointer = CFBundleGetDataPointerForName(bundle, property_name) orelse return false;
    tis.kPropertyUnicodeKeyLayoutData = @as(*const CFTypeRef, @ptrCast(@alignCast(property_pointer))).*;
    tis.CopyCurrentKeyboardLayoutInputSource = @ptrCast(@alignCast(CFBundleGetFunctionPointerForName(bundle, copy_name) orelse return false));
    tis.GetInputSourceProperty = @ptrCast(@alignCast(CFBundleGetFunctionPointerForName(bundle, get_property_name) orelse return false));
    tis.GetKbdType = @ptrCast(@alignCast(CFBundleGetFunctionPointerForName(bundle, get_kbd_type_name) orelse return false));

    return updateUnicodeData();
}

fn cfString(value: [*:0]const u8) ?CFStringRef {
    return CFStringCreateWithCString(null, value, kCFStringEncodingUTF8);
}
