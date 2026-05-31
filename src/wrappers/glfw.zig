const std = @import("std");
const vk = @import("../renderer/vk.zig");

pub const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", "1");
    @cInclude("GLFW/glfw3.h");
});

pub const Action = enum(c_int) {
    release = c.GLFW_RELEASE,
    press = c.GLFW_PRESS,
    repeat = c.GLFW_REPEAT,
};

pub const ErrorCode = enum(c_int) {
    not_initialized = c.GLFW_NOT_INITIALIZED,
    no_current_context = c.GLFW_NO_CURRENT_CONTEXT,
    invalid_enum = c.GLFW_INVALID_ENUM,
    invalid_value = c.GLFW_INVALID_VALUE,
    out_of_memory = c.GLFW_OUT_OF_MEMORY,
    api_unavailable = c.GLFW_API_UNAVAILABLE,
    version_unavailable = c.GLFW_VERSION_UNAVAILABLE,
    platform_error = c.GLFW_PLATFORM_ERROR,
    format_unavailable = c.GLFW_FORMAT_UNAVAILABLE,
    no_window_context = c.GLFW_NO_WINDOW_CONTEXT,
    cursor_unavailable = c.GLFW_CURSOR_UNAVAILABLE,
    feature_unavailable = c.GLFW_FEATURE_UNAVAILABLE,
    feature_unimplemented = c.GLFW_FEATURE_UNIMPLEMENTED,
    platform_unavailable = c.GLFW_PLATFORM_UNAVAILABLE,
    _,
};

pub const InitHints = struct {};

pub fn init(_: InitHints) bool {
    return c.glfwInit() == c.GLFW_TRUE;
}

pub fn terminate() void {
    c.glfwTerminate();
}

pub fn pollEvents() void {
    c.glfwPollEvents();
}

pub fn getTime() f64 {
    return c.glfwGetTime();
}

pub fn getErrorString() ?[:0]const u8 {
    var description: [*c]const u8 = null;
    _ = c.glfwGetError(&description);
    if (description == null) return null;
    return std.mem.span(description);
}

pub fn setErrorCallback(callback: ?*const fn (ErrorCode, [:0]const u8) void) void {
    error_callback = callback;
    _ = c.glfwSetErrorCallback(errorCallbackThunk);
}

var error_callback: ?*const fn (ErrorCode, [:0]const u8) void = null;

fn errorCallbackThunk(error_code: c_int, description: [*c]const u8) callconv(.c) void {
    if (error_callback) |callback| {
        callback(@enumFromInt(error_code), std.mem.span(description));
    }
}

pub fn getRequiredInstanceExtensions() ?[]const [*:0]const u8 {
    var count: u32 = 0;
    const extensions = c.glfwGetRequiredInstanceExtensions(&count);
    if (extensions == null) return null;
    return @as([*][*:0]const u8, @ptrCast(extensions))[0..count];
}

pub fn getInstanceProcAddress(instance: vk.Instance, name: [*:0]const u8) callconv(vk.vulkan_call_conv) vk.PfnVoidFunction {
    return @ptrCast(c.glfwGetInstanceProcAddress(toVkInstance(instance), name));
}

pub fn createWindowSurface(instance: vk.Instance, window: Window, allocation_callbacks: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) c_int {
    var c_surface: c.VkSurfaceKHR = 0;
    const result = c.glfwCreateWindowSurface(
        toVkInstance(instance),
        window.handle,
        @ptrCast(allocation_callbacks),
        &c_surface,
    );
    surface.* = @enumFromInt(c_surface);
    return result;
}

fn toVkInstance(instance: vk.Instance) c.VkInstance {
    return @ptrFromInt(@intFromEnum(instance));
}

pub const Window = struct {
    handle: *c.GLFWwindow,

    pub const Size = struct {
        width: u32,
        height: u32,
    };

    pub const Hints = struct {
        client_api: ClientAPI = .no_api,

        pub const ClientAPI = enum(c_int) {
            no_api = c.GLFW_NO_API,
        };
    };

    pub const Attribute = enum(c_int) {
        iconified = c.GLFW_ICONIFIED,
    };

    pub const Key = enum(c_int) {
        a = c.GLFW_KEY_A,
        d = c.GLFW_KEY_D,
        h = c.GLFW_KEY_H,
        j = c.GLFW_KEY_J,
        k = c.GLFW_KEY_K,
        l = c.GLFW_KEY_L,
        n = c.GLFW_KEY_N,
        s = c.GLFW_KEY_S,
        w = c.GLFW_KEY_W,
    };

    pub fn create(width: u32, height: u32, title: [:0]const u8, monitor: ?*anyopaque, share: ?Window, hints: Hints) ?Window {
        c.glfwDefaultWindowHints();
        c.glfwWindowHint(c.GLFW_CLIENT_API, @intFromEnum(hints.client_api));

        const handle = c.glfwCreateWindow(
            @intCast(width),
            @intCast(height),
            title.ptr,
            @ptrCast(monitor),
            if (share) |shared| shared.handle else null,
        ) orelse return null;

        return .{ .handle = handle };
    }

    pub fn destroy(self: Window) void {
        c.glfwDestroyWindow(self.handle);
    }

    pub fn shouldClose(self: Window) bool {
        return c.glfwWindowShouldClose(self.handle) == c.GLFW_TRUE;
    }

    pub fn getAttrib(self: Window, attribute: Attribute) c_int {
        return c.glfwGetWindowAttrib(self.handle, @intFromEnum(attribute));
    }

    pub fn getKey(self: Window, key: Key) Action {
        return @enumFromInt(c.glfwGetKey(self.handle, @intFromEnum(key)));
    }

    pub fn getFramebufferSize(self: Window) Size {
        var width: c_int = 0;
        var height: c_int = 0;
        c.glfwGetFramebufferSize(self.handle, &width, &height);
        return .{ .width = @intCast(width), .height = @intCast(height) };
    }

    pub fn setFramebufferSizeCallback(self: Window, callback: ?*const fn (Window, u32, u32) void) void {
        framebuffer_size_callback = callback;
        _ = c.glfwSetFramebufferSizeCallback(self.handle, framebufferSizeCallbackThunk);
    }
};

var framebuffer_size_callback: ?*const fn (Window, u32, u32) void = null;

fn framebufferSizeCallbackThunk(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
    if (framebuffer_size_callback) |callback| {
        callback(.{ .handle = window.? }, @intCast(width), @intCast(height));
    }
}
