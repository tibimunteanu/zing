const std = @import("std");

const objc = @import("objc.zig");
const types = @import("types.zig");

pub fn openLocalVulkanLoader() ?std.DynLib {
    const bundle = objc.getClass("NSBundle").?.msgSend(objc.Object, "mainBundle", .{});
    if (bundle.value == null) return null;
    const frameworks = bundle.msgSend(objc.Object, "privateFrameworksPath", .{});
    if (frameworks.value == null) return null;
    const path = frameworks.msgSend(objc.Object, "stringByAppendingPathComponent:", .{nsString("libvulkan.1.dylib").value});
    if (path.value == null) return null;
    return std.DynLib.open(std.mem.span(path.msgSend([*:0]const u8, "fileSystemRepresentation", .{}))) catch null;
}

pub fn getMetalLayer(handle: *anyopaque) ?*anyopaque {
    const window: *types.Window = @ptrCast(@alignCast(handle));
    const view = viewObject(handle);
    var layer = if (window.layer) |existing| objc.Object.fromId(existing) else objc.Object{ .value = null };
    if (layer.value == null) {
        const bundle = objc.getClass("NSBundle").?.msgSend(objc.Object, "bundleWithPath:", .{nsString("/System/Library/Frameworks/QuartzCore.framework").value});
        if (bundle.value == null) return null;
        const metal_layer_class = bundle.msgSend(objc.Object, "classNamed:", .{nsString("CAMetalLayer").value});
        if (metal_layer_class.value == null) return null;

        layer = metal_layer_class.msgSend(objc.Object, "layer", .{});
        if (layer.value == null) return null;

        window.layer = layer.value;
        view.msgSend(void, "setWantsLayer:", .{true});
        view.msgSend(void, "setLayer:", .{layer.value});
    }
    if (window.scale_framebuffer) {
        layer.msgSend(void, "setContentsScale:", .{objc.Object.fromId(window.window).msgSend(f64, "backingScaleFactor", .{})});
    }
    return layer.value;
}

pub fn getNativeView(handle: *anyopaque) ?*anyopaque {
    const window: *types.Window = @ptrCast(@alignCast(handle));
    return window.view;
}

fn viewObject(handle: *anyopaque) objc.Object {
    const window: *types.Window = @ptrCast(@alignCast(handle));
    return objc.Object.fromId(window.view);
}

fn nsString(value: [:0]const u8) objc.Object {
    return objc.getClass("NSString").?.msgSend(objc.Object, "stringWithUTF8String:", .{value.ptr});
}
