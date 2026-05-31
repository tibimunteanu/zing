const objc = @import("objc.zig");
const types = @import("types.zig");

pub fn getMetalLayer(handle: *anyopaque) ?*anyopaque {
    const view = viewObject(handle);
    const metal_layer_class = objc.getClass("CAMetalLayer").?;
    var layer = view.msgSend(objc.Object, "layer", .{});
    if (layer.value == null or !layer.msgSend(bool, "isKindOfClass:", .{metal_layer_class.value})) {
        layer = metal_layer_class.msgSend(objc.Object, "layer", .{});
        view.msgSend(void, "setLayer:", .{layer.value});
        view.msgSend(void, "setWantsLayer:", .{true});
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
