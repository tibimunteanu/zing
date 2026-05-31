const builtin = @import("builtin");

pub const Cursor = @import("platform/cursor.zig");
pub const Errors = @import("platform/errors.zig");
pub const Events = @import("platform/events.zig");
pub const Input = @import("platform/input.zig");
pub const Joystick = @import("platform/joystick.zig");
pub const Monitor = @import("platform/monitor.zig");
pub const Native = @import("platform/native.zig");
pub const Platform = @import("platform/platform.zig");
pub const Time = @import("platform/time.zig");
pub const VulkanWSI = @import("platform/vulkan_wsi.zig");
pub const Window = @import("platform/window.zig");
pub const objc = switch (builtin.os.tag) {
    .macos => @import("platform/macos/objc.zig"),
    else => struct {},
};
pub const vk = @import("renderer/vk.zig");
