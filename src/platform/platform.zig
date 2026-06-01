const builtin = @import("builtin");

const backend = switch (builtin.os.tag) {
    .macos => struct {
        pub const Cursor = @import("macos/cursor.zig");
        pub const Events = @import("macos/events.zig");
        pub const Input = @import("macos/input.zig");
        pub const Joystick = @import("macos/joystick.zig");
        pub const Monitor = @import("macos/monitor.zig");
        pub const Native = @import("macos/native.zig");
        pub const Tests = @import("macos/tests.zig");
        pub const Time = @import("macos/time.zig");
        pub const VulkanWSI = @import("macos/vulkan_wsi.zig");
        pub const Window = @import("macos/window.zig");
    },
    .windows => struct {
        pub const Cursor = @import("win32/cursor.zig");
        pub const Events = @import("win32/events.zig");
        pub const Input = @import("win32/input.zig");
        pub const Joystick = @import("win32/joystick.zig");
        pub const Monitor = @import("win32/monitor.zig");
        pub const Native = @import("win32/native.zig");
        pub const Tests = @import("win32/tests.zig");
        pub const Time = @import("win32/time.zig");
        pub const VulkanWSI = @import("win32/vulkan_wsi.zig");
        pub const Window = @import("win32/window.zig");
    },
    .linux => struct {
        pub const Cursor = @import("x11/cursor.zig");
        pub const Events = @import("x11/events.zig");
        pub const Input = @import("x11/input.zig");
        pub const Joystick = @import("x11/joystick.zig");
        pub const Monitor = @import("x11/monitor.zig");
        pub const Native = @import("x11/native.zig");
        pub const Tests = @import("x11/tests.zig");
        pub const Time = @import("x11/time.zig");
        pub const VulkanWSI = @import("x11/vulkan_wsi.zig");
        pub const Window = @import("x11/window.zig");
    },
    else => @compileError("Zing platform layer does not support this target OS"),
};

pub const os_tag = builtin.os.tag;

pub const Cursor = backend.Cursor;
pub const Events = backend.Events;
pub const Input = backend.Input;
pub const Joystick = backend.Joystick;
pub const Monitor = backend.Monitor;
pub const Native = backend.Native;
pub const Tests = backend.Tests;
pub const Time = backend.Time;
pub const VulkanWSI = backend.VulkanWSI;
pub const Window = backend.Window;
