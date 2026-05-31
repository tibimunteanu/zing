const std = @import("std");
const builtin = @import("builtin");

const vk = @import("../renderer/vk.zig");
const Window = @import("window.zig");
const Errors = @import("errors.zig");
const platform = @import("platform.zig");
const win32_types = if (builtin.os.tag == .windows) @import("win32/types.zig") else struct {};

pub const GetInstanceProcAddress = *const fn (vk.Instance, [*:0]const u8) callconv(vk.vulkan_call_conv) vk.PfnVoidFunction;
const VulkanLibrary = if (builtin.os.tag == .windows) WindowsVulkanLibrary else std.DynLib;

var loader: ?GetInstanceProcAddress = null;
var vulkan_library: ?VulkanLibrary = null;
var owns_loader = false;
var available = false;
var has_khr_surface = false;
var has_ext_metal_surface = false;
var has_mvk_macos_surface = false;
var has_khr_win32_surface = false;
const macos_extensions = [_][*:0]const u8{
    "VK_KHR_surface",
    "VK_EXT_metal_surface",
};
const macos_mvk_extensions = [_][*:0]const u8{
    "VK_KHR_surface",
    "VK_MVK_macos_surface",
};

const MetalSurfaceCreateInfoEXT = extern struct {
    s_type: vk.StructureType = .metal_surface_create_info_ext,
    p_next: ?*const anyopaque = null,
    flags: vk.MetalSurfaceCreateFlagsEXT = .{},
    p_layer: *const anyopaque,
};

const PfnCreateMetalSurfaceEXT = *const fn (
    instance: vk.Instance,
    p_create_info: *const MetalSurfaceCreateInfoEXT,
    p_allocator: ?*const vk.AllocationCallbacks,
    p_surface: *vk.SurfaceKHR,
) callconv(vk.vulkan_call_conv) vk.Result;

pub fn initSystem(new_loader: ?GetInstanceProcAddress) !void {
    loader = new_loader;
    owns_loader = new_loader == null;

    if (loader == null) {
        var library = openVulkanLibrary() catch {
            Errors.report(.api_unavailable, "Vulkan: loader not found", .{});
            return error.ApiUnavailable;
        };
        errdefer library.close();

        loader = library.lookup(vk.PfnGetInstanceProcAddr, "vkGetInstanceProcAddr") orelse {
            Errors.report(.api_unavailable, "Vulkan: vkGetInstanceProcAddr not found", .{});
            return error.ApiUnavailable;
        };
        vulkan_library = library;
    }

    try loadExtensionAvailability();
}

pub fn deinitSystem() void {
    loader = null;
    available = false;
    has_khr_surface = false;
    has_ext_metal_surface = false;
    has_mvk_macos_surface = false;
    has_khr_win32_surface = false;
    if (owns_loader) {
        if (vulkan_library) |*library| {
            library.close();
            vulkan_library = null;
        }
    }
    owns_loader = false;
}

pub fn supported() !bool {
    return switch (platform.os_tag) {
        .macos => available,
        .windows => available,
        else => false,
    };
}

pub fn getRequiredInstanceExtensions() ![]const [*:0]const u8 {
    switch (platform.os_tag) {
        .macos => {
            if (!has_khr_surface or (!has_ext_metal_surface and !has_mvk_macos_surface)) {
                Errors.report(.api_unavailable, "Vulkan: window surface creation extensions not found", .{});
                return error.ApiUnavailable;
            }
            return if (has_ext_metal_surface) &macos_extensions else &macos_mvk_extensions;
        },
        .windows => {
            if (!has_khr_surface or !has_khr_win32_surface) {
                Errors.report(.api_unavailable, "Vulkan: window surface creation extensions not found", .{});
                return error.ApiUnavailable;
            }
            return &platform.VulkanWSI.RequiredExtensions;
        },
        else => return error.PlatformUnavailable,
    }
}

pub fn getInstanceProcAddress(instance: vk.Instance, name: [*:0]const u8) callconv(vk.vulkan_call_conv) vk.PfnVoidFunction {
    if (std.mem.eql(u8, std.mem.span(name), "vkGetInstanceProcAddr")) {
        if (loader) |load| return @ptrCast(load);
    }
    if (loader) |load| {
        if (load(instance, name)) |proc| return proc;
    }
    if (vulkan_library) |*library| {
        return library.lookup(*const fn () callconv(vk.vulkan_call_conv) void, std.mem.span(name));
    }
    return null;
}

pub fn getPhysicalDevicePresentationSupport(instance: vk.Instance, physical_device: vk.PhysicalDevice, queue_family: u32) !bool {
    if (platform.os_tag == .macos) {
        return available and has_khr_surface and (has_ext_metal_surface or has_mvk_macos_surface);
    }
    if (platform.os_tag == .windows) {
        if (!available or !has_khr_surface or !has_khr_win32_surface) return false;
        const get_proc = getInstanceProcAddress(instance, "vkGetPhysicalDeviceWin32PresentationSupportKHR") orelse return false;
        const get_support: vk.PfnGetPhysicalDeviceWin32PresentationSupportKHR = @ptrCast(get_proc);
        return get_support(physical_device, queue_family) != 0;
    }
    return false;
}

pub fn createWindowSurface(instance: vk.Instance, window: Window, allocation_callbacks: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) !void {
    surface.* = .null_handle;
    if (platform.os_tag == .windows) {
        if (!has_khr_surface or !has_khr_win32_surface) return error.ApiUnavailable;
        const get_proc = getInstanceProcAddress(instance, "vkCreateWin32SurfaceKHR") orelse return error.ApiUnavailable;
        const create_win32_surface: vk.PfnCreateWin32SurfaceKHR = @ptrCast(get_proc);
        const create_info = vk.Win32SurfaceCreateInfoKHR{
            .hinstance = @ptrCast(platform.VulkanWSI.getNativeInstance() orelse return error.PlatformError),
            .hwnd = @ptrCast(platform.VulkanWSI.getNativeWindow(try window.nativeHandle()) orelse return error.PlatformError),
        };
        const result = create_win32_surface(instance, &create_info, allocation_callbacks, surface);
        return switch (result) {
            .success => {},
            .error_out_of_host_memory => error.OutOfHostMemory,
            .error_out_of_device_memory => error.OutOfDeviceMemory,
            .error_native_window_in_use_khr => error.NativeWindowInUse,
            else => error.PlatformError,
        };
    }

    if (platform.os_tag != .macos) return error.PlatformUnavailable;
    if (!has_khr_surface or (!has_ext_metal_surface and !has_mvk_macos_surface)) return error.ApiUnavailable;

    const result = if (has_ext_metal_surface) blk: {
        const get_proc = getInstanceProcAddress(instance, "vkCreateMetalSurfaceEXT") orelse return error.ApiUnavailable;
        const create_metal_surface: PfnCreateMetalSurfaceEXT = @ptrCast(get_proc);
        const create_info = MetalSurfaceCreateInfoEXT{
            .p_layer = platform.VulkanWSI.getMetalLayer(try window.nativeHandle()) orelse return error.PlatformError,
        };
        break :blk create_metal_surface(instance, &create_info, allocation_callbacks, surface);
    } else blk: {
        const get_proc = getInstanceProcAddress(instance, "vkCreateMacOSSurfaceMVK") orelse return error.ApiUnavailable;
        const create_macos_surface: vk.PfnCreateMacOSSurfaceMVK = @ptrCast(get_proc);
        const create_info = vk.MacOSSurfaceCreateInfoMVK{
            .p_view = platform.VulkanWSI.getNativeView(try window.nativeHandle()) orelse return error.PlatformError,
        };
        break :blk create_macos_surface(instance, &create_info, allocation_callbacks, surface);
    };
    return switch (result) {
        .success => {},
        .error_out_of_host_memory => error.OutOfHostMemory,
        .error_out_of_device_memory => error.OutOfDeviceMemory,
        .error_native_window_in_use_khr => error.NativeWindowInUse,
        else => error.PlatformError,
    };
}

fn loadExtensionAvailability() !void {
    available = false;
    has_khr_surface = false;
    has_ext_metal_surface = false;
    has_mvk_macos_surface = false;
    has_khr_win32_surface = false;

    const get_proc = loader orelse return;
    const enumerate_proc = get_proc(.null_handle, "vkEnumerateInstanceExtensionProperties") orelse {
        if (owns_loader) {
            Errors.report(.api_unavailable, "Vulkan: failed to retrieve vkEnumerateInstanceExtensionProperties", .{});
            return error.ApiUnavailable;
        }
        return;
    };
    const enumerate: vk.PfnEnumerateInstanceExtensionProperties = @ptrCast(enumerate_proc);

    var count: u32 = 0;
    var result = enumerate(null, &count, null);
    if (result != .success) {
        if (owns_loader) {
            Errors.report(.api_unavailable, "Vulkan: failed to query instance extension count", .{});
            return error.ApiUnavailable;
        }
        return;
    }

    var properties: [256]vk.ExtensionProperties = undefined;
    const query_count = @min(count, properties.len);
    count = @intCast(query_count);
    result = enumerate(null, &count, properties[0..].ptr);
    if (result != .success) {
        if (owns_loader) {
            Errors.report(.api_unavailable, "Vulkan: failed to query instance extensions", .{});
            return error.ApiUnavailable;
        }
        return;
    }

    for (properties[0..count]) |property| {
        const len = std.mem.indexOfScalar(u8, &property.extension_name, 0) orelse property.extension_name.len;
        const name = property.extension_name[0..len];
        if (std.mem.eql(u8, name, "VK_KHR_surface")) has_khr_surface = true;
        if (std.mem.eql(u8, name, "VK_EXT_metal_surface")) has_ext_metal_surface = true;
        if (std.mem.eql(u8, name, "VK_MVK_macos_surface")) has_mvk_macos_surface = true;
        if (std.mem.eql(u8, name, "VK_KHR_win32_surface")) has_khr_win32_surface = true;
    }

    available = switch (platform.os_tag) {
        .macos => has_khr_surface and (has_ext_metal_surface or has_mvk_macos_surface),
        .windows => has_khr_surface and has_khr_win32_surface,
        else => false,
    };
}

fn openVulkanLibrary() !VulkanLibrary {
    if (builtin.os.tag == .windows) {
        const handle = win32_types.LoadLibraryA("vulkan-1.dll") orelse return error.PlatformUnavailable;
        return .{ .handle = handle };
    }
    if (builtin.os.tag == .macos) {
        if (std.c.getenv("VULKAN_SDK")) |sdk| {
            var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
            const path = try std.fmt.bufPrint(&path_buffer, "{s}/lib/libvulkan.1.dylib", .{std.mem.span(sdk)});
            if (std.DynLib.open(path)) |library| return library else |_| {}
        }

        return std.DynLib.open("libvulkan.1.dylib") catch std.DynLib.open("libvulkan.dylib");
    }

    if (builtin.os.tag == .linux) {
        return std.DynLib.open("libvulkan.so.1") catch std.DynLib.open("libvulkan.so");
    }

    return error.PlatformUnavailable;
}

const WindowsVulkanLibrary = struct {
    handle: win32_types.HMODULE,

    fn close(self: *WindowsVulkanLibrary) void {
        _ = win32_types.FreeLibrary(self.handle);
        self.handle = null;
    }

    fn lookup(self: *WindowsVulkanLibrary, comptime T: type, name: []const u8) ?T {
        var buffer: [128:0]u8 = @splat(0);
        if (name.len >= buffer.len) return null;
        @memcpy(buffer[0..name.len], name);
        const proc = win32_types.GetProcAddress(self.handle, &buffer) orelse return null;
        return @ptrCast(@alignCast(proc));
    }
};
