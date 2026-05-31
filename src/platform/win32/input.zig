const std = @import("std");
const win = @import("types.zig");

var key_name_buffers: [349][5:0]u8 = @splat(@splat(0));

pub fn rawMouseMotionSupported() bool {
    return true;
}

pub fn getKeyScancode(key: c_int) c_int {
    const vk = keyToVirtualKey(key);
    if (vk == 0) return -1;
    const scancode = win.MapVirtualKeyW(@intCast(vk), win.MAPVK_VK_TO_VSC);
    if (scancode == 0) return -1;
    return @intCast(scancode);
}

pub fn getScancodeName(scancode: c_int) ?[*:0]const u8 {
    if (scancode < 0 or scancode >= 512) return null;

    const vk = win.MapVirtualKeyW(@intCast(scancode), win.MAPVK_VSC_TO_VK);
    const key = translateKey(@intCast(vk), @intCast(scancode));
    if (key <= 0 or key >= key_name_buffers.len) return null;

    var state: [256]win.BYTE = @splat(0);
    _ = win.GetKeyboardState(&state[0]);

    var chars: [8]win.WCHAR = @splat(0);
    const length = win.ToUnicode(@intCast(vk), @intCast(scancode), &state[0], &chars[0], 8, 0);
    if (length <= 0) return null;

    var buffer = &key_name_buffers[@intCast(key)];
    @memset(buffer, 0);
    const length_utf8 = std.unicode.wtf16LeToWtf8(buffer[0 .. buffer.len - 1], chars[0..@intCast(length)]);
    buffer[length_utf8] = 0;
    return buffer;
}

pub fn translateKey(vk: u32, scancode: u32) c_int {
    _ = scancode;
    if (vk >= 'A' and vk <= 'Z') return @intCast(vk);
    if (vk >= '0' and vk <= '9') return @intCast(vk);
    return switch (vk) {
        0x20 => 32,
        0xde => 39,
        0xbc => 44,
        0xbd => 45,
        0xbe => 46,
        0xbf => 47,
        0xba => 59,
        0xbb => 61,
        0xdb => 91,
        0xdc => 92,
        0xdd => 93,
        0xc0 => 96,
        0x1b => 256,
        0x0d => 257,
        0x09 => 258,
        0x08 => 259,
        0x2d => 260,
        0x2e => 261,
        0x27 => 262,
        0x25 => 263,
        0x28 => 264,
        0x26 => 265,
        0x21 => 266,
        0x22 => 267,
        0x24 => 268,
        0x23 => 269,
        0x14 => 280,
        0x91 => 281,
        0x90 => 282,
        0x2c => 283,
        0x13 => 284,
        0x70...0x87 => @intCast(290 + vk - 0x70),
        0x60...0x69 => @intCast(320 + vk - 0x60),
        0x6e => 330,
        0x6f => 331,
        0x6a => 332,
        0x6d => 333,
        0x6b => 334,
        0x10 => 340,
        0xa0 => 340,
        0xa1 => 344,
        0x11 => 341,
        0xa2 => 341,
        0xa3 => 345,
        0x12 => 342,
        0xa4 => 342,
        0xa5 => 346,
        0x5b => 343,
        0x5c => 347,
        0x5d => 348,
        else => 0,
    };
}

fn keyToVirtualKey(key: c_int) u32 {
    if (key >= 'A' and key <= 'Z') return @intCast(key);
    if (key >= '0' and key <= '9') return @intCast(key);
    return switch (key) {
        32 => 0x20,
        39 => 0xde,
        44 => 0xbc,
        45 => 0xbd,
        46 => 0xbe,
        47 => 0xbf,
        59 => 0xba,
        61 => 0xbb,
        91 => 0xdb,
        92 => 0xdc,
        93 => 0xdd,
        96 => 0xc0,
        256 => 0x1b,
        257 => 0x0d,
        258 => 0x09,
        259 => 0x08,
        260 => 0x2d,
        261 => 0x2e,
        262 => 0x27,
        263 => 0x25,
        264 => 0x28,
        265 => 0x26,
        266 => 0x21,
        267 => 0x22,
        268 => 0x24,
        269 => 0x23,
        280 => 0x14,
        281 => 0x91,
        282 => 0x90,
        283 => 0x2c,
        284 => 0x13,
        290...313 => @intCast(0x70 + key - 290),
        320...329 => @intCast(0x60 + key - 320),
        330 => 0x6e,
        331 => 0x6f,
        332 => 0x6a,
        333 => 0x6d,
        334 => 0x6b,
        340 => 0xa0,
        341 => 0xa2,
        342 => 0xa4,
        343 => 0x5b,
        344 => 0xa1,
        345 => 0xa3,
        346 => 0xa5,
        347 => 0x5c,
        348 => 0x5d,
        else => 0,
    };
}
