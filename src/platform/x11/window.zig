const std = @import("std");

const Input = @import("../input.zig");
const cursor_module = @import("cursor.zig");
const input = @import("input.zig");
const monitor_module = @import("monitor.zig");
const x11 = @import("types.zig");
const xkb_unicode = @import("xkb_unicode.zig");

const xdnd_version = 5;
const max_drop_paths = 256;
const shape_set = 0;
const shape_input = 2;
const xi_all_master_devices = 1;
const xi_raw_motion = 17;
const lc_ctype = 0;

extern fn setlocale(category: c_int, locale: ?[*:0]const u8) ?[*:0]u8;

const Xshape = struct {
    lib: std.DynLib,
    XShapeQueryExtension: *const fn (*x11.Display, *c_int, *c_int) callconv(.c) x11.Bool,
    XShapeQueryVersion: *const fn (*x11.Display, *c_int, *c_int) callconv(.c) x11.Status,
    XShapeCombineRegion: *const fn (*x11.Display, x11.Window, c_int, c_int, c_int, ?*x11.Region, c_int) callconv(.c) void,
    XShapeCombineMask: *const fn (*x11.Display, x11.Window, c_int, c_int, c_int, x11.Pixmap, c_int) callconv(.c) void,
};

const XRenderDirectFormat = extern struct {
    red: c_short,
    red_mask: c_short,
    green: c_short,
    green_mask: c_short,
    blue: c_short,
    blue_mask: c_short,
    alpha: c_short,
    alpha_mask: c_short,
};

const XRenderPictFormat = extern struct {
    id: x11.XID,
    type: c_int,
    depth: c_int,
    direct: XRenderDirectFormat,
    colormap: x11.Colormap,
};

const XRender = struct {
    lib: std.DynLib,
    configured: bool = false,
    available: bool = false,
    major: c_int = 0,
    minor: c_int = 0,
    event_base: c_int = 0,
    error_base: c_int = 0,
    XRenderQueryExtension: *const fn (*x11.Display, *c_int, *c_int) callconv(.c) x11.Bool,
    XRenderQueryVersion: *const fn (*x11.Display, *c_int, *c_int) callconv(.c) x11.Status,
    XRenderFindVisualFormat: *const fn (*x11.Display, *const x11.Visual) callconv(.c) ?*XRenderPictFormat,
};

const XIEventMask = extern struct {
    deviceid: c_int,
    mask_len: c_int,
    mask: [*]u8,
};

const XIValuatorState = extern struct {
    mask_len: c_int,
    mask: [*]u8,
    values: [*]f64,
};

const XIRawEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: x11.Bool,
    display: ?*x11.Display,
    extension: c_int,
    evtype: c_int,
    time: x11.Time,
    deviceid: c_int,
    sourceid: c_int,
    detail: c_int,
    flags: c_int,
    valuators: XIValuatorState,
    raw_values: [*]f64,
};

const Xi = struct {
    lib: std.DynLib,
    XIQueryVersion: *const fn (*x11.Display, *c_int, *c_int) callconv(.c) x11.Status,
    XISelectEvents: *const fn (*x11.Display, x11.Window, *XIEventMask, c_int) callconv(.c) c_int,
};

pub const Config = extern struct {
    width: u32,
    height: u32,
    title: [*:0]const u8,
    resizable: bool,
    visible: bool,
    decorated: bool,
    focused: bool,
    auto_iconify: bool,
    floating: bool,
    maximized: bool,
    center_cursor: bool,
    scale_to_monitor: bool,
    scale_framebuffer: bool,
    transparent_framebuffer: bool,
    mouse_passthrough: bool,
    monitor: ?*anyopaque,
};

pub const ContentScale = extern struct {
    x_scale: f32,
    y_scale: f32,
};

pub const FrameSize = extern struct {
    left: u32,
    top: u32,
    right: u32,
    bottom: u32,
};

pub const Pos = extern struct {
    x: i32,
    y: i32,
};

pub const Size = extern struct {
    width: u32,
    height: u32,
};

pub const IconImage = extern struct {
    width: u32,
    height: u32,
    pixels: [*]const u8,
};

pub const EventCallbacks = struct {
    close: *const fn (usize) void,
    pos: *const fn (usize, i32, i32) void,
    size: *const fn (usize, u32, u32) void,
    focus: *const fn (usize, bool) void,
    iconify: *const fn (usize, bool) void,
    maximize: *const fn (usize, bool) void,
    framebuffer_size: *const fn (usize, u32, u32) void,
    content_scale: *const fn (usize, f32, f32) void,
    key: *const fn (usize, i32, i32, i32, u8) void,
    key_state: *const fn (usize, i32) i32,
    char: *const fn (usize, u32) void,
    char_mods: *const fn (usize, u32, u8) void,
    mouse_button: *const fn (usize, i32, i32, u8) void,
    cursor_pos: *const fn (usize, f64, f64) void,
    cursor_enter: *const fn (usize, bool) void,
    scroll: *const fn (usize, f64, f64) void,
    refresh: *const fn (usize) void,
    drop: *const fn (usize, usize, [*][*:0]const u8) void,
    monitor_changed: *const fn () void,
};

const max_windows = 128;
const event_mask =
    x11.StructureNotifyMask |
    x11.ExposureMask |
    x11.FocusChangeMask |
    x11.KeyPressMask |
    x11.KeyReleaseMask |
    x11.ButtonPressMask |
    x11.ButtonReleaseMask |
    x11.PointerMotionMask |
    x11.VisibilityChangeMask |
    x11.EnterWindowMask |
    x11.LeaveWindowMask |
    x11.PropertyChangeMask;

var callbacks_: ?EventCallbacks = null;
var initialized = false;
var windows: [max_windows]?*x11.WindowState = @splat(null);
var helper_window: x11.Window = 0;
var blank_cursor: x11.Cursor = 0;
var primary_selection_buffer: ?[:0]u8 = null;
var clipboard_buffer: ?[:0]u8 = null;
var xshape: ?Xshape = null;
var xshape_available = false;
var xrender: ?XRender = null;
var xi: ?Xi = null;
var disabled_cursor_window: ?*x11.WindowState = null;
var screen_saver_count: u32 = 0;
var screen_saver_timeout: c_int = 0;
var screen_saver_interval: c_int = 0;
var screen_saver_blanking: c_int = 0;
var screen_saver_exposure: c_int = 0;

pub fn setEventCallbacks(new_callbacks: EventCallbacks) void {
    callbacks_ = new_callbacks;
}

pub fn init() bool {
    if (initialized) return true;
    applyLocaleHack();
    if (!x11.loadXlib()) return false;
    const lib = &(x11.xlib orelse return false);
    if (lib.XInitThreads() == 0) {
        x11.unloadXlib();
        return false;
    }
    lib.XrmInitialize();

    x11.display = lib.XOpenDisplay(null) orelse {
        x11.unloadXlib();
        return false;
    };
    x11.screen = lib.XDefaultScreen(x11.display.?);
    x11.root = lib.XRootWindow(x11.display.?, x11.screen);
    detectContentScale();
    loadXi();
    loadXshape();
    loadXrender();
    x11.wm_delete_window = lib.XInternAtom(x11.display.?, "WM_DELETE_WINDOW", 0);
    x11.wm_protocols = lib.XInternAtom(x11.display.?, "WM_PROTOCOLS", 0);
    x11.wm_state = lib.XInternAtom(x11.display.?, "WM_STATE", 0);
    x11.null_atom = lib.XInternAtom(x11.display.?, "NULL", 0);
    x11.utf8_string = lib.XInternAtom(x11.display.?, "UTF8_STRING", 0);
    x11.atom_pair = lib.XInternAtom(x11.display.?, "ATOM_PAIR", 0);
    x11.targets = lib.XInternAtom(x11.display.?, "TARGETS", 0);
    x11.multiple = lib.XInternAtom(x11.display.?, "MULTIPLE", 0);
    x11.primary = lib.XInternAtom(x11.display.?, "PRIMARY", 0);
    x11.incr = lib.XInternAtom(x11.display.?, "INCR", 0);
    x11.clipboard = lib.XInternAtom(x11.display.?, "CLIPBOARD", 0);
    x11.clipboard_manager = lib.XInternAtom(x11.display.?, "CLIPBOARD_MANAGER", 0);
    x11.save_targets = lib.XInternAtom(x11.display.?, "SAVE_TARGETS", 0);
    x11.glfw_selection = lib.XInternAtom(x11.display.?, "GLFW_SELECTION", 0);
    x11.net_wm_icon = lib.XInternAtom(x11.display.?, "_NET_WM_ICON", 0);
    x11.net_wm_pid = lib.XInternAtom(x11.display.?, "_NET_WM_PID", 0);
    x11.net_wm_name = lib.XInternAtom(x11.display.?, "_NET_WM_NAME", 0);
    x11.net_wm_icon_name = lib.XInternAtom(x11.display.?, "_NET_WM_ICON_NAME", 0);
    x11.net_wm_ping = lib.XInternAtom(x11.display.?, "_NET_WM_PING", 0);
    x11.net_supported = lib.XInternAtom(x11.display.?, "_NET_SUPPORTED", 0);
    x11.net_supporting_wm_check = lib.XInternAtom(x11.display.?, "_NET_SUPPORTING_WM_CHECK", 0);
    x11.net_wm_window_type = lib.XInternAtom(x11.display.?, "_NET_WM_WINDOW_TYPE", 0);
    x11.net_wm_window_type_normal = lib.XInternAtom(x11.display.?, "_NET_WM_WINDOW_TYPE_NORMAL", 0);
    x11.net_wm_fullscreen_monitors = lib.XInternAtom(x11.display.?, "_NET_WM_FULLSCREEN_MONITORS", 0);
    x11.net_workarea = lib.XInternAtom(x11.display.?, "_NET_WORKAREA", 0);
    x11.net_current_desktop = lib.XInternAtom(x11.display.?, "_NET_CURRENT_DESKTOP", 0);
    x11.net_active_window = lib.XInternAtom(x11.display.?, "_NET_ACTIVE_WINDOW", 0);
    x11.net_frame_extents = lib.XInternAtom(x11.display.?, "_NET_FRAME_EXTENTS", 0);
    x11.net_request_frame_extents = lib.XInternAtom(x11.display.?, "_NET_REQUEST_FRAME_EXTENTS", 0);
    x11.net_wm_window_opacity = lib.XInternAtom(x11.display.?, "_NET_WM_WINDOW_OPACITY", 0);
    var compositor_name_buffer: [32]u8 = undefined;
    const compositor_name = std.fmt.bufPrintSentinel(&compositor_name_buffer, "_NET_WM_CM_S{d}", .{x11.screen}, 0) catch "_NET_WM_CM_S0";
    x11.net_wm_cm_sx = lib.XInternAtom(x11.display.?, compositor_name.ptr, 0);
    x11.net_wm_state = lib.XInternAtom(x11.display.?, "_NET_WM_STATE", 0);
    x11.net_wm_state_fullscreen = lib.XInternAtom(x11.display.?, "_NET_WM_STATE_FULLSCREEN", 0);
    x11.net_wm_state_above = lib.XInternAtom(x11.display.?, "_NET_WM_STATE_ABOVE", 0);
    x11.net_wm_state_demands_attention = lib.XInternAtom(x11.display.?, "_NET_WM_STATE_DEMANDS_ATTENTION", 0);
    x11.net_wm_state_hidden = lib.XInternAtom(x11.display.?, "_NET_WM_STATE_HIDDEN", 0);
    x11.net_wm_state_maximized_vert = lib.XInternAtom(x11.display.?, "_NET_WM_STATE_MAXIMIZED_VERT", 0);
    x11.net_wm_state_maximized_horz = lib.XInternAtom(x11.display.?, "_NET_WM_STATE_MAXIMIZED_HORZ", 0);
    x11.net_wm_bypass_compositor = lib.XInternAtom(x11.display.?, "_NET_WM_BYPASS_COMPOSITOR", 0);
    x11.motif_wm_hints = lib.XInternAtom(x11.display.?, "_MOTIF_WM_HINTS", 0);
    x11.xdnd_aware = lib.XInternAtom(x11.display.?, "XdndAware", 0);
    x11.xdnd_enter = lib.XInternAtom(x11.display.?, "XdndEnter", 0);
    x11.xdnd_position = lib.XInternAtom(x11.display.?, "XdndPosition", 0);
    x11.xdnd_status = lib.XInternAtom(x11.display.?, "XdndStatus", 0);
    x11.xdnd_action_copy = lib.XInternAtom(x11.display.?, "XdndActionCopy", 0);
    x11.xdnd_drop = lib.XInternAtom(x11.display.?, "XdndDrop", 0);
    x11.xdnd_finished = lib.XInternAtom(x11.display.?, "XdndFinished", 0);
    x11.xdnd_selection = lib.XInternAtom(x11.display.?, "XdndSelection", 0);
    x11.xdnd_type_list = lib.XInternAtom(x11.display.?, "XdndTypeList", 0);
    x11.text_uri_list = lib.XInternAtom(x11.display.?, "text/uri-list", 0);

    input.initKeyboard();
    detectEWMH();

    var helper_attributes = x11.XSetWindowAttributes{
        .event_mask = x11.PropertyChangeMask,
    };
    helper_window = lib.XCreateWindow(
        x11.display.?,
        x11.root,
        0,
        0,
        1,
        1,
        0,
        0,
        x11.InputOnly,
        lib.XDefaultVisual(x11.display.?, x11.screen),
        x11.CWEventMask,
        &helper_attributes,
    );
    if (helper_window == 0) {
        _ = lib.XCloseDisplay(x11.display.?);
        x11.display = null;
        x11.unloadXlib();
        return false;
    }

    blank_cursor = createBlankCursor();
    initInputMethod();
    monitor_module.refresh();
    input.initKeycodes();
    initialized = true;
    return true;
}

pub fn deinit() void {
    const lib = &(x11.xlib orelse return);
    if (x11.display) |display| {
        if (helper_window != 0) {
            if (lib.XGetSelectionOwner(display, x11.clipboard) == helper_window) {
                pushSelectionToManager();
            }
            _ = lib.XDestroyWindow(display, helper_window);
            helper_window = 0;
        }
        if (blank_cursor != 0) {
            _ = lib.XFreeCursor(display, blank_cursor);
            blank_cursor = 0;
        }
        _ = lib.XUnregisterIMInstantiateCallback(
            display,
            null,
            null,
            null,
            inputMethodInstantiateCallback,
            null,
        );
        if (x11.im != null) {
            _ = lib.XCloseIM(x11.im);
            x11.im = null;
        }
        _ = lib.XCloseDisplay(display);
    }
    unloadXi();
    unloadXshape();
    unloadXrender();
    x11.display = null;
    x11.root = 0;
    x11.xi_available = false;
    x11.xi_major_opcode = 0;
    x11.detectable_autorepeat = false;
    disabled_cursor_window = null;
    screen_saver_count = 0;
    windows = @splat(null);
    if (clipboard_buffer) |buffer| {
        std.heap.c_allocator.free(buffer);
        clipboard_buffer = null;
    }
    if (primary_selection_buffer) |buffer| {
        std.heap.c_allocator.free(buffer);
        primary_selection_buffer = null;
    }
    x11.unloadXlib();
    initialized = false;
}

fn applyLocaleHack() void {
    const current = setlocale(lc_ctype, null) orelse return;
    if (std.mem.eql(u8, std.mem.span(current), "C")) {
        _ = setlocale(lc_ctype, "");
    }
}

fn detectContentScale() void {
    x11.content_scale_x = 1.0;
    x11.content_scale_y = 1.0;

    const display = x11.display orelse return;
    const lib = &(x11.xlib orelse return);
    const resource_string = lib.XResourceManagerString(display) orelse return;
    const database = lib.XrmGetStringDatabase(resource_string) orelse return;
    defer lib.XrmDestroyDatabase(database);

    var value: x11.XrmValue = .{
        .size = 0,
        .addr = null,
    };
    var resource_type: ?[*:0]u8 = null;
    if (lib.XrmGetResource(database, "Xft.dpi", "Xft.Dpi", &resource_type, &value) == 0) return;
    if (resource_type == null or !std.mem.eql(u8, std.mem.span(resource_type.?), "String")) return;
    const addr = value.addr orelse return;
    const dpi = std.fmt.parseFloat(f32, std.mem.span(@as([*:0]const u8, @ptrCast(addr)))) catch return;
    x11.content_scale_x = dpi / 96.0;
    x11.content_scale_y = dpi / 96.0;
}

fn initInputMethod() void {
    const display = x11.display orelse return;
    const lib = &(x11.xlib orelse return);
    if (lib.XSupportsLocale() == 0 or !x11.xlib_utf8) return;

    _ = lib.XSetLocaleModifiers("");
    _ = lib.XRegisterIMInstantiateCallback(
        display,
        null,
        null,
        null,
        inputMethodInstantiateCallback,
        null,
    );
}

fn inputMethodInstantiateCallback(_: *x11.Display, _: x11.XPointer, _: x11.XPointer) callconv(.c) void {
    if (x11.im != null) return;

    const display = x11.display orelse return;
    const lib = &(x11.xlib orelse return);
    x11.im = lib.XOpenIM(display, null, null, null);
    if (x11.im != null and !hasUsableInputMethodStyle()) {
        _ = lib.XCloseIM(x11.im);
        x11.im = null;
    }

    if (x11.im != null) {
        var callback = x11.XIMCallback{
            .client_data = null,
            .callback = inputMethodDestroyCallback,
        };
        _ = lib.XSetIMValues(
            x11.im,
            x11.XNDestroyCallback,
            &callback,
            @as(?*anyopaque, null),
        );

        for (&windows) |maybe_window| {
            if (maybe_window) |window| createInputContext(window);
        }
    }
}

fn inputMethodDestroyCallback(_: x11.XIM, _: x11.XPointer, _: x11.XPointer) callconv(.c) void {
    x11.im = null;
}

fn inputContextDestroyCallback(_: x11.XIM, client_data: x11.XPointer, _: x11.XPointer) callconv(.c) void {
    const window: *x11.WindowState = @ptrCast(@alignCast(client_data orelse return));
    window.ic = null;
}

fn hasUsableInputMethodStyle() bool {
    const lib = &(x11.xlib orelse return false);
    var styles: ?*x11.XIMStyles = null;
    if (lib.XGetIMValues(
        x11.im,
        x11.XNQueryInputStyle,
        &styles,
        @as(?*anyopaque, null),
    ) != null) return false;
    defer {
        if (styles) |ptr| _ = lib.XFree(ptr);
    }

    const usable_style = x11.XIMPreeditNothing | x11.XIMStatusNothing;
    const resolved_styles = styles orelse return false;
    var i: usize = 0;
    while (i < resolved_styles.count_styles) : (i += 1) {
        if (resolved_styles.supported_styles[i] == usable_style) return true;
    }

    return false;
}

fn createInputContext(window: *x11.WindowState) void {
    if (window.ic != null) return;
    const lib = &(x11.xlib orelse return);
    var callback = x11.XIMCallback{
        .client_data = window,
        .callback = inputContextDestroyCallback,
    };

    window.ic = lib.XCreateIC(
        x11.im,
        x11.XNInputStyle,
        @as(x11.XIMStyle, x11.XIMPreeditNothing | x11.XIMStatusNothing),
        x11.XNClientWindow,
        window.handle,
        x11.XNFocusWindow,
        window.handle,
        x11.XNDestroyCallback,
        &callback,
        @as(?*anyopaque, null),
    );

    if (window.ic != null) {
        var attributes: x11.XWindowAttributes = .{};
        if (lib.XGetWindowAttributes(window.display, window.handle, &attributes) == 0) return;

        var filter: c_ulong = 0;
        if (lib.XGetICValues(
            window.ic,
            x11.XNFilterEvents,
            &filter,
            @as(?*anyopaque, null),
        ) == null) {
            _ = lib.XSelectInput(window.display, window.handle, attributes.your_event_mask | @as(c_long, @intCast(filter)));
        }
    }
}

fn xErrorHandler(display: *x11.Display, event: *x11.XErrorEvent) callconv(.c) c_int {
    if (x11.display) |current| {
        if (current == display) x11.error_code = @intCast(event.error_code);
    }
    return 0;
}

fn grabErrorHandler() void {
    const lib = &(x11.xlib orelse return);
    x11.error_code = x11.Success;
    x11.error_handler = lib.XSetErrorHandler(xErrorHandler);
}

fn releaseErrorHandler() void {
    const display = x11.display orelse return;
    const lib = &(x11.xlib orelse return);
    _ = lib.XSync(display, 0);
    _ = lib.XSetErrorHandler(x11.error_handler);
    x11.error_handler = null;
}

fn detectEWMH() void {
    clearEWMHSupportAtoms();

    const display = x11.display orelse return;
    const lib = &(x11.xlib orelse return);
    if (x11.net_supporting_wm_check == 0 or x11.net_supported == 0) return;

    const window_from_root = readSingleWindowProperty(display, x11.root, x11.net_supporting_wm_check) orelse return;
    grabErrorHandler();
    const window_from_child = readSingleWindowProperty(display, window_from_root, x11.net_supporting_wm_check);
    releaseErrorHandler();
    if (x11.error_code == x11.BadWindow) return;
    if (window_from_child == null or window_from_root != window_from_child.?) return;

    var actual_type: x11.Atom = 0;
    var actual_format: c_int = 0;
    var atom_count: c_ulong = 0;
    var bytes_after: c_ulong = 0;
    var data: ?[*]u8 = null;
    _ = lib.XGetWindowProperty(
        display,
        x11.root,
        x11.net_supported,
        0,
        std.math.maxInt(c_long),
        0,
        x11.XA_ATOM,
        &actual_type,
        &actual_format,
        &atom_count,
        &bytes_after,
        &data,
    );
    defer {
        if (data) |ptr| _ = lib.XFree(@ptrCast(ptr));
    }

    if (data == null or actual_type != x11.XA_ATOM or actual_format != 32) return;
    const supported_atoms: [*]x11.Atom = @ptrCast(@alignCast(data.?));
    const atoms = supported_atoms[0..@intCast(atom_count)];

    x11.net_wm_state = getAtomIfSupported(atoms, "_NET_WM_STATE");
    x11.net_wm_state_above = getAtomIfSupported(atoms, "_NET_WM_STATE_ABOVE");
    x11.net_wm_state_fullscreen = getAtomIfSupported(atoms, "_NET_WM_STATE_FULLSCREEN");
    x11.net_wm_state_maximized_vert = getAtomIfSupported(atoms, "_NET_WM_STATE_MAXIMIZED_VERT");
    x11.net_wm_state_maximized_horz = getAtomIfSupported(atoms, "_NET_WM_STATE_MAXIMIZED_HORZ");
    x11.net_wm_state_demands_attention = getAtomIfSupported(atoms, "_NET_WM_STATE_DEMANDS_ATTENTION");
    x11.net_wm_fullscreen_monitors = getAtomIfSupported(atoms, "_NET_WM_FULLSCREEN_MONITORS");
    x11.net_wm_window_type = getAtomIfSupported(atoms, "_NET_WM_WINDOW_TYPE");
    x11.net_wm_window_type_normal = getAtomIfSupported(atoms, "_NET_WM_WINDOW_TYPE_NORMAL");
    x11.net_workarea = getAtomIfSupported(atoms, "_NET_WORKAREA");
    x11.net_current_desktop = getAtomIfSupported(atoms, "_NET_CURRENT_DESKTOP");
    x11.net_active_window = getAtomIfSupported(atoms, "_NET_ACTIVE_WINDOW");
    x11.net_frame_extents = getAtomIfSupported(atoms, "_NET_FRAME_EXTENTS");
    x11.net_request_frame_extents = getAtomIfSupported(atoms, "_NET_REQUEST_FRAME_EXTENTS");
}

fn clearEWMHSupportAtoms() void {
    x11.net_wm_state = 0;
    x11.net_wm_state_above = 0;
    x11.net_wm_state_fullscreen = 0;
    x11.net_wm_state_maximized_vert = 0;
    x11.net_wm_state_maximized_horz = 0;
    x11.net_wm_state_demands_attention = 0;
    x11.net_wm_fullscreen_monitors = 0;
    x11.net_wm_window_type = 0;
    x11.net_wm_window_type_normal = 0;
    x11.net_workarea = 0;
    x11.net_current_desktop = 0;
    x11.net_active_window = 0;
    x11.net_frame_extents = 0;
    x11.net_request_frame_extents = 0;
}

fn readSingleWindowProperty(display: *x11.Display, window: x11.Window, property: x11.Atom) ?x11.Window {
    const lib = &(x11.xlib orelse return null);
    var actual_type: x11.Atom = 0;
    var actual_format: c_int = 0;
    var item_count: c_ulong = 0;
    var bytes_after: c_ulong = 0;
    var data: ?[*]u8 = null;
    _ = lib.XGetWindowProperty(
        display,
        window,
        property,
        0,
        1,
        0,
        x11.XA_WINDOW,
        &actual_type,
        &actual_format,
        &item_count,
        &bytes_after,
        &data,
    );
    defer {
        if (data) |ptr| _ = lib.XFree(@ptrCast(ptr));
    }

    if (data == null or actual_type != x11.XA_WINDOW or actual_format != 32 or item_count == 0) return null;
    const values: [*]x11.Window = @ptrCast(@alignCast(data.?));
    return values[0];
}

fn getAtomIfSupported(supported_atoms: []const x11.Atom, atom_name: [:0]const u8) x11.Atom {
    const display = x11.display orelse return 0;
    const lib = &(x11.xlib orelse return 0);
    const atom = lib.XInternAtom(display, atom_name.ptr, 0);
    for (supported_atoms) |supported| {
        if (supported == atom) return atom;
    }
    return 0;
}

pub fn create(config: *const Config) ?*anyopaque {
    const display = x11.display orelse return null;
    const lib = &(x11.xlib orelse return null);
    const visual = lib.XDefaultVisual(display, x11.screen) orelse return null;
    const colormap = lib.XCreateColormap(display, x11.root, visual, x11.AllocNone);
    if (colormap == 0) return null;
    var width = config.width;
    var height = config.height;
    if (config.scale_to_monitor) {
        width = @intFromFloat(@as(f32, @floatFromInt(width)) * x11.content_scale_x);
        height = @intFromFloat(@as(f32, @floatFromInt(height)) * x11.content_scale_y);
    }

    var attributes = x11.XSetWindowAttributes{
        .border_pixel = 0,
        .colormap = colormap,
        .event_mask = event_mask,
    };
    grabErrorHandler();
    const handle = lib.XCreateWindow(
        display,
        x11.root,
        0,
        0,
        width,
        height,
        0,
        lib.XDefaultDepth(display, x11.screen),
        x11.InputOutput,
        visual,
        x11.CWBorderPixel | x11.CWColormap | x11.CWEventMask,
        &attributes,
    );
    releaseErrorHandler();
    if (handle == 0) {
        _ = lib.XFreeColormap(display, colormap);
        return null;
    }

    const window = std.heap.c_allocator.create(x11.WindowState) catch {
        _ = lib.XDestroyWindow(display, handle);
        _ = lib.XFreeColormap(display, colormap);
        return null;
    };
    window.* = .{
        .display = display,
        .handle = handle,
        .parent = x11.root,
        .colormap = colormap,
        .width = width,
        .height = height,
        .decorated = config.decorated,
        .resizable = config.resizable,
        .floating = config.floating,
        .mouse_passthrough = config.mouse_passthrough,
        .raw_mouse_motion = false,
        .auto_iconify = config.auto_iconify,
        .transparent = isVisualTransparent(visual),
    };

    _ = lib.XSelectInput(display, handle, event_mask);
    setTitleForWindow(window, config.title);
    setWindowPid(window);
    setWindowDecorations(window, config.decorated);
    setWindowType(window);
    setWindowHints(window);
    updateNormalHints(window);
    setClassHint(window, config.title);
    var version: x11.Atom = xdnd_version;
    _ = lib.XChangeProperty(
        display,
        handle,
        x11.xdnd_aware,
        x11.XA_ATOM,
        32,
        x11.PropModeReplace,
        @ptrCast(&version),
        1,
    );
    var protocols = [_]x11.Atom{ x11.wm_delete_window, x11.net_wm_ping };
    _ = lib.XSetWMProtocols(display, handle, &protocols[0], protocols.len);
    if (x11.im != null) createInputContext(window);
    registerWindow(window);

    if (config.maximized) maximize(@ptrCast(window));
    if (config.floating) setWindowFloating(window, true);
    if (config.visible) show(@ptrCast(window));
    if (config.focused) focus(@ptrCast(window));
    if (config.mouse_passthrough) setMousePassthrough(window, true);
    return @ptrCast(window);
}

pub fn destroy(handle: *anyopaque) void {
    const window = native(handle);
    if (window.monitor) |monitor| {
        releaseMonitor(window, monitor);
        window.monitor = null;
    }
    unregisterWindow(window);
    if (x11.xlib) |lib| {
        if (window.ic != null) {
            lib.XDestroyIC(window.ic);
            window.ic = null;
        }
        _ = lib.XDestroyWindow(window.display, window.handle);
        if (window.colormap != 0) _ = lib.XFreeColormap(window.display, window.colormap);
        _ = lib.XFlush(window.display);
    }
    std.heap.c_allocator.destroy(window);
}

pub fn setCallbackId(handle: *anyopaque, id: usize) void {
    native(handle).callback_id = id;
}

pub fn shouldClose(handle: *anyopaque) bool {
    return native(handle).should_close;
}

pub fn setShouldClose(handle: *anyopaque, value: bool) void {
    native(handle).should_close = value;
}

pub fn setTitle(handle: *anyopaque, title: [*:0]const u8) void {
    const window = native(handle);
    setTitleForWindow(window, title);
}

pub fn getPos(handle: *anyopaque) Pos {
    const window = native(handle);
    if (x11.xlib) |lib| {
        var child: x11.Window = 0;
        var x: c_int = 0;
        var y: c_int = 0;
        if (lib.XTranslateCoordinates(window.display, window.handle, x11.root, 0, 0, &x, &y, &child) != 0) {
            window.x = x;
            window.y = y;
        }
    }
    return .{ .x = window.x, .y = window.y };
}

pub fn setPos(handle: *anyopaque, pos: Pos) void {
    const window = native(handle);
    window.x = pos.x;
    window.y = pos.y;
    if (x11.xlib) |lib| {
        if (!isWindowVisible(window)) {
            var hints = x11.XSizeHints{};
            var supplied: c_long = 0;
            if (lib.XGetWMNormalHints(window.display, window.handle, &hints, &supplied) != 0) {
                hints.flags |= x11.PPosition;
                hints.x = 0;
                hints.y = 0;
                lib.XSetWMNormalHints(window.display, window.handle, &hints);
            }
        }

        _ = lib.XMoveWindow(window.display, window.handle, pos.x, pos.y);
        _ = lib.XFlush(window.display);
    }
}

pub fn getSize(handle: *anyopaque) Size {
    const window = native(handle);
    if (x11.xlib) |lib| {
        var attributes = x11.XWindowAttributes{};
        if (lib.XGetWindowAttributes(window.display, window.handle, &attributes) != 0) {
            window.width = @intCast(attributes.width);
            window.height = @intCast(attributes.height);
        }
    }
    return .{ .width = window.width, .height = window.height };
}

pub fn setSize(handle: *anyopaque, size: Size) void {
    const window = native(handle);
    window.width = size.width;
    window.height = size.height;
    if (window.monitor) |monitor| {
        setMonitorVideoMode(monitor, size, 0);
    } else {
        if (!window.resizable) updateNormalHints(window);
        if (x11.xlib) |lib| _ = lib.XResizeWindow(window.display, window.handle, size.width, size.height);
    }
    if (x11.xlib) |lib| _ = lib.XFlush(window.display);
}

pub fn setSizeLimits(handle: *anyopaque, min_size: Size, max_size: Size) void {
    const window = native(handle);
    window.min_width = min_size.width;
    window.min_height = min_size.height;
    window.max_width = max_size.width;
    window.max_height = max_size.height;
    updateNormalHints(window);
    if (x11.xlib) |lib| _ = lib.XFlush(window.display);
}

pub fn setAspectRatio(handle: *anyopaque, numerator: u32, denominator: u32) void {
    const window = native(handle);
    window.aspect_numerator = numerator;
    window.aspect_denominator = denominator;
    updateNormalHints(window);
    if (x11.xlib) |lib| _ = lib.XFlush(window.display);
}

pub fn clearAspectRatio(handle: *anyopaque) void {
    const window = native(handle);
    window.aspect_numerator = 0;
    window.aspect_denominator = 0;
    updateNormalHints(window);
    if (x11.xlib) |lib| _ = lib.XFlush(window.display);
}

pub fn getFramebufferSize(handle: *anyopaque) Size {
    return getSize(handle);
}

pub fn getFrameSize(handle: *anyopaque) FrameSize {
    const window = native(handle);
    if (window.monitor != null or !window.decorated or x11.net_frame_extents == 0) {
        return .{ .left = 0, .top = 0, .right = 0, .bottom = 0 };
    }

    if (!window.visible and x11.net_request_frame_extents != 0) {
        sendEventToWM(window, x11.net_request_frame_extents, 0, 0, 0, 0, 0);
        if (!waitForFrameExtents(window)) {
            return .{ .left = 0, .top = 0, .right = 0, .bottom = 0 };
        }
    }

    const display = x11.display orelse return .{ .left = 0, .top = 0, .right = 0, .bottom = 0 };
    const lib = &(x11.xlib orelse return .{ .left = 0, .top = 0, .right = 0, .bottom = 0 });
    var actual_type: x11.Atom = 0;
    var actual_format: c_int = 0;
    var item_count: c_ulong = 0;
    var bytes_after: c_ulong = 0;
    var data: ?[*]u8 = null;
    _ = lib.XGetWindowProperty(
        display,
        window.handle,
        x11.net_frame_extents,
        0,
        4,
        0,
        x11.XA_CARDINAL,
        &actual_type,
        &actual_format,
        &item_count,
        &bytes_after,
        &data,
    );
    defer {
        if (data) |ptr| _ = lib.XFree(@ptrCast(ptr));
    }

    if (data == null or actual_type != x11.XA_CARDINAL or actual_format != 32 or item_count != 4) {
        return .{ .left = 0, .top = 0, .right = 0, .bottom = 0 };
    }

    const extents: [*]c_ulong = @ptrCast(@alignCast(data.?));
    return .{
        .left = @intCast(extents[0]),
        .top = @intCast(extents[2]),
        .right = @intCast(extents[1]),
        .bottom = @intCast(extents[3]),
    };
}

pub fn getContentScale(handle: *anyopaque) ContentScale {
    _ = handle;
    return .{ .x_scale = x11.content_scale_x, .y_scale = x11.content_scale_y };
}

pub fn getOpacity(handle: *anyopaque) f32 {
    const window = native(handle);
    const lib = &(x11.xlib orelse return 1.0);
    if (x11.net_wm_cm_sx == 0 or lib.XGetSelectionOwner(window.display, x11.net_wm_cm_sx) == 0) {
        return 1.0;
    }

    var actual_type: x11.Atom = 0;
    var actual_format: c_int = 0;
    var item_count: c_ulong = 0;
    var bytes_after: c_ulong = 0;
    var data: ?[*]u8 = null;
    _ = lib.XGetWindowProperty(
        window.display,
        window.handle,
        x11.net_wm_window_opacity,
        0,
        1,
        0,
        x11.XA_CARDINAL,
        &actual_type,
        &actual_format,
        &item_count,
        &bytes_after,
        &data,
    );
    defer {
        if (data) |ptr| _ = lib.XFree(@ptrCast(ptr));
    }

    if (data == null or actual_type != x11.XA_CARDINAL or actual_format != 32 or item_count == 0) {
        return 1.0;
    }

    const value: [*]c_ulong = @ptrCast(@alignCast(data.?));
    return @floatCast(@as(f64, @floatFromInt(value[0])) / @as(f64, @floatFromInt(@as(c_ulong, 0xffffffff))));
}

pub fn setOpacity(handle: *anyopaque, opacity: f32) void {
    const window = native(handle);
    if (x11.xlib) |lib| {
        var value: c_ulong = @intFromFloat(0xffffffff * @as(f64, opacity));
        _ = lib.XChangeProperty(
            window.display,
            window.handle,
            x11.net_wm_window_opacity,
            x11.XA_CARDINAL,
            32,
            x11.PropModeReplace,
            @ptrCast(&value),
            1,
        );
    }
}

pub fn iconify(handle: *anyopaque) void {
    const window = native(handle);
    if (window.override_redirect) return;
    if (x11.xlib) |lib| {
        _ = lib.XIconifyWindow(window.display, window.handle, x11.screen);
        _ = lib.XFlush(window.display);
    }
}

pub fn restore(handle: *anyopaque) void {
    const window = native(handle);
    if (window.override_redirect) return;
    const lib = &(x11.xlib orelse return);

    if (getWindowState(window) == x11.IconicState) {
        _ = lib.XMapWindow(window.display, window.handle);
        _ = waitForVisibilityNotify(window);
    } else if (isWindowVisible(window) and
        x11.net_wm_state != 0 and
        x11.net_wm_state_maximized_vert != 0 and
        x11.net_wm_state_maximized_horz != 0)
    {
        sendEventToWM(
            window,
            x11.net_wm_state,
            0,
            @intCast(x11.net_wm_state_maximized_vert),
            @intCast(x11.net_wm_state_maximized_horz),
            1,
            0,
        );
    }

    _ = lib.XFlush(window.display);
}

pub fn maximize(handle: *anyopaque) void {
    const window = native(handle);
    if (x11.net_wm_state == 0 or
        x11.net_wm_state_maximized_vert == 0 or
        x11.net_wm_state_maximized_horz == 0)
    {
        return;
    }

    if (isWindowVisible(window)) {
        sendEventToWM(
            window,
            x11.net_wm_state,
            1,
            @intCast(x11.net_wm_state_maximized_vert),
            @intCast(x11.net_wm_state_maximized_horz),
            1,
            0,
        );
    } else {
        appendMissingNetWmStates(window, &.{
            x11.net_wm_state_maximized_vert,
            x11.net_wm_state_maximized_horz,
        });
    }

    if (x11.xlib) |lib| _ = lib.XFlush(window.display);
}

pub fn show(handle: *anyopaque) void {
    const window = native(handle);
    if (isWindowVisible(window)) return;
    window.visible = true;
    if (x11.xlib) |lib| {
        _ = lib.XMapWindow(window.display, window.handle);
        _ = waitForVisibilityNotify(window);
    }
}

pub fn hide(handle: *anyopaque) void {
    const window = native(handle);
    window.visible = false;
    if (x11.xlib) |lib| {
        _ = lib.XUnmapWindow(window.display, window.handle);
        _ = lib.XFlush(window.display);
    }
}

pub fn focus(handle: *anyopaque) void {
    const window = native(handle);
    if (x11.net_active_window != 0) {
        sendEventToWM(window, x11.net_active_window, 1, 0, 0, 0, 0);
    } else if (isWindowVisible(window)) {
        const lib = &(x11.xlib orelse return);
        _ = lib.XRaiseWindow(window.display, window.handle);
        _ = lib.XSetInputFocus(window.display, window.handle, x11.RevertToParent, x11.CurrentTime);
        _ = lib.XFlush(window.display);
    }
}

pub fn requestAttention(handle: *anyopaque) void {
    const window = native(handle);
    setNetWmState(window, x11.net_wm_state_demands_attention, true);
}

pub fn setMonitor(handle: *anyopaque, monitor: ?*anyopaque, pos: Pos, size: Size, refresh_rate: u32) void {
    const window = native(handle);
    const previous_monitor = window.monitor;

    if (previous_monitor == monitor) {
        window.x = pos.x;
        window.y = pos.y;
        window.width = size.width;
        window.height = size.height;

        if (monitor) |current| {
            if (monitor_module.window(current) == @as(*anyopaque, @ptrCast(window))) {
                acquireMonitor(window, current, size, refresh_rate);
            }
        } else {
            if (!window.resizable) updateNormalHints(window);
            if (x11.xlib) |lib| _ = lib.XMoveResizeWindow(window.display, window.handle, pos.x, pos.y, size.width, size.height);
        }

        if (x11.xlib) |lib| _ = lib.XFlush(window.display);
        return;
    }

    if (previous_monitor) |old_monitor| {
        setWindowDecorations(window, window.decorated);
        setWindowFloating(window, window.floating);
        releaseMonitor(window, old_monitor);
    }

    window.monitor = monitor;
    window.x = pos.x;
    window.y = pos.y;
    window.width = size.width;
    window.height = size.height;
    if (monitor != null) {
        if (!isWindowVisible(window)) {
            if (x11.xlib) |lib| {
                _ = lib.XMapRaised(window.display, window.handle);
                _ = waitForVisibilityNotify(window);
            }
            window.visible = true;
        }
        updateWindowMode(window);
        updateNormalHints(window);
        acquireMonitor(window, monitor.?, size, refresh_rate);
    } else {
        updateWindowMode(window);
        updateNormalHints(window);
        if (x11.xlib) |lib| _ = lib.XMoveResizeWindow(window.display, window.handle, pos.x, pos.y, size.width, size.height);
    }
    if (x11.xlib) |lib| _ = lib.XFlush(window.display);
}

pub fn setIcon(handle: *anyopaque, images: [*]const IconImage, count: usize) bool {
    const window = native(handle);
    const lib = &(x11.xlib orelse return false);
    if (count == 0) {
        _ = lib.XDeleteProperty(window.display, window.handle, x11.net_wm_icon);
        return true;
    }

    var long_count: usize = 0;
    for (images[0..count]) |image| long_count += 2 + image.width * image.height;
    const icon = std.heap.c_allocator.alloc(c_ulong, long_count) catch return false;
    defer std.heap.c_allocator.free(icon);

    var out: usize = 0;
    for (images[0..count]) |image| {
        icon[out] = image.width;
        icon[out + 1] = image.height;
        out += 2;

        const pixels = image.pixels[0 .. image.width * image.height * 4];
        var i: usize = 0;
        while (i < pixels.len) : (i += 4) {
            const red: c_ulong = pixels[i + 0];
            const green: c_ulong = pixels[i + 1];
            const blue: c_ulong = pixels[i + 2];
            const alpha: c_ulong = pixels[i + 3];
            icon[out] = (alpha << 24) | (red << 16) | (green << 8) | blue;
            out += 1;
        }
    }

    _ = lib.XChangeProperty(
        window.display,
        window.handle,
        x11.net_wm_icon,
        x11.XA_CARDINAL,
        32,
        x11.PropModeReplace,
        @ptrCast(icon.ptr),
        @intCast(icon.len),
    );
    return true;
}

fn getWindowState(window: *x11.WindowState) c_int {
    const lib = &(x11.xlib orelse return x11.NormalState);
    var actual_type: x11.Atom = 0;
    var actual_format: c_int = 0;
    var item_count: c_ulong = 0;
    var bytes_after: c_ulong = 0;
    var data: ?[*]u8 = null;
    _ = lib.XGetWindowProperty(
        window.display,
        window.handle,
        x11.wm_state,
        0,
        2,
        0,
        x11.wm_state,
        &actual_type,
        &actual_format,
        &item_count,
        &bytes_after,
        &data,
    );
    defer {
        if (data) |ptr| _ = lib.XFree(@ptrCast(ptr));
    }

    if (data == null or actual_type != x11.wm_state or actual_format != 32 or item_count < 1) return x11.NormalState;
    const values: [*]c_long = @ptrCast(@alignCast(data.?));
    return @intCast(values[0]);
}

fn isWindowFocused(window: *x11.WindowState) bool {
    const lib = &(x11.xlib orelse return false);
    var focused: x11.Window = 0;
    var state: c_int = 0;
    _ = lib.XGetInputFocus(window.display, &focused, &state);
    return focused == window.handle;
}

fn isWindowVisible(window: *x11.WindowState) bool {
    const lib = &(x11.xlib orelse return false);
    var attributes: x11.XWindowAttributes = .{};
    if (lib.XGetWindowAttributes(window.display, window.handle, &attributes) == 0) return false;
    return attributes.map_state == x11.IsViewable;
}

fn isWindowMaximized(window: *x11.WindowState) bool {
    if (x11.net_wm_state == 0 or x11.net_wm_state_maximized_vert == 0 or x11.net_wm_state_maximized_horz == 0) return false;

    const lib = &(x11.xlib orelse return false);
    var actual_type: x11.Atom = 0;
    var actual_format: c_int = 0;
    var item_count: c_ulong = 0;
    var bytes_after: c_ulong = 0;
    var data: ?[*]u8 = null;
    _ = lib.XGetWindowProperty(
        window.display,
        window.handle,
        x11.net_wm_state,
        0,
        std.math.maxInt(c_long),
        0,
        x11.XA_ATOM,
        &actual_type,
        &actual_format,
        &item_count,
        &bytes_after,
        &data,
    );
    defer {
        if (data) |ptr| _ = lib.XFree(@ptrCast(ptr));
    }

    if (data == null or actual_type != x11.XA_ATOM or actual_format != 32) return false;
    const states: [*]x11.Atom = @ptrCast(@alignCast(data.?));
    for (states[0..@intCast(item_count)]) |state| {
        if (state == x11.net_wm_state_maximized_vert or state == x11.net_wm_state_maximized_horz) return true;
    }
    return false;
}

fn appendMissingNetWmStates(window: *x11.WindowState, requested_states: []const x11.Atom) void {
    if (x11.net_wm_state == 0) return;
    const lib = &(x11.xlib orelse return);
    var actual_type: x11.Atom = 0;
    var actual_format: c_int = 0;
    var item_count: c_ulong = 0;
    var bytes_after: c_ulong = 0;
    var data: ?[*]u8 = null;
    _ = lib.XGetWindowProperty(
        window.display,
        window.handle,
        x11.net_wm_state,
        0,
        std.math.maxInt(c_long),
        0,
        x11.XA_ATOM,
        &actual_type,
        &actual_format,
        &item_count,
        &bytes_after,
        &data,
    );
    defer {
        if (data) |ptr| _ = lib.XFree(@ptrCast(ptr));
    }

    const states: []const x11.Atom = if (data != null and actual_type == x11.XA_ATOM and actual_format == 32)
        @as([*]x11.Atom, @ptrCast(@alignCast(data.?)))[0..@intCast(item_count)]
    else
        &.{};

    var missing: [8]x11.Atom = undefined;
    var missing_count: usize = 0;
    for (requested_states) |requested| {
        if (requested == 0) continue;
        var found = false;
        for (states) |state| {
            if (state == requested) {
                found = true;
                break;
            }
        }
        if (!found and missing_count < missing.len) {
            missing[missing_count] = requested;
            missing_count += 1;
        }
    }

    if (missing_count == 0) return;
    _ = lib.XChangeProperty(
        window.display,
        window.handle,
        x11.net_wm_state,
        x11.XA_ATOM,
        32,
        x11.PropModeAppend,
        @ptrCast(missing[0..missing_count].ptr),
        @intCast(missing_count),
    );
}

fn removeNetWmStates(window: *x11.WindowState, removed_states: []const x11.Atom) void {
    if (x11.net_wm_state == 0) return;
    const lib = &(x11.xlib orelse return);
    var actual_type: x11.Atom = 0;
    var actual_format: c_int = 0;
    var item_count: c_ulong = 0;
    var bytes_after: c_ulong = 0;
    var data: ?[*]u8 = null;
    _ = lib.XGetWindowProperty(
        window.display,
        window.handle,
        x11.net_wm_state,
        0,
        std.math.maxInt(c_long),
        0,
        x11.XA_ATOM,
        &actual_type,
        &actual_format,
        &item_count,
        &bytes_after,
        &data,
    );
    defer {
        if (data) |ptr| _ = lib.XFree(@ptrCast(ptr));
    }

    if (data == null or actual_type != x11.XA_ATOM or actual_format != 32) return;
    const states: [*]x11.Atom = @ptrCast(@alignCast(data.?));
    var write_index: usize = 0;
    var changed = false;
    for (states[0..@intCast(item_count)]) |state| {
        var remove = false;
        for (removed_states) |removed| {
            if (state == removed) {
                remove = true;
                break;
            }
        }
        if (remove) {
            changed = true;
        } else {
            states[write_index] = state;
            write_index += 1;
        }
    }

    if (!changed) return;
    _ = lib.XChangeProperty(
        window.display,
        window.handle,
        x11.net_wm_state,
        x11.XA_ATOM,
        32,
        x11.PropModeReplace,
        @ptrCast(states),
        @intCast(write_index),
    );
}

fn setWindowFloating(window: *x11.WindowState, enabled: bool) void {
    if (x11.net_wm_state == 0 or x11.net_wm_state_above == 0) return;

    if (isWindowVisible(window)) {
        sendEventToWM(window, x11.net_wm_state, if (enabled) 1 else 0, @intCast(x11.net_wm_state_above), 0, 1, 0);
    } else if (enabled) {
        appendMissingNetWmStates(window, &.{x11.net_wm_state_above});
    } else {
        removeNetWmStates(window, &.{x11.net_wm_state_above});
    }

    if (x11.xlib) |lib| _ = lib.XFlush(window.display);
}

fn isWindowHovered(window: *x11.WindowState) bool {
    const lib = &(x11.xlib orelse return false);
    var current = x11.root;
    while (current != 0) {
        var root_return: x11.Window = 0;
        var child_return: x11.Window = 0;
        var root_x: c_int = 0;
        var root_y: c_int = 0;
        var child_x: c_int = 0;
        var child_y: c_int = 0;
        var mask: c_uint = 0;

        grabErrorHandler();
        const result = lib.XQueryPointer(
            window.display,
            current,
            &root_return,
            &child_return,
            &root_x,
            &root_y,
            &child_x,
            &child_y,
            &mask,
        );
        releaseErrorHandler();

        if (x11.error_code == x11.BadWindow) {
            current = x11.root;
        } else if (result == 0) {
            return false;
        } else if (child_return == window.handle) {
            return true;
        } else {
            current = child_return;
        }
    }

    return false;
}

fn handlePropertyNotify(window: *x11.WindowState, event: *const x11.XPropertyEvent) void {
    if (event.state != x11.PropertyNewValue) return;

    const cb = callbacks();
    if (event.atom == x11.wm_state) {
        const state = getWindowState(window);
        if (state != x11.IconicState and state != x11.NormalState) return;

        const iconified = state == x11.IconicState;
        if (window.iconified != iconified) {
            if (window.monitor) |monitor| {
                if (iconified) {
                    releaseMonitor(window, monitor);
                } else {
                    acquireMonitor(window, monitor, .{ .width = window.width, .height = window.height }, 0);
                }
            }

            window.iconified = iconified;
            cb.iconify(window.callback_id, iconified);
        }
    } else if (event.atom == x11.net_wm_state) {
        const maximized = isWindowMaximized(window);
        if (window.maximized != maximized) {
            window.maximized = maximized;
            cb.maximize(window.callback_id, maximized);
        }
    }
}

pub fn getAttribute(handle: *anyopaque, attribute: c_int) bool {
    const window = native(handle);
    return switch (attribute) {
        0 => isWindowFocused(window),
        1 => getWindowState(window) == x11.IconicState,
        2 => isWindowMaximized(window),
        3 => isWindowHovered(window),
        4 => isWindowVisible(window),
        5 => window.resizable,
        6 => window.decorated,
        7 => window.auto_iconify,
        8 => window.floating,
        11 => window.mouse_passthrough,
        else => false,
    };
}

pub fn setAttribute(handle: *anyopaque, attribute: c_int, value: bool) void {
    const window = native(handle);
    switch (attribute) {
        5 => window.resizable = value,
        6 => window.decorated = value,
        8 => {
            window.floating = value;
            setWindowFloating(window, value);
        },
        11 => {
            window.mouse_passthrough = value;
            setMousePassthrough(window, value);
        },
        else => {},
    }
    if (attribute == 6) setWindowDecorations(window, value);
}

pub fn setUserPointer(handle: *anyopaque, pointer: ?*anyopaque) void {
    native(handle).user_pointer = pointer;
}

pub fn getUserPointer(handle: *anyopaque) ?*anyopaque {
    return native(handle).user_pointer;
}

pub fn getCursorPos(handle: *anyopaque) Pos {
    const window = native(handle);
    if (window.cursor_mode == 2) {
        return .{ .x = @intFromFloat(window.virtual_cursor_x), .y = @intFromFloat(window.virtual_cursor_y) };
    }

    var root_return: x11.Window = 0;
    var child_return: x11.Window = 0;
    var root_x: c_int = 0;
    var root_y: c_int = 0;
    var win_x: c_int = 0;
    var win_y: c_int = 0;
    var mask: c_uint = 0;
    if (x11.xlib) |lib| {
        if (lib.XQueryPointer(window.display, window.handle, &root_return, &child_return, &root_x, &root_y, &win_x, &win_y, &mask) != 0) {
            return .{ .x = win_x, .y = win_y };
        }
    }
    return .{ .x = 0, .y = 0 };
}

pub fn setCursorPos(handle: *anyopaque, x: f64, y: f64) void {
    const window = native(handle);
    window.warp_cursor_pos_x = @intFromFloat(x);
    window.warp_cursor_pos_y = @intFromFloat(y);
    if (x11.xlib) |lib| {
        _ = lib.XWarpPointer(window.display, 0, window.handle, 0, 0, 0, 0, @intFromFloat(x), @intFromFloat(y));
        _ = lib.XFlush(window.display);
    }
}

pub fn setCursor(handle: *anyopaque, cursor: ?*anyopaque) void {
    const window = native(handle);
    window.cursor = cursor_module.nativeCursor(cursor);
    updateCursor(window);
}

pub fn setInputMode(handle: *anyopaque, mode: c_int, value: c_int) void {
    const window = native(handle);
    if (mode == 1) {
        window.raw_mouse_motion = value != 0;
        if (disabled_cursor_window == window) setRawMouseMotion(window, value != 0);
        return;
    }
    if (mode == 0) {
        window.cursor_mode = value;
        if (isWindowFocused(window)) {
            if (value == 2) {
                const pos = getCursorPos(handle);
                window.restore_cursor_x = @floatFromInt(pos.x);
                window.restore_cursor_y = @floatFromInt(pos.y);
                window.virtual_cursor_x = @floatFromInt(pos.x);
                window.virtual_cursor_y = @floatFromInt(pos.y);

                const size = getSize(handle);
                setCursorPos(handle, @floatFromInt(size.width / 2), @floatFromInt(size.height / 2));

                if (window.raw_mouse_motion) setRawMouseMotion(window, true);
            } else if (disabled_cursor_window == window) {
                if (window.raw_mouse_motion) setRawMouseMotion(window, false);
            }

            if (value == 2 or value == 3) {
                captureCursor(window);
            } else {
                releaseCursor(window);
            }

            if (value == 2) {
                disabled_cursor_window = window;
            } else if (disabled_cursor_window == window) {
                disabled_cursor_window = null;
                setCursorPos(handle, window.restore_cursor_x, window.restore_cursor_y);
            }
        }
        updateCursor(window);
        if (x11.xlib) |lib| _ = lib.XFlush(window.display);
    }
}

pub fn pollDisabledCursor() void {
    const window = disabled_cursor_window orelse return;
    const size = getSize(@ptrCast(window));
    const center_x: i32 = @intCast(size.width / 2);
    const center_y: i32 = @intCast(size.height / 2);

    if (window.last_cursor_pos_x != center_x or window.last_cursor_pos_y != center_y) {
        setCursorPos(@ptrCast(window), @floatFromInt(center_x), @floatFromInt(center_y));
    }
}

pub fn setClipboardString(value: [*:0]const u8) void {
    setSelectionString(x11.clipboard, &clipboard_buffer, value);
}

pub fn getClipboardString() ?[*:0]const u8 {
    return getSelectionString(x11.clipboard, &clipboard_buffer);
}

pub fn setX11SelectionString(value: [*:0]const u8) void {
    setSelectionString(x11.primary, &primary_selection_buffer, value);
}

pub fn getX11SelectionString() ?[*:0]const u8 {
    return getSelectionString(x11.primary, &primary_selection_buffer);
}

fn setSelectionString(selection: x11.Atom, storage: *?[:0]u8, value: [*:0]const u8) void {
    const display = x11.display orelse return;
    const lib = &(x11.xlib orelse return);
    const copy = std.heap.c_allocator.dupeZ(u8, std.mem.span(value)) catch null;
    if (storage.*) |old| std.heap.c_allocator.free(old);
    storage.* = copy;

    _ = lib.XSetSelectionOwner(display, selection, helper_window, x11.CurrentTime);
    if (lib.XGetSelectionOwner(display, selection) != helper_window) {
        if (storage.*) |old| std.heap.c_allocator.free(old);
        storage.* = null;
    }
}

fn getSelectionString(selection: x11.Atom, storage: *?[:0]u8) ?[*:0]const u8 {
    const display = x11.display orelse return null;
    const lib = &(x11.xlib orelse return null);
    if (lib.XGetSelectionOwner(display, selection) == helper_window) {
        return if (storage.*) |buffer| buffer.ptr else null;
    }

    if (storage.*) |old| std.heap.c_allocator.free(old);
    storage.* = null;

    const targets = [_]x11.Atom{ x11.utf8_string, x11.XA_STRING };
    for (targets) |target| {
        lib.XConvertSelection(display, selection, target, x11.glfw_selection, helper_window, x11.CurrentTime);
        const notification = waitForSelectionNotify(selection) orelse continue;
        if (notification.property == 0) continue;

        var actual_type: x11.Atom = 0;
        var actual_format: c_int = 0;
        var item_count: c_ulong = 0;
        var bytes_after: c_ulong = 0;
        var data: ?[*]u8 = null;
        _ = lib.XGetWindowProperty(
            display,
            notification.requestor,
            notification.property,
            0,
            std.math.maxInt(c_long),
            1,
            x11.AnyPropertyType,
            &actual_type,
            &actual_format,
            &item_count,
            &bytes_after,
            &data,
        );
        defer {
            if (data) |ptr| _ = lib.XFree(@ptrCast(ptr));
        }

        if (actual_type == x11.incr) {
            storage.* = readIncrementalSelection(&notification, target);
        } else if (data != null and actual_format == 8 and actual_type == target) {
            const bytes = data.?[0..@intCast(item_count)];
            storage.* = if (target == x11.XA_STRING)
                latin1ToUtf8(bytes)
            else
                std.heap.c_allocator.dupeZ(u8, bytes) catch null;
        }
        if (storage.*) |buffer| return buffer.ptr;
    }

    return null;
}

pub fn handleEvent(incoming: *const x11.XEvent) void {
    var event = incoming.*;
    var saved_keycode: c_uint = 0;
    var filtered = false;
    if (event.type == x11.KeyPress or event.type == x11.KeyRelease) {
        saved_keycode = event.xkey.keycode;
    }
    if (x11.xlib) |lib| filtered = lib.XFilterEvent(&event, 0) != 0;
    if (event.type == x11.KeyPress or event.type == x11.KeyRelease) {
        event.xkey.keycode = saved_keycode;
    }

    if (monitor_module.handleEvent(&event)) return;
    if (input.handleEvent(&event)) return;

    if (event.type == x11.GenericEvent) {
        handleGenericEvent(&event);
        return;
    }
    if (event.type == x11.SelectionRequest) {
        handleSelectionRequest(&event.xselectionrequest);
        return;
    }
    if (event.type == x11.SelectionClear) {
        return;
    }

    const window = windowFromXid(event.xany.window) orelse return;
    const cb = callbacks_ orelse return;
    switch (event.type) {
        x11.ClientMessage => {
            if (filtered) return;
            if (event.xclient.message_type == 0) return;

            if (event.xclient.message_type == x11.wm_protocols) {
                if (@as(x11.Atom, @intCast(event.xclient.data.l[0])) == x11.wm_delete_window) {
                    window.should_close = true;
                    cb.close(window.callback_id);
                } else if (@as(x11.Atom, @intCast(event.xclient.data.l[0])) == x11.net_wm_ping) {
                    var reply = event;
                    reply.xclient.window = x11.root;
                    if (x11.xlib) |lib| {
                        _ = lib.XSendEvent(
                            window.display,
                            x11.root,
                            0,
                            x11.SubstructureNotifyMask | x11.SubstructureRedirectMask,
                            &reply,
                        );
                    }
                }
            } else if (event.xclient.message_type == x11.xdnd_enter) {
                handleXdndEnter(window, &event.xclient);
            } else if (event.xclient.message_type == x11.xdnd_position) {
                handleXdndPosition(window, &event.xclient);
            } else if (event.xclient.message_type == x11.xdnd_drop) {
                handleXdndDrop(window, &event.xclient);
            }
        },
        x11.SelectionNotify => handleSelectionNotify(window, &event.xselection),
        x11.ReparentNotify => {
            window.parent = event.xreparent.parent;
        },
        x11.ConfigureNotify => {
            const cfg = event.xconfigure;
            var xpos = cfg.x;
            var ypos = cfg.y;
            if (cfg.send_event == 0 and window.parent != x11.root) {
                var child: x11.Window = 0;
                if (x11.xlib) |lib| {
                    grabErrorHandler();
                    _ = lib.XTranslateCoordinates(
                        window.display,
                        window.parent,
                        x11.root,
                        xpos,
                        ypos,
                        &xpos,
                        &ypos,
                        &child,
                    );
                    releaseErrorHandler();
                    if (x11.error_code == x11.BadWindow) return;
                }
            }

            if (window.x != xpos or window.y != ypos) {
                window.x = xpos;
                window.y = ypos;
                cb.pos(window.callback_id, xpos, ypos);
            }
            if (window.width != @as(u32, @intCast(cfg.width)) or window.height != @as(u32, @intCast(cfg.height))) {
                window.width = @intCast(cfg.width);
                window.height = @intCast(cfg.height);
                cb.size(window.callback_id, window.width, window.height);
                cb.framebuffer_size(window.callback_id, window.width, window.height);
            }
        },
        x11.FocusIn => handleFocus(window, &event.xfocus, true),
        x11.FocusOut => handleFocus(window, &event.xfocus, false),
        x11.Expose => cb.refresh(window.callback_id),
        x11.MapNotify => {
            window.visible = true;
        },
        x11.UnmapNotify => {
            window.visible = false;
        },
        x11.PropertyNotify => handlePropertyNotify(window, &event.xproperty),
        x11.EnterNotify => {
            if (window.cursor_mode == 1) updateCursor(window);
            window.last_cursor_pos_x = event.xcrossing.x;
            window.last_cursor_pos_y = event.xcrossing.y;
            cb.cursor_enter(window.callback_id, true);
            cb.cursor_pos(window.callback_id, @floatFromInt(event.xcrossing.x), @floatFromInt(event.xcrossing.y));
        },
        x11.LeaveNotify => cb.cursor_enter(window.callback_id, false),
        x11.MotionNotify => {
            const x = event.xmotion.x;
            const y = event.xmotion.y;
            if (x != window.warp_cursor_pos_x or y != window.warp_cursor_pos_y) {
                if (window.cursor_mode == 2) {
                    if (disabled_cursor_window != window or window.raw_mouse_motion) return;

                    const dx = x - window.last_cursor_pos_x;
                    const dy = y - window.last_cursor_pos_y;
                    window.virtual_cursor_x += @floatFromInt(dx);
                    window.virtual_cursor_y += @floatFromInt(dy);
                    cb.cursor_pos(window.callback_id, window.virtual_cursor_x, window.virtual_cursor_y);
                } else {
                    cb.cursor_pos(window.callback_id, @floatFromInt(x), @floatFromInt(y));
                }
            }
            window.last_cursor_pos_x = x;
            window.last_cursor_pos_y = y;
        },
        x11.ButtonPress, x11.ButtonRelease => handleButton(window, &event.xbutton, event.type == x11.ButtonPress),
        x11.KeyPress => handleKey(window, &event.xkey, true, filtered),
        x11.KeyRelease => {
            if (!isKeyRepeatRelease(&event.xkey)) handleKey(window, &event.xkey, false, filtered);
        },
        else => {},
    }
}

pub fn native(handle: *anyopaque) *x11.WindowState {
    return @ptrCast(@alignCast(handle));
}

fn callbacks() EventCallbacks {
    return callbacks_.?;
}

fn handleButton(window: *x11.WindowState, event: *const x11.XButtonEvent, pressed: bool) void {
    const cb = callbacks();
    const mods = translateMods(event.state);
    if (event.button >= x11.Button4 and event.button <= x11.Button7) {
        if (pressed) switch (event.button) {
            x11.Button4 => cb.scroll(window.callback_id, 0.0, 1.0),
            x11.Button5 => cb.scroll(window.callback_id, 0.0, -1.0),
            x11.Button6 => cb.scroll(window.callback_id, 1.0, 0.0),
            x11.Button7 => cb.scroll(window.callback_id, -1.0, 0.0),
            else => {},
        };
        return;
    }

    const button: c_int = switch (event.button) {
        x11.Button1 => 0,
        x11.Button2 => 2,
        x11.Button3 => 1,
        else => @as(c_int, @intCast(event.button - x11.Button1 - 4)),
    };
    cb.mouse_button(window.callback_id, button, if (pressed) 1 else 0, @bitCast(mods));
}

fn handleFocus(window: *x11.WindowState, event: *const x11.XFocusChangeEvent, focused: bool) void {
    if (event.mode == x11.NotifyGrab or event.mode == x11.NotifyUngrab) return;

    if (focused) {
        if (window.cursor_mode == 2 or window.cursor_mode == 3) {
            captureCursor(window);
            if (window.cursor_mode == 2 and window.raw_mouse_motion) setRawMouseMotion(window, true);
        }

        if (window.ic != null) {
            if (x11.xlib) |lib| lib.XSetICFocus(window.ic);
        }
    } else {
        if (window.cursor_mode == 2 or window.cursor_mode == 3) {
            if (window.cursor_mode == 2 and window.raw_mouse_motion) setRawMouseMotion(window, false);
            releaseCursor(window);
        }

        if (window.ic != null) {
            if (x11.xlib) |lib| lib.XUnsetICFocus(window.ic);
        }

        if (window.monitor != null and window.auto_iconify) {
            iconify(@ptrCast(window));
        }
    }

    callbacks().focus(window.callback_id, focused);
}

fn handleKey(window: *x11.WindowState, event: *const x11.XKeyEvent, pressed: bool, filtered: bool) void {
    var mutable_event = event.*;
    var keysym: x11.KeySym = 0;
    var scratch: [1]u8 = undefined;
    const key = input.translateScancode(event.keycode);
    const scancode: c_int = @intCast(event.keycode);
    const mods: u8 = @bitCast(translateMods(event.state));

    const lib = &(x11.xlib orelse return);

    if (pressed and window.ic != null) {
        const keycode_index: usize = if (event.keycode < window.key_press_times.len) @intCast(event.keycode) else 0;
        const previous = window.key_press_times[keycode_index];
        const diff = event.time -% previous;
        if (diff == event.time or (diff > 0 and diff < (@as(x11.Time, 1) << 31))) {
            if (event.keycode != 0) {
                callbacks().key(window.callback_id, key, scancode, 1, mods);
            }
            window.key_press_times[keycode_index] = event.time;
        }

        if (!filtered) {
            emitUtf8LookupChars(window, &mutable_event, mods);
        }
        return;
    }

    _ = lib.XLookupString(&mutable_event, &scratch, 0, &keysym, null);

    callbacks().key(window.callback_id, key, scancode, if (pressed) 1 else 0, mods);

    if (pressed and !filtered) {
        if (xkb_unicode.keySymToUnicode(keysym)) |codepoint| emitChar(window, codepoint, mods);
    }
}

fn emitUtf8LookupChars(window: *x11.WindowState, event: *x11.XKeyEvent, mods: u8) void {
    const lib = &(x11.xlib orelse return);
    var status: x11.Status = 0;
    var stack_buffer: [100]u8 = undefined;

    var count = lib.Xutf8LookupString(window.ic, event, &stack_buffer, stack_buffer.len - 1, null, &status);
    if (status == x11.XBufferOverflow) {
        if (count <= 0) return;
        const heap_buffer = std.heap.c_allocator.alloc(u8, @as(usize, @intCast(count)) + 1) catch return;
        defer std.heap.c_allocator.free(heap_buffer);
        count = lib.Xutf8LookupString(window.ic, event, heap_buffer.ptr, count, null, &status);
        if (status == x11.XLookupChars or status == x11.XLookupBoth) {
            emitUtf8Chars(window, heap_buffer[0..@intCast(count)], mods);
        }
        return;
    }

    if (status == x11.XLookupChars or status == x11.XLookupBoth) {
        emitUtf8Chars(window, stack_buffer[0..@intCast(count)], mods);
    }
}

fn emitUtf8Chars(window: *x11.WindowState, bytes: []const u8, mods: u8) void {
    const view = std.unicode.Utf8View.init(bytes) catch return;
    var iter = view.iterator();
    while (iter.nextCodepoint()) |codepoint| emitChar(window, codepoint, mods);
}

fn emitChar(window: *x11.WindowState, codepoint: u21, mods: u8) void {
    callbacks().char(window.callback_id, codepoint);
    callbacks().char_mods(window.callback_id, codepoint, mods);
}

fn handleGenericEvent(event: *const x11.XEvent) void {
    if (!x11.xi_available) return;
    const window = disabled_cursor_window orelse return;
    if (!window.raw_mouse_motion) return;
    var cookie = event.xcookie;
    if (cookie.extension != x11.xi_major_opcode) return;
    const lib = &(x11.xlib orelse return);
    if (lib.XGetEventData(window.display, &cookie) == 0) return;
    defer lib.XFreeEventData(window.display, &cookie);

    if (cookie.evtype != xi_raw_motion) return;
    const raw: *XIRawEvent = @ptrCast(@alignCast(cookie.data orelse return));
    if (raw.valuators.mask_len == 0) return;

    var values = raw.raw_values;
    var x_pos = window.virtual_cursor_x;
    var y_pos = window.virtual_cursor_y;

    if (xiMaskIsSet(raw.valuators.mask, 0)) {
        x_pos += values[0];
        values += 1;
    }

    if (xiMaskIsSet(raw.valuators.mask, 1)) {
        y_pos += values[0];
    }

    window.virtual_cursor_x = x_pos;
    window.virtual_cursor_y = y_pos;
    if (callbacks_) |cb| cb.cursor_pos(window.callback_id, x_pos, y_pos);
}

fn handleSelectionRequest(request: *const x11.XSelectionRequestEvent) void {
    var reply = std.mem.zeroes(x11.XEvent);
    reply.xselection = .{
        .type = x11.SelectionNotify,
        .serial = 0,
        .send_event = 1,
        .display = request.display,
        .requestor = request.requestor,
        .selection = request.selection,
        .target = request.target,
        .property = writeSelectionTarget(request),
        .time = request.time,
    };

    if (x11.xlib) |lib| {
        if (request.display) |display| {
            _ = lib.XSendEvent(display, request.requestor, 0, 0, &reply);
            _ = lib.XFlush(display);
        }
    }
}

fn writeSelectionTarget(request: *const x11.XSelectionRequestEvent) x11.Atom {
    const buffer = selectionBuffer(request.selection) orelse return 0;
    const lib = &(x11.xlib orelse return 0);
    const display = request.display orelse return 0;
    if (request.property == 0) return 0;

    if (request.target == x11.targets) {
        const targets = [_]x11.Atom{ x11.targets, x11.multiple, x11.utf8_string, x11.XA_STRING };
        _ = lib.XChangeProperty(
            display,
            request.requestor,
            request.property,
            x11.XA_ATOM,
            32,
            x11.PropModeReplace,
            @ptrCast(&targets),
            targets.len,
        );
        return request.property;
    }

    if (request.target == x11.multiple) {
        var actual_type: x11.Atom = 0;
        var actual_format: c_int = 0;
        var item_count: c_ulong = 0;
        var bytes_after: c_ulong = 0;
        var data: ?[*]u8 = null;
        _ = lib.XGetWindowProperty(
            display,
            request.requestor,
            request.property,
            0,
            std.math.maxInt(c_long),
            0,
            x11.atom_pair,
            &actual_type,
            &actual_format,
            &item_count,
            &bytes_after,
            &data,
        );
        defer {
            if (data) |ptr| _ = lib.XFree(@ptrCast(ptr));
        }

        if (data == null or actual_type != x11.atom_pair or actual_format != 32) return 0;
        const target_pairs: [*]x11.Atom = @ptrCast(@alignCast(data.?));
        var index: usize = 0;
        while (index + 1 < item_count) : (index += 2) {
            const target = target_pairs[index];
            const property = target_pairs[index + 1];
            if (target == x11.utf8_string or target == x11.XA_STRING) {
                writeStringProperty(display, request.requestor, property, target, buffer);
            } else if (target == x11.save_targets) {
                writeEmptyProperty(display, request.requestor, property);
            } else {
                target_pairs[index + 1] = 0;
            }
        }

        _ = lib.XChangeProperty(
            display,
            request.requestor,
            request.property,
            x11.atom_pair,
            32,
            x11.PropModeReplace,
            @ptrCast(target_pairs),
            @intCast(item_count),
        );
        return request.property;
    }

    if (request.target == x11.save_targets) {
        writeEmptyProperty(display, request.requestor, request.property);
        return request.property;
    }

    if (request.target == x11.utf8_string or request.target == x11.XA_STRING) {
        writeStringProperty(display, request.requestor, request.property, request.target, buffer);
        return request.property;
    }

    return 0;
}

fn selectionBuffer(selection: x11.Atom) ?[:0]u8 {
    if (selection == x11.primary) return primary_selection_buffer;
    return clipboard_buffer;
}

fn writeStringProperty(display: *x11.Display, requestor: x11.Window, property: x11.Atom, target: x11.Atom, buffer: [:0]const u8) void {
    const lib = &(x11.xlib orelse return);
    const bytes = std.mem.sliceTo(buffer, 0);
    _ = lib.XChangeProperty(
        display,
        requestor,
        property,
        target,
        8,
        x11.PropModeReplace,
        bytes.ptr,
        @intCast(bytes.len),
    );
}

fn writeEmptyProperty(display: *x11.Display, requestor: x11.Window, property: x11.Atom) void {
    const lib = &(x11.xlib orelse return);
    _ = lib.XChangeProperty(
        display,
        requestor,
        property,
        x11.null_atom,
        32,
        x11.PropModeReplace,
        null,
        0,
    );
}

fn pushSelectionToManager() void {
    const display = x11.display orelse return;
    const lib = &(x11.xlib orelse return);
    if (helper_window == 0) return;

    _ = lib.XConvertSelection(
        display,
        x11.clipboard_manager,
        x11.save_targets,
        0,
        helper_window,
        x11.CurrentTime,
    );

    while (true) {
        while (lib.XPending(display) > 0) {
            var event: x11.XEvent = undefined;
            _ = lib.XNextEvent(display, &event);
            switch (event.type) {
                x11.SelectionRequest => handleSelectionRequest(&event.xselectionrequest),
                x11.SelectionNotify => {
                    if (event.xselection.target == x11.save_targets) return;
                    handleEvent(&event);
                },
                else => handleEvent(&event),
            }
        }
        _ = waitForX11Event(null);
    }
}

fn handleXdndEnter(window: *x11.WindowState, event: *const x11.XClientMessageEvent) void {
    const display = x11.display orelse return;
    const lib = &(x11.xlib orelse return);

    window.xdnd_source = @intCast(event.data.l[0]);
    window.xdnd_version = event.data.l[1] >> 24;
    window.xdnd_format = 0;

    if (window.xdnd_version > xdnd_version) return;

    if ((event.data.l[1] & 1) != 0) {
        var actual_type: x11.Atom = 0;
        var actual_format: c_int = 0;
        var item_count: c_ulong = 0;
        var bytes_after: c_ulong = 0;
        var data: ?[*]u8 = null;
        _ = lib.XGetWindowProperty(
            display,
            window.xdnd_source,
            x11.xdnd_type_list,
            0,
            std.math.maxInt(c_long),
            0,
            x11.XA_ATOM,
            &actual_type,
            &actual_format,
            &item_count,
            &bytes_after,
            &data,
        );
        defer {
            if (data) |ptr| _ = lib.XFree(@ptrCast(ptr));
        }

        if (actual_type == x11.XA_ATOM and actual_format == 32) {
            if (data) |ptr| {
                const formats: [*]x11.Atom = @ptrCast(@alignCast(ptr));
                for (formats[0..@intCast(item_count)]) |format| {
                    if (format == x11.text_uri_list) {
                        window.xdnd_format = x11.text_uri_list;
                        break;
                    }
                }
            }
        }
    } else {
        for (event.data.l[2..5]) |format| {
            if (@as(x11.Atom, @intCast(format)) == x11.text_uri_list) {
                window.xdnd_format = x11.text_uri_list;
                break;
            }
        }
    }
}

fn handleXdndPosition(window: *x11.WindowState, event: *const x11.XClientMessageEvent) void {
    const display = x11.display orelse return;
    const lib = &(x11.xlib orelse return);
    if (window.xdnd_version > xdnd_version) return;

    const packed_position = event.data.l[2];
    const x_abs: c_int = @intCast((packed_position >> 16) & 0xffff);
    const y_abs: c_int = @intCast(packed_position & 0xffff);
    var x_pos: c_int = 0;
    var y_pos: c_int = 0;
    var child: x11.Window = 0;
    _ = lib.XTranslateCoordinates(display, x11.root, window.handle, x_abs, y_abs, &x_pos, &y_pos, &child);
    callbacks().cursor_pos(window.callback_id, @floatFromInt(x_pos), @floatFromInt(y_pos));
    sendXdndStatus(window, window.xdnd_format != 0);
}

fn handleXdndDrop(window: *x11.WindowState, event: *const x11.XClientMessageEvent) void {
    const display = x11.display orelse return;
    const lib = &(x11.xlib orelse return);
    if (window.xdnd_version > xdnd_version) return;

    if (window.xdnd_format != 0) {
        const time: x11.Time = if (window.xdnd_version >= 1) @intCast(event.data.l[2]) else x11.CurrentTime;
        _ = lib.XConvertSelection(
            display,
            x11.xdnd_selection,
            window.xdnd_format,
            x11.xdnd_selection,
            window.handle,
            time,
        );
    } else if (window.xdnd_version >= 2) {
        sendXdndFinished(window, false);
    }
}

fn handleSelectionNotify(window: *x11.WindowState, event: *const x11.XSelectionEvent) void {
    const display = x11.display orelse return;
    const lib = &(x11.xlib orelse return);
    if (event.property != x11.xdnd_selection) return;

    var actual_type: x11.Atom = 0;
    var actual_format: c_int = 0;
    var item_count: c_ulong = 0;
    var bytes_after: c_ulong = 0;
    var data: ?[*]u8 = null;
    _ = lib.XGetWindowProperty(
        display,
        event.requestor,
        event.property,
        0,
        std.math.maxInt(c_long),
        0,
        event.target,
        &actual_type,
        &actual_format,
        &item_count,
        &bytes_after,
        &data,
    );
    defer {
        if (data) |ptr| _ = lib.XFree(@ptrCast(ptr));
    }

    var accepted = false;
    if (data != null and actual_format == 8 and actual_type == event.target and item_count > 0) {
        accepted = dispatchUriDrop(window, data.?[0..@intCast(item_count)]);
    }

    if (window.xdnd_version >= 2) sendXdndFinished(window, accepted);
}

fn sendXdndStatus(window: *x11.WindowState, accepted: bool) void {
    const lib = &(x11.xlib orelse return);
    var reply = std.mem.zeroes(x11.XEvent);
    reply.xclient.type = x11.ClientMessage;
    reply.xclient.display = window.display;
    reply.xclient.window = window.xdnd_source;
    reply.xclient.message_type = x11.xdnd_status;
    reply.xclient.format = 32;
    reply.xclient.data.l[0] = @intCast(window.handle);
    reply.xclient.data.l[1] = if (accepted) 1 else 0;
    reply.xclient.data.l[2] = 0;
    reply.xclient.data.l[3] = 0;
    reply.xclient.data.l[4] = if (accepted and window.xdnd_version >= 2) @intCast(x11.xdnd_action_copy) else 0;
    _ = lib.XSendEvent(window.display, window.xdnd_source, 0, x11.NoEventMask, &reply);
    _ = lib.XFlush(window.display);
}

fn sendXdndFinished(window: *x11.WindowState, accepted: bool) void {
    const lib = &(x11.xlib orelse return);
    var reply = std.mem.zeroes(x11.XEvent);
    reply.xclient.type = x11.ClientMessage;
    reply.xclient.display = window.display;
    reply.xclient.window = window.xdnd_source;
    reply.xclient.message_type = x11.xdnd_finished;
    reply.xclient.format = 32;
    reply.xclient.data.l[0] = @intCast(window.handle);
    reply.xclient.data.l[1] = if (accepted) 1 else 0;
    reply.xclient.data.l[2] = if (accepted) @intCast(x11.xdnd_action_copy) else 0;
    _ = lib.XSendEvent(window.display, window.xdnd_source, 0, x11.NoEventMask, &reply);
    _ = lib.XFlush(window.display);
}

fn updateWindowMode(window: *x11.WindowState) void {
    if (window.monitor) |monitor| {
        if (monitor_module.xineramaAvailable() and x11.net_wm_fullscreen_monitors != 0) {
            const index = monitor_module.fullscreenIndex(monitor);
            sendEventToWM(
                window,
                x11.net_wm_fullscreen_monitors,
                @intCast(index),
                @intCast(index),
                @intCast(index),
                @intCast(index),
                0,
            );
        }

        if (x11.net_wm_state != 0 and x11.net_wm_state_fullscreen != 0) {
            setNetWmState(window, x11.net_wm_state_fullscreen, true);
        } else {
            setOverrideRedirect(window, true);
        }

        setCompositorBypass(window, true);
    } else {
        if (monitor_module.xineramaAvailable() and x11.net_wm_fullscreen_monitors != 0) {
            if (x11.xlib) |lib| _ = lib.XDeleteProperty(window.display, window.handle, x11.net_wm_fullscreen_monitors);
        }

        if (x11.net_wm_state != 0 and x11.net_wm_state_fullscreen != 0) {
            setNetWmState(window, x11.net_wm_state_fullscreen, false);
        } else {
            setOverrideRedirect(window, false);
        }

        setCompositorBypass(window, false);
    }
}

fn setOverrideRedirect(window: *x11.WindowState, enabled: bool) void {
    const lib = &(x11.xlib orelse return);
    var attributes = x11.XSetWindowAttributes{
        .override_redirect = if (enabled) 1 else 0,
    };
    _ = lib.XChangeWindowAttributes(window.display, window.handle, x11.CWOverrideRedirect, &attributes);
    window.override_redirect = enabled;
}

fn setCompositorBypass(window: *x11.WindowState, enabled: bool) void {
    if (window.transparent) return;
    if (x11.net_wm_bypass_compositor == 0) return;
    const lib = &(x11.xlib orelse return);
    if (enabled) {
        var value: c_ulong = 1;
        _ = lib.XChangeProperty(
            window.display,
            window.handle,
            x11.net_wm_bypass_compositor,
            x11.XA_CARDINAL,
            32,
            x11.PropModeReplace,
            @ptrCast(&value),
            1,
        );
    } else {
        _ = lib.XDeleteProperty(window.display, window.handle, x11.net_wm_bypass_compositor);
    }
}

fn acquireMonitor(window: *x11.WindowState, monitor: *anyopaque, size: Size, refresh_rate: u32) void {
    const lib = &(x11.xlib orelse return);
    if (screen_saver_count == 0) {
        _ = lib.XGetScreenSaver(
            window.display,
            &screen_saver_timeout,
            &screen_saver_interval,
            &screen_saver_blanking,
            &screen_saver_exposure,
        );
        _ = lib.XSetScreenSaver(window.display, 0, 0, x11.DontPreferBlanking, x11.DefaultExposures);
    }

    if (monitor_module.window(monitor) == null) {
        screen_saver_count += 1;
    }

    setMonitorVideoMode(monitor, size, refresh_rate);

    if (window.override_redirect) {
        const pos = monitor_module.getPos(monitor);
        const mode = monitor_module.getVideoMode(monitor);
        _ = lib.XMoveResizeWindow(window.display, window.handle, pos.x, pos.y, mode.width, mode.height);
    }

    monitor_module.setWindow(monitor, @ptrCast(window));
}

fn releaseMonitor(window: *x11.WindowState, monitor: *anyopaque) void {
    const lib = &(x11.xlib orelse return);
    if (monitor_module.window(monitor) != @as(*anyopaque, @ptrCast(window))) return;

    monitor_module.setWindow(monitor, null);
    monitor_module.restoreVideoMode(monitor);
    if (screen_saver_count > 0) {
        screen_saver_count -= 1;
        if (screen_saver_count == 0) {
            _ = lib.XSetScreenSaver(
                window.display,
                screen_saver_timeout,
                screen_saver_interval,
                screen_saver_blanking,
                screen_saver_exposure,
            );
        }
    }
}

fn setMonitorVideoMode(monitor: *anyopaque, size: Size, refresh_rate: u32) void {
    _ = monitor_module.setVideoMode(monitor, .{
        .width = size.width,
        .height = size.height,
        .red_bits = 8,
        .green_bits = 8,
        .blue_bits = 8,
        .refresh_rate = refresh_rate,
    });
}

fn dispatchUriDrop(window: *x11.WindowState, text: []const u8) bool {
    var paths: [max_drop_paths][:0]u8 = undefined;
    var count: usize = 0;

    var index: usize = 0;
    while (index < text.len and count < max_drop_paths) {
        const line_start = index;
        while (index < text.len and text[index] != '\r' and text[index] != '\n') : (index += 1) {}
        var line = text[line_start..index];
        while (index < text.len and (text[index] == '\r' or text[index] == '\n')) : (index += 1) {}

        if (line.len == 0 or line[0] == '#') continue;
        if (std.mem.startsWith(u8, line, "file://")) {
            line = line["file://".len..];
            var slash_index: usize = 0;
            while (slash_index < line.len and line[slash_index] != '/') : (slash_index += 1) {}
            if (slash_index >= line.len) continue;
            line = line[slash_index..];
        }

        paths[count] = decodeUriPath(line) orelse {
            freeDecodedPaths(paths[0..count]);
            return false;
        };
        count += 1;
    }

    if (count == 0) return false;
    const ptrs = std.heap.c_allocator.alloc([*:0]const u8, count) catch {
        freeDecodedPaths(paths[0..count]);
        return false;
    };
    defer std.heap.c_allocator.free(ptrs);
    defer freeDecodedPaths(paths[0..count]);

    for (paths[0..count], ptrs) |path, *ptr| ptr.* = path.ptr;
    callbacks().drop(window.callback_id, count, ptrs.ptr);
    return true;
}

fn freeDecodedPaths(paths: [][:0]u8) void {
    for (paths) |path| std.heap.c_allocator.free(path);
}

fn decodeUriPath(line: []const u8) ?[:0]u8 {
    var output_len: usize = 0;
    var index: usize = 0;
    while (index < line.len) : (index += 1) {
        if (line[index] == '%' and index + 2 < line.len) index += 2;
        output_len += 1;
    }

    const path = std.heap.c_allocator.allocSentinel(u8, output_len, 0) catch return null;
    var in_index: usize = 0;
    var out_index: usize = 0;
    while (in_index < line.len) : (in_index += 1) {
        if (line[in_index] == '%' and in_index + 2 < line.len) {
            path[out_index] = std.fmt.parseInt(u8, line[in_index + 1 .. in_index + 3], 16) catch 0;
            in_index += 2;
        } else {
            path[out_index] = line[in_index];
        }
        out_index += 1;
    }
    path.ptr[out_index] = 0;
    return path;
}

fn waitForSelectionNotify(selection: x11.Atom) ?x11.XSelectionEvent {
    const display = x11.display orelse return null;
    const lib = &(x11.xlib orelse return null);
    const time = @import("time.zig");
    const start = time.getTimerValue();
    const timeout = time.getTimerFrequency();
    const deadline = start + timeout;

    while (time.getTimerValue() < deadline) {
        while (lib.XPending(display) > 0) {
            var event: x11.XEvent = undefined;
            _ = lib.XNextEvent(display, &event);
            if (event.type == x11.SelectionNotify and event.xselection.requestor == helper_window and event.xselection.selection == selection) {
                return event.xselection;
            }
            handleEvent(&event);
        }
        if (!waitForX11Event(deadline)) return null;
    }

    return null;
}

fn readIncrementalSelection(notification: *const x11.XSelectionEvent, target: x11.Atom) ?[:0]u8 {
    const display = x11.display orelse return null;
    const lib = &(x11.xlib orelse return null);
    var bytes = std.ArrayList(u8).initCapacity(std.heap.c_allocator, 0) catch return null;
    defer bytes.deinit(std.heap.c_allocator);

    while (true) {
        if (!waitForSelectionPropertyNotify(notification)) return null;

        var actual_type: x11.Atom = 0;
        var actual_format: c_int = 0;
        var item_count: c_ulong = 0;
        var bytes_after: c_ulong = 0;
        var data: ?[*]u8 = null;
        _ = lib.XGetWindowProperty(
            display,
            notification.requestor,
            notification.property,
            0,
            std.math.maxInt(c_long),
            1,
            x11.AnyPropertyType,
            &actual_type,
            &actual_format,
            &item_count,
            &bytes_after,
            &data,
        );
        defer {
            if (data) |ptr| _ = lib.XFree(@ptrCast(ptr));
        }

        if (item_count == 0) {
            return if (target == x11.XA_STRING)
                latin1ToUtf8(bytes.items)
            else
                std.heap.c_allocator.dupeZ(u8, bytes.items) catch null;
        }

        if (data != null and actual_format == 8) {
            bytes.appendSlice(std.heap.c_allocator, data.?[0..@intCast(item_count)]) catch return null;
        }
    }
}

fn waitForSelectionPropertyNotify(notification: *const x11.XSelectionEvent) bool {
    const display = x11.display orelse return false;
    const lib = &(x11.xlib orelse return false);
    const time = @import("time.zig");
    const start = time.getTimerValue();
    const timeout = time.getTimerFrequency();
    const deadline = start + timeout;

    while (time.getTimerValue() < deadline) {
        while (lib.XPending(display) > 0) {
            var event: x11.XEvent = undefined;
            _ = lib.XNextEvent(display, &event);
            if (event.type == x11.PropertyNotify and
                event.xproperty.state == x11.PropertyNewValue and
                event.xproperty.window == notification.requestor and
                event.xproperty.atom == notification.property)
            {
                return true;
            }
            handleEvent(&event);
        }
        if (!waitForX11Event(deadline)) return false;
    }

    return false;
}

fn waitForFrameExtents(window: *x11.WindowState) bool {
    const display = x11.display orelse return false;
    const lib = &(x11.xlib orelse return false);
    const time = @import("time.zig");
    const start = time.getTimerValue();
    const timeout = time.getTimerFrequency() / 2;
    const deadline = start + timeout;

    while (time.getTimerValue() < deadline) {
        while (lib.XPending(display) > 0) {
            var event: x11.XEvent = undefined;
            _ = lib.XNextEvent(display, &event);
            if (event.type == x11.PropertyNotify and
                event.xproperty.state == x11.PropertyNewValue and
                event.xproperty.window == window.handle and
                event.xproperty.atom == x11.net_frame_extents)
            {
                return true;
            }
            handleEvent(&event);
        }
        if (!waitForX11Event(deadline)) return false;
    }

    return false;
}

fn waitForVisibilityNotify(window: *x11.WindowState) bool {
    const display = x11.display orelse return false;
    const lib = &(x11.xlib orelse return false);
    const time = @import("time.zig");
    const start = time.getTimerValue();
    const timeout = time.getTimerFrequency() / 10;
    const deadline = start + timeout;

    while (time.getTimerValue() < deadline) {
        var event: x11.XEvent = undefined;
        if (lib.XCheckTypedWindowEvent(display, window.handle, x11.VisibilityNotify, &event) != 0) {
            return true;
        }

        if (!waitForX11Event(deadline)) return false;
    }

    return false;
}

fn waitForX11Event(deadline: ?u64) bool {
    const display = x11.display orelse return false;
    const lib = &(x11.xlib orelse return false);
    const linux = std.os.linux;
    const time = @import("time.zig");

    var fd = [_]linux.pollfd{
        .{ .fd = lib.XConnectionNumber(display), .events = linux.POLL.IN, .revents = 0 },
    };

    while (lib.XPending(display) == 0) {
        const timeout_ms: i32 = if (deadline) |limit| blk: {
            const now = time.getTimerValue();
            if (now >= limit) return false;
            const remaining_ns = limit - now;
            const remaining_ms = @max(@as(u64, 1), remaining_ns / std.time.ns_per_ms);
            break :blk @intCast(@min(remaining_ms, @as(u64, @intCast(std.math.maxInt(i32)))));
        } else -1;

        const rc = linux.poll(&fd, fd.len, timeout_ms);
        switch (std.posix.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) return false;
            },
            .INTR => continue,
            else => return false,
        }
    }

    return true;
}

fn latin1ToUtf8(bytes: []const u8) ?[:0]u8 {
    const result = std.heap.c_allocator.allocSentinel(u8, bytes.len * 2, 0) catch return null;
    var out: usize = 0;
    for (bytes) |byte| {
        if (byte < 0x80) {
            result[out] = byte;
            out += 1;
        } else {
            result[out] = 0xc0 | @as(u8, @intCast(byte >> 6));
            result[out + 1] = 0x80 | (byte & 0x3f);
            out += 2;
        }
    }
    result[out] = 0;
    return result;
}

fn isKeyRepeatRelease(event: *const x11.XKeyEvent) bool {
    if (x11.detectable_autorepeat) return false;
    const display = event.display orelse return false;
    const lib = &(x11.xlib orelse return false);
    if (lib.XEventsQueued(display, x11.QueuedAfterReading) == 0) return false;

    var next: x11.XEvent = undefined;
    _ = lib.XPeekEvent(display, &next);
    if (next.type != x11.KeyPress) return false;
    if (next.xkey.window != event.window or next.xkey.keycode != event.keycode) return false;
    return next.xkey.time -% event.time < 20;
}

fn translateMods(state: c_uint) Input.Modifiers {
    return .{
        .shift = (state & x11.ShiftMask) != 0,
        .control = (state & x11.ControlMask) != 0,
        .alt = (state & x11.Mod1Mask) != 0,
        .super = (state & x11.Mod4Mask) != 0,
        .caps_lock = (state & x11.LockMask) != 0,
        .num_lock = (state & x11.Mod2Mask) != 0,
    };
}

fn updateCursor(window: *x11.WindowState) void {
    if (x11.xlib) |lib| {
        const cursor = switch (window.cursor_mode) {
            1, 2 => blank_cursor,
            else => window.cursor,
        };
        if (cursor != 0) {
            _ = lib.XDefineCursor(window.display, window.handle, cursor);
        } else {
            _ = lib.XUndefineCursor(window.display, window.handle);
        }
        _ = lib.XFlush(window.display);
    }
}

fn setTitleForWindow(window: *x11.WindowState, title: [*:0]const u8) void {
    if (x11.xlib) |lib| {
        const title_span = std.mem.span(title);
        if (x11.xlib_utf8) {
            lib.Xutf8SetWMProperties(window.display, window.handle, title, title, null, 0, null, null, null);
        }
        _ = lib.XStoreName(window.display, window.handle, title);
        _ = lib.XChangeProperty(
            window.display,
            window.handle,
            x11.net_wm_name,
            x11.utf8_string,
            8,
            x11.PropModeReplace,
            @ptrCast(title_span.ptr),
            @intCast(title_span.len),
        );
        _ = lib.XChangeProperty(
            window.display,
            window.handle,
            x11.net_wm_icon_name,
            x11.utf8_string,
            8,
            x11.PropModeReplace,
            @ptrCast(title_span.ptr),
            @intCast(title_span.len),
        );
    }
}

fn setWindowPid(window: *x11.WindowState) void {
    if (x11.xlib) |lib| {
        var pid: c_ulong = @intCast(std.os.linux.getpid());
        _ = lib.XChangeProperty(
            window.display,
            window.handle,
            x11.net_wm_pid,
            x11.XA_CARDINAL,
            32,
            x11.PropModeReplace,
            @ptrCast(&pid),
            1,
        );
    }
}

fn setWindowType(window: *x11.WindowState) void {
    if (x11.net_wm_window_type == 0 or x11.net_wm_window_type_normal == 0) return;
    if (x11.xlib) |lib| {
        var window_type = x11.net_wm_window_type_normal;
        _ = lib.XChangeProperty(
            window.display,
            window.handle,
            x11.net_wm_window_type,
            x11.XA_ATOM,
            32,
            x11.PropModeReplace,
            @ptrCast(&window_type),
            1,
        );
    }
}

fn isVisualTransparent(visual: *x11.Visual) bool {
    const display = x11.display orelse return false;
    const lib = if (xrender) |*value| value else return false;
    if (!lib.available) return false;

    const format = lib.XRenderFindVisualFormat(display, visual) orelse return false;
    return format.direct.alpha_mask != 0;
}

fn setRawMouseMotion(window: *x11.WindowState, enabled: bool) void {
    _ = window;
    if (!x11.xi_available) return;
    const lib = if (xi) |*value| value else return;
    var mask = [_]u8{0} ** xiMaskLen(xi_raw_motion);
    var xi_event_mask = XIEventMask{
        .deviceid = xi_all_master_devices,
        .mask_len = @intCast(mask.len),
        .mask = mask[0..].ptr,
    };

    if (enabled) xiSetMask(mask[0..], xi_raw_motion);
    _ = lib.XISelectEvents(x11.display orelse return, x11.root, &xi_event_mask, 1);
}

fn captureCursor(window: *x11.WindowState) void {
    if (x11.xlib) |lib| {
        _ = lib.XGrabPointer(
            window.display,
            window.handle,
            1,
            @intCast(x11.ButtonPressMask | x11.ButtonReleaseMask | x11.PointerMotionMask),
            x11.GrabModeAsync,
            x11.GrabModeAsync,
            window.handle,
            x11.None,
            x11.CurrentTime,
        );
    }
}

fn releaseCursor(window: *x11.WindowState) void {
    if (x11.xlib) |lib| _ = lib.XUngrabPointer(window.display, x11.CurrentTime);
}

fn setMousePassthrough(window: *x11.WindowState, enabled: bool) void {
    if (!xshape_available) return;
    const lib = if (xshape) |*shape| shape else return;
    const xlib = &(x11.xlib orelse return);

    if (enabled) {
        const region = xlib.XCreateRegion();
        lib.XShapeCombineRegion(window.display, window.handle, shape_input, 0, 0, region, shape_set);
        _ = xlib.XDestroyRegion(region);
    } else {
        lib.XShapeCombineMask(window.display, window.handle, shape_input, 0, 0, x11.None, shape_set);
    }
}

fn loadXi() void {
    if (xi != null) return;
    const display = x11.display orelse return;
    const xlib = &(x11.xlib orelse return);
    var lib = std.DynLib.open("libXi.so.6") catch std.DynLib.open("libXi.so") catch return;
    var keep_lib = false;
    defer if (!keep_lib) lib.close();

    const query_version = lookupXi(&lib, "XIQueryVersion") orelse return;
    const select_events = lookupXi(&lib, "XISelectEvents") orelse return;

    var major_opcode: c_int = 0;
    var event_base: c_int = 0;
    var error_base: c_int = 0;
    if (xlib.XQueryExtension(display, "XInputExtension", &major_opcode, &event_base, &error_base) == 0) return;

    var major: c_int = 2;
    var minor: c_int = 0;
    if (query_version(display, &major, &minor) == 0) {
        xi = .{
            .lib = lib,
            .XIQueryVersion = query_version,
            .XISelectEvents = select_events,
        };
        x11.xi_available = true;
        x11.xi_major_opcode = major_opcode;
        keep_lib = true;
    }
}

fn unloadXi() void {
    if (xi) |*lib| lib.lib.close();
    xi = null;
    x11.xi_available = false;
    x11.xi_major_opcode = 0;
}

fn lookupXi(lib: *std.DynLib, comptime name: [:0]const u8) ?@TypeOf(@field(@as(Xi, undefined), name)) {
    return lib.lookup(@TypeOf(@field(@as(Xi, undefined), name)), name);
}

fn xiMaskLen(comptime event: c_int) comptime_int {
    return (event >> 3) + 1;
}

fn xiSetMask(mask: []u8, event: c_int) void {
    mask[@intCast(event >> 3)] |= @as(u8, 1) << @intCast(event & 7);
}

fn xiMaskIsSet(mask: [*]u8, event: c_int) bool {
    return (mask[@intCast(event >> 3)] & (@as(u8, 1) << @intCast(event & 7))) != 0;
}

fn setWindowHints(window: *x11.WindowState) void {
    if (x11.xlib) |lib| {
        var hints = x11.XWMHints{
            .flags = x11.StateHint,
            .initial_state = x11.NormalState,
        };
        _ = lib.XSetWMHints(window.display, window.handle, &hints);
    }
}

fn loadXshape() void {
    if (xshape != null) return;
    const display = x11.display orelse return;
    var lib = std.DynLib.open("libXext.so.6") catch std.DynLib.open("libXext.so") catch return;
    var keep_lib = false;
    defer if (!keep_lib) lib.close();

    const query_extension = lookupXshape(&lib, "XShapeQueryExtension") orelse return;
    const query_version = lookupXshape(&lib, "XShapeQueryVersion") orelse return;
    const combine_region = lookupXshape(&lib, "XShapeCombineRegion") orelse return;
    const combine_mask = lookupXshape(&lib, "XShapeCombineMask") orelse return;

    var error_base: c_int = 0;
    var event_base: c_int = 0;
    if (query_extension(display, &error_base, &event_base) == 0) return;

    var major: c_int = 0;
    var minor: c_int = 0;
    if (query_version(display, &major, &minor) == 0) return;

    xshape = .{
        .lib = lib,
        .XShapeQueryExtension = query_extension,
        .XShapeQueryVersion = query_version,
        .XShapeCombineRegion = combine_region,
        .XShapeCombineMask = combine_mask,
    };
    keep_lib = true;
    xshape_available = true;
}

fn unloadXshape() void {
    if (xshape) |*lib| lib.lib.close();
    xshape = null;
    xshape_available = false;
}

fn lookupXshape(lib: *std.DynLib, comptime name: [:0]const u8) ?@TypeOf(@field(@as(Xshape, undefined), name)) {
    return lib.lookup(@TypeOf(@field(@as(Xshape, undefined), name)), name);
}

fn loadXrender() void {
    if (xrender != null) return;
    const display = x11.display orelse return;
    var lib = std.DynLib.open("libXrender-1.so") catch
        std.DynLib.open("libXrender.so") catch
        std.DynLib.open("libXrender.so.1") catch return;
    var keep_lib = false;
    defer if (!keep_lib) lib.close();

    const query_extension = lookupXrender(&lib, "XRenderQueryExtension") orelse return;
    const query_version = lookupXrender(&lib, "XRenderQueryVersion") orelse return;
    const find_visual_format = lookupXrender(&lib, "XRenderFindVisualFormat") orelse return;

    var error_base: c_int = 0;
    var event_base: c_int = 0;
    if (query_extension(display, &error_base, &event_base) == 0) return;

    var major: c_int = 0;
    var minor: c_int = 0;
    if (query_version(display, &major, &minor) == 0) return;

    xrender = .{
        .lib = lib,
        .configured = true,
        .available = true,
        .major = major,
        .minor = minor,
        .event_base = event_base,
        .error_base = error_base,
        .XRenderQueryExtension = query_extension,
        .XRenderQueryVersion = query_version,
        .XRenderFindVisualFormat = find_visual_format,
    };
    keep_lib = true;
}

fn unloadXrender() void {
    if (xrender) |*lib| lib.lib.close();
    xrender = null;
}

fn lookupXrender(lib: *std.DynLib, comptime name: [:0]const u8) ?@TypeOf(@field(@as(XRender, undefined), name)) {
    return lib.lookup(@TypeOf(@field(@as(XRender, undefined), name)), name);
}

fn setClassHint(window: *x11.WindowState, title: [*:0]const u8) void {
    const lib = &(x11.xlib orelse return);
    const title_span = std.mem.span(title);
    const resource_name = std.c.getenv("RESOURCE_NAME");

    var hint = x11.XClassHint{};
    if (resource_name) |name| {
        if (std.mem.span(name).len != 0) {
            hint.res_name = name;
        }
    }

    if (hint.res_name == null) {
        hint.res_name = if (title_span.len != 0)
            @constCast(title)
        else
            @constCast("glfw-application");
    }

    hint.res_class = if (title_span.len != 0)
        @constCast(title)
    else
        @constCast("GLFW-Application");

    _ = lib.XSetClassHint(window.display, window.handle, &hint);
}

fn setWindowDecorations(window: *x11.WindowState, decorated: bool) void {
    if (x11.xlib) |lib| {
        var hints = x11.MotifWmHints{
            .flags = 2,
            .decorations = if (decorated) 1 else 0,
        };
        _ = lib.XChangeProperty(
            window.display,
            window.handle,
            x11.motif_wm_hints,
            x11.motif_wm_hints,
            32,
            x11.PropModeReplace,
            @ptrCast(&hints),
            @sizeOf(x11.MotifWmHints) / @sizeOf(c_ulong),
        );
    }
}

fn updateNormalHints(window: *x11.WindowState) void {
    if (x11.xlib) |lib| {
        var hints = x11.XSizeHints{};
        hints.flags = x11.PWinGravity;
        hints.win_gravity = x11.StaticGravity;

        if (window.monitor == null and window.resizable) {
            if (window.min_width != 0 and window.min_height != 0) {
                hints.flags |= x11.PMinSize;
                hints.min_width = @intCast(window.min_width);
                hints.min_height = @intCast(window.min_height);
            }

            if (window.max_width != 0 and window.max_height != 0) {
                hints.flags |= x11.PMaxSize;
                hints.max_width = @intCast(window.max_width);
                hints.max_height = @intCast(window.max_height);
            }

            if (window.aspect_numerator != 0 and window.aspect_denominator != 0) {
                hints.flags |= x11.PAspect;
                hints.min_aspect.x = @intCast(window.aspect_numerator);
                hints.min_aspect.y = @intCast(window.aspect_denominator);
                hints.max_aspect.x = @intCast(window.aspect_numerator);
                hints.max_aspect.y = @intCast(window.aspect_denominator);
            }
        } else {
            hints.flags |= x11.PMinSize | x11.PMaxSize;
            hints.min_width = @intCast(window.width);
            hints.min_height = @intCast(window.height);
            hints.max_width = @intCast(window.width);
            hints.max_height = @intCast(window.height);
        }

        lib.XSetWMNormalHints(window.display, window.handle, &hints);
    }
}

fn setNetWmState(window: *x11.WindowState, atom: x11.Atom, enabled: bool) void {
    if (atom == 0) return;
    sendEventToWM(window, x11.net_wm_state, if (enabled) 1 else 0, @intCast(atom), 0, 1, 0);
}

fn sendEventToWM(window: *x11.WindowState, message_type: x11.Atom, a: c_long, b: c_long, c: c_long, d: c_long, e: c_long) void {
    if (message_type == 0) return;
    if (x11.xlib) |lib| {
        var event = std.mem.zeroes(x11.XEvent);
        event.xclient.type = x11.ClientMessage;
        event.xclient.display = window.display;
        event.xclient.window = window.handle;
        event.xclient.message_type = message_type;
        event.xclient.format = 32;
        event.xclient.data.l[0] = a;
        event.xclient.data.l[1] = b;
        event.xclient.data.l[2] = c;
        event.xclient.data.l[3] = d;
        event.xclient.data.l[4] = e;
        _ = lib.XSendEvent(
            window.display,
            x11.root,
            0,
            x11.SubstructureNotifyMask | x11.SubstructureRedirectMask,
            &event,
        );
        _ = lib.XFlush(window.display);
    }
}

fn createBlankCursor() x11.Cursor {
    const display = x11.display orelse return 0;
    var pixels: [16 * 16 * 4]u8 = @splat(0);
    const image = cursor_module.Image{
        .width = 16,
        .height = 16,
        .pixels = pixels[0..].ptr,
    };
    return cursor_module.createNativeCursor(display, &image, 0, 0) orelse 0;
}

fn registerWindow(window: *x11.WindowState) void {
    for (&windows) |*slot| {
        if (slot.* == null) {
            slot.* = window;
            return;
        }
    }
}

fn unregisterWindow(window: *x11.WindowState) void {
    for (&windows) |*slot| {
        if (slot.* == window) {
            slot.* = null;
            return;
        }
    }
}

fn windowFromXid(handle: x11.Window) ?*x11.WindowState {
    for (windows) |maybe_window| {
        if (maybe_window) |window| {
            if (window.handle == handle) return window;
        }
    }
    return null;
}
