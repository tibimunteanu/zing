const std = @import("std");

const linux = std.os.linux;

const poll_axes: u8 = 1;
const poll_buttons: u8 = 2;

const max_joysticks = 16;
const max_axes = 64;
const max_buttons = 128;
const max_hats = 16;
const path_max = 4096;
const max_event_devices = 256;
const invalid_map = std.math.maxInt(usize);

const EV_SYN = 0x00;
const EV_KEY = 0x01;
const EV_ABS = 0x03;
const EV_CNT = 0x20;

const SYN_REPORT = 0;
const SYN_DROPPED = 3;

const KEY_CNT = 0x300;
const BTN_MISC = 0x100;

const ABS_CNT = 0x40;
const ABS_HAT0X = 0x10;
const ABS_HAT3Y = 0x17;

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

const InputId = extern struct {
    bustype: u16,
    vendor: u16,
    product: u16,
    version: u16,
};

const InputAbsInfo = extern struct {
    value: c_int,
    minimum: c_int,
    maximum: c_int,
    fuzz: c_int,
    flat: c_int,
    resolution: c_int,
};

const InputEvent = extern struct {
    time: extern struct {
        tv_sec: c_long,
        tv_usec: c_long,
    },
    type: u16,
    code: u16,
    value: i32,
};

const InotifyEvent = extern struct {
    wd: c_int,
    mask: u32,
    cookie: u32,
    len: u32,
};

const Path = [path_max:0]u8;

const Slot = struct {
    fd: i32 = -1,
    path: Path = @splat(0),
    key_map: [KEY_CNT - BTN_MISC]usize = @splat(invalid_map),
    abs_map: [ABS_CNT]isize = @splat(-1),
    abs_info: [ABS_CNT]InputAbsInfo = [_]InputAbsInfo{std.mem.zeroes(InputAbsInfo)} ** ABS_CNT,
    hats: [4][2]i32 = [_][2]i32{.{ 0, 0 }} ** 4,
};

var callbacks: ?Callbacks = null;
var slots: [max_joysticks]Slot = @splat(.{});
var inotify_fd: i32 = -1;
var inotify_watch: i32 = -1;
var dropped = false;

pub fn init(new_callbacks: Callbacks) !void {
    callbacks = new_callbacks;
    setupInotify();
    enumerateJoysticks();
}

pub fn deinit() void {
    for (0..max_joysticks) |index| closeSlot(index);

    if (inotify_fd > 0) {
        if (inotify_watch > 0) _ = linux.inotify_rm_watch(inotify_fd, inotify_watch);
        _ = linux.close(inotify_fd);
    }

    callbacks = null;
    slots = @splat(.{});
    inotify_fd = -1;
    inotify_watch = -1;
    dropped = false;
}

pub fn poll(index: usize, mode: u8) !bool {
    if (index >= max_joysticks) return false;
    detectConnections();
    if (slots[index].fd == -1) return false;

    if ((mode & (poll_axes | poll_buttons)) == 0) return true;
    pollSlot(index);
    return slots[index].fd != -1;
}

pub fn updateGamepadGuid(_: *[33:0]u8) void {}

pub fn eventFd() i32 {
    return inotify_fd;
}

pub fn detectConnections() void {
    if (callbacks == null or inotify_fd <= 0) return;

    var buffer: [16384]u8 = undefined;
    const rc = linux.read(inotify_fd, &buffer, buffer.len);
    if (std.posix.errno(rc) != .SUCCESS or rc == 0) return;

    const size: usize = @intCast(rc);
    var offset: usize = 0;
    while (offset + @sizeOf(InotifyEvent) <= size) {
        const event = std.mem.bytesAsValue(InotifyEvent, buffer[offset .. offset + @sizeOf(InotifyEvent)]);
        offset += @sizeOf(InotifyEvent);
        if (offset + event.len > size) break;
        defer offset += event.len;

        const raw_name = buffer[offset .. offset + event.len];
        const name = std.mem.sliceTo(raw_name, 0);
        if (!isEventDeviceName(name)) continue;

        var path_buffer: Path = @splat(0);
        const path = std.fmt.bufPrintSentinel(&path_buffer, "/dev/input/{s}", .{name}, 0) catch continue;

        if ((event.mask & (linux.IN.CREATE | linux.IN.ATTRIB)) != 0) {
            _ = openJoystickDevice(path);
        } else if ((event.mask & linux.IN.DELETE) != 0) {
            if (slotForPath(path)) |index| closeSlot(index);
        }
    }
}

fn setupInotify() void {
    const fd_rc = linux.inotify_init1(linux.IN.NONBLOCK | linux.IN.CLOEXEC);
    if (std.posix.errno(fd_rc) != .SUCCESS or fd_rc == 0) return;

    inotify_fd = @intCast(fd_rc);
    inotify_watch = -1;

    // GLFW registers IN_ATTRIB as a udev-completion approximation.
    const watch_rc = linux.inotify_add_watch(inotify_fd, "/dev/input", linux.IN.CREATE | linux.IN.ATTRIB | linux.IN.DELETE);
    if (std.posix.errno(watch_rc) == .SUCCESS) inotify_watch = @intCast(watch_rc);
}

fn enumerateJoysticks() void {
    var paths: [max_event_devices]Path = undefined;
    var count: usize = 0;

    var dir = std.fs.openDirAbsolute("/dev/input", .{ .iterate = true }) catch return;
    defer dir.close();

    var iterator = dir.iterate();
    while (iterator.next() catch null) |entry| {
        if (!isEventDeviceName(entry.name)) continue;
        if (count >= paths.len) break;

        paths[count] = @splat(0);
        _ = std.fmt.bufPrintSentinel(&paths[count], "/dev/input/{s}", .{entry.name}, 0) catch continue;
        count += 1;
    }

    std.mem.sortUnstable(Path, paths[0..count], {}, lessPath);
    for (paths[0..count]) |*path| _ = openJoystickDevice(std.mem.sliceTo(path, 0));
}

fn openJoystickDevice(path: [:0]const u8) bool {
    if (slotForPath(path) != null) return false;

    const fd = openEventDevice(path) orelse return false;
    errdefer _ = linux.close(fd);

    var ev_bits: [(EV_CNT + 7) / 8]u8 = @splat(0);
    var key_bits: [(KEY_CNT + 7) / 8]u8 = @splat(0);
    var abs_bits: [(ABS_CNT + 7) / 8]u8 = @splat(0);
    var id: InputId = undefined;

    if (!ioctlRead(fd, eviocgbit(0, ev_bits.len), &ev_bits) or
        !ioctlRead(fd, eviocgbit(EV_KEY, key_bits.len), &key_bits) or
        !ioctlRead(fd, eviocgbit(EV_ABS, abs_bits.len), &abs_bits) or
        !ioctlRead(fd, eviocgid(), &id))
    {
        return false;
    }

    if (!isBitSet(EV_ABS, &ev_bits)) return false;

    var name: [256:0]u8 = @splat(0);
    if (!ioctlRead(fd, eviocgname(name.len), &name)) {
        @memcpy(name[0.."Unknown".len], "Unknown");
    }
    name[name.len - 1] = 0;

    var slot = Slot{ .fd = fd };
    const path_len = @min(path.len, slot.path.len - 1);
    @memcpy(slot.path[0..path_len], path[0..path_len]);

    var guid: [33:0]u8 = @splat(0);
    formatGuid(&guid, id, &name);

    var axis_count: usize = 0;
    var button_count: usize = 0;
    var hat_count: usize = 0;

    for (BTN_MISC..KEY_CNT) |code| {
        if (!isBitSet(code, &key_bits)) continue;
        slot.key_map[code - BTN_MISC] = button_count;
        button_count += 1;
    }

    var code: usize = 0;
    while (code < ABS_CNT) : (code += 1) {
        if (!isBitSet(code, &abs_bits)) continue;

        if (code >= ABS_HAT0X and code <= ABS_HAT3Y) {
            const hat = hat_count;
            slot.abs_map[code] = @intCast(hat);
            if (code + 1 < ABS_CNT) slot.abs_map[code + 1] = @intCast(hat);
            hat_count += 1;
            code += 1;
        } else {
            if (!ioctlRead(fd, eviocgabs(@intCast(code)), &slot.abs_info[code])) continue;
            slot.abs_map[code] = @intCast(axis_count);
            axis_count += 1;
        }
    }

    const index = firstFreeSlot() orelse return false;
    slots[index] = slot;
    pollAbsState(index);

    if (callbacks) |cb| cb.connect(index, std.mem.sliceTo(&name, 0), guid[0..32], axis_count, button_count, hat_count);
    return true;
}

fn closeSlot(index: usize) void {
    if (slots[index].fd == -1) return;

    if (callbacks) |cb| cb.disconnect(index);
    _ = linux.close(slots[index].fd);
    slots[index] = .{};
}

fn pollSlot(index: usize) void {
    while (slots[index].fd != -1) {
        var event: InputEvent = undefined;
        const bytes = std.mem.asBytes(&event);
        const rc = linux.read(slots[index].fd, bytes.ptr, bytes.len);
        switch (std.posix.errno(rc)) {
            .SUCCESS => {
                if (rc != bytes.len) return;
            },
            .INTR => continue,
            .NODEV => {
                closeSlot(index);
                return;
            },
            else => return,
        }

        if (event.type == EV_SYN) {
            if (event.code == SYN_DROPPED) {
                dropped = true;
            } else if (event.code == SYN_REPORT) {
                dropped = false;
                pollAbsState(index);
            }
        }

        if (dropped) continue;

        if (event.type == EV_KEY) {
            handleKeyEvent(index, event.code, event.value);
        } else if (event.type == EV_ABS) {
            handleAbsEvent(index, event.code, event.value);
        }
    }
}

fn pollAbsState(index: usize) void {
    const slot = &slots[index];
    for (0..ABS_CNT) |code| {
        if (slot.abs_map[code] < 0) continue;
        if (!ioctlRead(slot.fd, eviocgabs(@intCast(code)), &slot.abs_info[code])) continue;
        handleAbsEvent(index, @intCast(code), slot.abs_info[code].value);
    }
}

fn handleKeyEvent(index: usize, code: u16, value: i32) void {
    if (code < BTN_MISC or code >= KEY_CNT) return;
    const mapped = slots[index].key_map[code - BTN_MISC];
    if (mapped == invalid_map) return;
    if (callbacks) |cb| cb.button(index, mapped, value != 0);
}

fn handleAbsEvent(index: usize, code: u16, value: i32) void {
    if (code >= ABS_CNT) return;
    const slot = &slots[index];
    const mapped = slot.abs_map[code];
    if (mapped < 0) return;

    if (code >= ABS_HAT0X and code <= ABS_HAT3Y) {
        const state_map = [3][3]u8{
            .{ 0x00, 0x01, 0x04 },
            .{ 0x08, 0x09, 0x0c },
            .{ 0x02, 0x03, 0x06 },
        };

        const hat = (code - ABS_HAT0X) / 2;
        const axis = (code - ABS_HAT0X) % 2;
        if (hat >= slot.hats.len) return;

        if (value == 0) {
            slot.hats[hat][axis] = 0;
        } else if (value < 0) {
            slot.hats[hat][axis] = 1;
        } else {
            slot.hats[hat][axis] = 2;
        }

        if (callbacks) |cb| {
            cb.hat(index, @intCast(mapped), state_map[@intCast(slot.hats[hat][0])][@intCast(slot.hats[hat][1])]);
        }
    } else {
        const info = slot.abs_info[code];
        var normalized: f32 = @floatFromInt(value);
        const range = info.maximum - info.minimum;
        if (range != 0) {
            normalized = (normalized - @as(f32, @floatFromInt(info.minimum))) / @as(f32, @floatFromInt(range));
            normalized = normalized * 2.0 - 1.0;
        }

        if (callbacks) |cb| cb.axis(index, @intCast(mapped), normalized);
    }
}

fn openEventDevice(path: [:0]const u8) ?i32 {
    const rc = linux.openat(linux.AT.FDCWD, path.ptr, .{ .ACCMODE = .RDONLY, .NONBLOCK = true, .CLOEXEC = true }, 0);
    return if (std.posix.errno(rc) == .SUCCESS) @intCast(rc) else null;
}

fn ioctlRead(fd: i32, request: u32, ptr: anytype) bool {
    return std.posix.errno(linux.ioctl(fd, request, @intFromPtr(ptr))) == .SUCCESS;
}

fn eviocgid() u32 {
    return linux.IOCTL.IOR('E', 0x02, InputId);
}

fn eviocgname(comptime len: usize) u32 {
    return linux.IOCTL.IOR('E', 0x06, [len]u8);
}

fn eviocgbit(comptime event_type: u8, comptime len: usize) u32 {
    return linux.IOCTL.IOR('E', 0x20 + event_type, [len]u8);
}

fn eviocgabs(code: u8) u32 {
    return linux.IOCTL.IOR('E', 0x40 + code, InputAbsInfo);
}

fn formatGuid(buffer: *[33:0]u8, id: InputId, name: *const [256:0]u8) void {
    if (id.vendor != 0 and id.product != 0 and id.version != 0) {
        _ = std.fmt.bufPrintSentinel(buffer, "{x:0>2}{x:0>2}0000{x:0>2}{x:0>2}0000{x:0>2}{x:0>2}0000{x:0>2}{x:0>2}0000", .{
            @as(u8, @truncate(id.bustype)),
            @as(u8, @truncate(id.bustype >> 8)),
            @as(u8, @truncate(id.vendor)),
            @as(u8, @truncate(id.vendor >> 8)),
            @as(u8, @truncate(id.product)),
            @as(u8, @truncate(id.product >> 8)),
            @as(u8, @truncate(id.version)),
            @as(u8, @truncate(id.version >> 8)),
        }, 0) catch {};
    } else {
        _ = std.fmt.bufPrintSentinel(buffer, "{x:0>2}{x:0>2}0000{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}00", .{
            @as(u8, @truncate(id.bustype)),
            @as(u8, @truncate(id.bustype >> 8)),
            name[0],
            name[1],
            name[2],
            name[3],
            name[4],
            name[5],
            name[6],
            name[7],
            name[8],
            name[9],
            name[10],
        }, 0) catch {};
    }
}

fn isBitSet(bit: usize, bits: []const u8) bool {
    return (bits[bit / 8] & (@as(u8, 1) << @intCast(bit % 8))) != 0;
}

fn firstFreeSlot() ?usize {
    for (slots, 0..) |slot, index| {
        if (slot.fd == -1) return index;
    }
    return null;
}

fn slotForPath(path: []const u8) ?usize {
    for (&slots, 0..) |*slot, index| {
        if (slot.fd == -1) continue;
        if (std.mem.eql(u8, std.mem.sliceTo(&slot.path, 0), path)) return index;
    }
    return null;
}

fn isEventDeviceName(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "event") or name.len == "event".len) return false;
    for (name["event".len..]) |char| {
        if (!std.ascii.isDigit(char)) return false;
    }
    return true;
}

fn lessPath(_: void, lhs: Path, rhs: Path) bool {
    return std.mem.order(u8, std.mem.sliceTo(&lhs, 0), std.mem.sliceTo(&rhs, 0)) == .lt;
}

test "event device name matching follows GLFW regex" {
    try std.testing.expect(isEventDeviceName("event0"));
    try std.testing.expect(isEventDeviceName("event42"));
    try std.testing.expect(!isEventDeviceName("event"));
    try std.testing.expect(!isEventDeviceName("js0"));
    try std.testing.expect(!isEventDeviceName("eventx"));
}
