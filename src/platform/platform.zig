const builtin = @import("builtin");

const backend = switch (builtin.os.tag) {
    .macos => struct {
        pub const Cursor = @import("macos/cursor.zig");
        pub const Events = @import("macos/events.zig");
        pub const Input = @import("macos/input.zig");
        pub const Monitor = @import("macos/monitor.zig");
        pub const Native = @import("macos/native.zig");
        pub const Tests = @import("macos/tests.zig");
        pub const VulkanWSI = @import("macos/vulkan_wsi.zig");
        pub const Window = @import("macos/window.zig");
    },
    .windows => @compileError("Zing win32 platform backend is not implemented yet"),
    .linux => @compileError("Zing X11 platform backend is not implemented yet"),
    else => @compileError("Zing platform layer does not support this target OS"),
};

pub const os_tag = builtin.os.tag;

pub const Cursor = backend.Cursor;
pub const Events = backend.Events;
pub const Input = backend.Input;
pub const Monitor = backend.Monitor;
pub const Native = backend.Native;
pub const Tests = backend.Tests;
pub const VulkanWSI = backend.VulkanWSI;
pub const Window = backend.Window;
