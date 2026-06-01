const std = @import("std");

pub const Bool = c_int;
pub const Status = c_int;
pub const Success: Status = 0;
pub const Display = opaque {};
pub const Visual = opaque {};
pub const Screen = opaque {};
pub const Region = opaque {};
pub const XIC = ?*opaque {};
pub const XIM = ?*opaque {};
pub const XrmDatabase = ?*opaque {};
pub const XIMStyle = c_ulong;
pub const XPointer = ?*anyopaque;
pub const XIDProc = *const fn (*Display, XPointer, XPointer) callconv(.c) void;
pub const XIMProc = *const fn (XIM, XPointer, XPointer) callconv(.c) void;
pub const XErrorHandler = ?*const fn (*Display, *XErrorEvent) callconv(.c) c_int;
pub const Window = c_ulong;
pub const XID = c_ulong;
pub const Drawable = c_ulong;
pub const Pixmap = c_ulong;
pub const Colormap = c_ulong;
pub const Cursor = c_ulong;
pub const Atom = c_ulong;
pub const Time = c_ulong;
pub const VisualID = c_ulong;
pub const KeySym = c_ulong;
pub const KeyCode = u8;

pub const None: c_ulong = 0;
pub const CurrentTime: Time = 0;
pub const BadWindow: c_int = 3;
pub const GrabModeAsync: c_int = 1;
pub const CopyFromParent: c_int = 0;
pub const InputOutput: c_uint = 1;
pub const InputOnly: c_uint = 2;
pub const AllocNone: c_int = 0;
pub const NoEventMask: c_long = 0;
pub const CWBorderPixel: c_ulong = 1 << 3;
pub const CWOverrideRedirect: c_ulong = 1 << 9;
pub const CWEventMask: c_ulong = 1 << 11;
pub const CWColormap: c_ulong = 1 << 13;
pub const PropModeReplace: c_int = 0;
pub const PropModeAppend: c_int = 2;
pub const RevertToParent: c_int = 2;
pub const QueuedAfterReading: c_int = 1;
pub const PPosition: c_long = 1 << 2;
pub const PMinSize: c_long = 1 << 4;
pub const PMaxSize: c_long = 1 << 5;
pub const PAspect: c_long = 1 << 7;
pub const PWinGravity: c_long = 1 << 9;
pub const StateHint: c_long = 1 << 1;
pub const NormalState: c_int = 1;
pub const IconicState: c_int = 3;
pub const IsViewable: c_int = 2;
pub const StaticGravity: c_int = 10;
pub const PropertyNewValue: c_int = 0;
pub const DontPreferBlanking: c_int = 0;
pub const DefaultExposures: c_int = 2;
pub const NotifyGrab: c_int = 1;
pub const NotifyUngrab: c_int = 2;
pub const XIMPreeditNothing: XIMStyle = 0x0008;
pub const XIMStatusNothing: XIMStyle = 0x0400;
pub const XBufferOverflow: Status = -1;
pub const XLookupChars: Status = 2;
pub const XLookupBoth: Status = 4;
pub const XNInputStyle: [*:0]const u8 = "inputStyle";
pub const XNClientWindow: [*:0]const u8 = "clientWindow";
pub const XNFocusWindow: [*:0]const u8 = "focusWindow";
pub const XNDestroyCallback: [*:0]const u8 = "destroyCallback";
pub const XNFilterEvents: [*:0]const u8 = "filterEvents";
pub const XNQueryInputStyle: [*:0]const u8 = "queryInputStyle";
pub const XkbUseCoreKbd: c_uint = 0x0100;
pub const XkbEventCode: c_int = 0;
pub const XkbStateNotify: c_int = 2;
pub const XkbKeyNameLength = 4;
pub const XkbKeyNamesMask: c_uint = 1 << 9;
pub const XkbKeyAliasesMask: c_uint = 1 << 10;
pub const XkbGroupStateMask: c_uint = 1 << 4;

pub const KeyPress: c_int = 2;
pub const KeyRelease: c_int = 3;
pub const ButtonPress: c_int = 4;
pub const ButtonRelease: c_int = 5;
pub const MotionNotify: c_int = 6;
pub const EnterNotify: c_int = 7;
pub const LeaveNotify: c_int = 8;
pub const FocusIn: c_int = 9;
pub const FocusOut: c_int = 10;
pub const Expose: c_int = 12;
pub const VisibilityNotify: c_int = 15;
pub const UnmapNotify: c_int = 18;
pub const MapNotify: c_int = 19;
pub const ReparentNotify: c_int = 21;
pub const ConfigureNotify: c_int = 22;
pub const PropertyNotify: c_int = 28;
pub const SelectionClear: c_int = 29;
pub const SelectionRequest: c_int = 30;
pub const SelectionNotify: c_int = 31;
pub const ClientMessage: c_int = 33;
pub const GenericEvent: c_int = 35;

pub const KeyPressMask: c_long = 1 << 0;
pub const KeyReleaseMask: c_long = 1 << 1;
pub const ButtonPressMask: c_long = 1 << 2;
pub const ButtonReleaseMask: c_long = 1 << 3;
pub const EnterWindowMask: c_long = 1 << 4;
pub const LeaveWindowMask: c_long = 1 << 5;
pub const PointerMotionMask: c_long = 1 << 6;
pub const ExposureMask: c_long = 1 << 15;
pub const VisibilityChangeMask: c_long = 1 << 16;
pub const StructureNotifyMask: c_long = 1 << 17;
pub const SubstructureNotifyMask: c_long = 1 << 19;
pub const SubstructureRedirectMask: c_long = 1 << 20;
pub const FocusChangeMask: c_long = 1 << 21;
pub const PropertyChangeMask: c_long = 1 << 22;

pub const ShiftMask: c_uint = 1 << 0;
pub const LockMask: c_uint = 1 << 1;
pub const ControlMask: c_uint = 1 << 2;
pub const Mod1Mask: c_uint = 1 << 3;
pub const Mod2Mask: c_uint = 1 << 4;
pub const Mod4Mask: c_uint = 1 << 6;

pub const Button1: c_uint = 1;
pub const Button2: c_uint = 2;
pub const Button3: c_uint = 3;
pub const Button4: c_uint = 4;
pub const Button5: c_uint = 5;
pub const Button6: c_uint = 6;
pub const Button7: c_uint = 7;

pub const XA_ATOM: Atom = 4;
pub const XA_CARDINAL: Atom = 6;
pub const XA_STRING: Atom = 31;
pub const XA_WINDOW: Atom = 33;
pub const AnyPropertyType: Atom = 0;

pub const XColor = extern struct {
    pixel: c_ulong = 0,
    red: c_ushort = 0,
    green: c_ushort = 0,
    blue: c_ushort = 0,
    flags: u8 = 0,
    pad: u8 = 0,
};

pub const XAnyEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: Bool,
    display: ?*Display,
    window: Window,
};

pub const XErrorEvent = extern struct {
    type: c_int,
    display: ?*Display,
    resourceid: XID,
    serial: c_ulong,
    error_code: u8,
    request_code: u8,
    minor_code: u8,
};

pub const XKeyEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: Bool,
    display: ?*Display,
    window: Window,
    root: Window,
    subwindow: Window,
    time: Time,
    x: c_int,
    y: c_int,
    x_root: c_int,
    y_root: c_int,
    state: c_uint,
    keycode: c_uint,
    same_screen: Bool,
};

pub const XButtonEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: Bool,
    display: ?*Display,
    window: Window,
    root: Window,
    subwindow: Window,
    time: Time,
    x: c_int,
    y: c_int,
    x_root: c_int,
    y_root: c_int,
    state: c_uint,
    button: c_uint,
    same_screen: Bool,
};

pub const XMotionEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: Bool,
    display: ?*Display,
    window: Window,
    root: Window,
    subwindow: Window,
    time: Time,
    x: c_int,
    y: c_int,
    x_root: c_int,
    y_root: c_int,
    state: c_uint,
    is_hint: u8,
    same_screen: Bool,
};

pub const XCrossingEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: Bool,
    display: ?*Display,
    window: Window,
    root: Window,
    subwindow: Window,
    time: Time,
    x: c_int,
    y: c_int,
    x_root: c_int,
    y_root: c_int,
    mode: c_int,
    detail: c_int,
    same_screen: Bool,
    focus: Bool,
    state: c_uint,
};

pub const XFocusChangeEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: Bool,
    display: ?*Display,
    window: Window,
    mode: c_int,
    detail: c_int,
};

pub const XConfigureEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: Bool,
    display: ?*Display,
    event: Window,
    window: Window,
    x: c_int,
    y: c_int,
    width: c_int,
    height: c_int,
    border_width: c_int,
    above: Window,
    override_redirect: Bool,
};

pub const XReparentEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: Bool,
    display: ?*Display,
    event: Window,
    window: Window,
    parent: Window,
    x: c_int,
    y: c_int,
    override_redirect: Bool,
};

pub const XkbKeyNameRec = extern struct {
    name: [XkbKeyNameLength]u8,
};

pub const XkbKeyAliasRec = extern struct {
    real: [XkbKeyNameLength]u8,
    alias: [XkbKeyNameLength]u8,
};

pub const XIMStyles = extern struct {
    count_styles: c_ushort,
    supported_styles: [*]XIMStyle,
};

pub const XIMCallback = extern struct {
    client_data: XPointer,
    callback: ?XIMProc,
};

pub const XrmValue = extern struct {
    size: c_uint,
    addr: XPointer,
};

pub const XkbNamesRec = extern struct {
    keycodes: Atom,
    geometry: Atom,
    symbols: Atom,
    types: Atom,
    compat: Atom,
    vmods: [16]Atom,
    indicators: [32]Atom,
    groups: [4]Atom,
    keys: [*]XkbKeyNameRec,
    key_aliases: [*]XkbKeyAliasRec,
    radio_groups: ?[*]Atom,
    phys_symbols: Atom,
    num_keys: u8,
    num_key_aliases: u8,
    num_rg: u16,
};

pub const XkbDescRec = extern struct {
    display: ?*Display,
    flags: c_ushort,
    device_spec: c_ushort,
    min_key_code: KeyCode,
    max_key_code: KeyCode,
    ctrls: ?*anyopaque,
    server: ?*anyopaque,
    map: ?*anyopaque,
    indicators: ?*anyopaque,
    names: ?*XkbNamesRec,
    compat: ?*anyopaque,
    geom: ?*anyopaque,
};

pub const XkbStateRec = extern struct {
    group: u8,
    locked_group: u8,
    base_group: u16,
    latched_group: u16,
    mods: u8,
    base_mods: u8,
    latched_mods: u8,
    locked_mods: u8,
    compat_state: u8,
    grab_mods: u8,
    compat_grab_mods: u8,
    lookup_mods: u8,
    compat_lookup_mods: u8,
    ptr_buttons: u16,
};

pub const XkbStateNotifyEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: Bool,
    display: ?*Display,
    time: Time,
    xkb_type: c_int,
    device: c_int,
    changed: c_uint,
    group: c_int,
    base_group: c_int,
    latched_group: c_int,
    locked_group: c_int,
    mods: c_uint,
    base_mods: c_uint,
    latched_mods: c_uint,
    locked_mods: c_uint,
    compat_state: c_int,
    grab_mods: u8,
    compat_grab_mods: u8,
    lookup_mods: u8,
    compat_lookup_mods: u8,
    ptr_buttons: c_int,
    keycode: KeyCode,
    event_type: u8,
    request_major: u8,
    request_minor: u8,
};

pub const XkbEvent = extern union {
    type: c_int,
    state: XkbStateNotifyEvent,
    pad: [24]c_long,
};

pub const XPropertyEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: Bool,
    display: ?*Display,
    window: Window,
    atom: Atom,
    time: Time,
    state: c_int,
};

pub const XClientMessageEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: Bool,
    display: ?*Display,
    window: Window,
    message_type: Atom,
    format: c_int,
    data: extern union {
        b: [20]u8,
        s: [10]c_short,
        l: [5]c_long,
    },
};

pub const XGenericEventCookie = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: Bool,
    display: ?*Display,
    extension: c_int,
    evtype: c_int,
    cookie: c_uint,
    data: ?*anyopaque,
};

pub const XSelectionRequestEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: Bool,
    display: ?*Display,
    owner: Window,
    requestor: Window,
    selection: Atom,
    target: Atom,
    property: Atom,
    time: Time,
};

pub const XSelectionEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: Bool,
    display: ?*Display,
    requestor: Window,
    selection: Atom,
    target: Atom,
    property: Atom,
    time: Time,
};

pub const XSelectionClearEvent = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: Bool,
    display: ?*Display,
    window: Window,
    selection: Atom,
    time: Time,
};

pub const XEvent = extern union {
    type: c_int,
    xany: XAnyEvent,
    xkey: XKeyEvent,
    xbutton: XButtonEvent,
    xmotion: XMotionEvent,
    xcrossing: XCrossingEvent,
    xfocus: XFocusChangeEvent,
    xconfigure: XConfigureEvent,
    xreparent: XReparentEvent,
    xproperty: XPropertyEvent,
    xclient: XClientMessageEvent,
    xcookie: XGenericEventCookie,
    xselectionrequest: XSelectionRequestEvent,
    xselection: XSelectionEvent,
    xselectionclear: XSelectionClearEvent,
    pad: [24]c_long,
};

pub const XWindowAttributes = extern struct {
    x: c_int = 0,
    y: c_int = 0,
    width: c_int = 0,
    height: c_int = 0,
    border_width: c_int = 0,
    depth: c_int = 0,
    visual: ?*Visual = null,
    root: Window = 0,
    class: c_int = 0,
    bit_gravity: c_int = 0,
    win_gravity: c_int = 0,
    backing_store: c_int = 0,
    backing_planes: c_ulong = 0,
    backing_pixel: c_ulong = 0,
    save_under: Bool = 0,
    colormap: Colormap = 0,
    map_installed: Bool = 0,
    map_state: c_int = 0,
    all_event_masks: c_long = 0,
    your_event_mask: c_long = 0,
    do_not_propagate_mask: c_long = 0,
    override_redirect: Bool = 0,
    screen: ?*Screen = null,
};

pub const XSetWindowAttributes = extern struct {
    background_pixmap: Pixmap = 0,
    background_pixel: c_ulong = 0,
    border_pixmap: Pixmap = 0,
    border_pixel: c_ulong = 0,
    bit_gravity: c_int = 0,
    win_gravity: c_int = 0,
    backing_store: c_int = 0,
    backing_planes: c_ulong = 0,
    backing_pixel: c_ulong = 0,
    save_under: Bool = 0,
    event_mask: c_long = 0,
    do_not_propagate_mask: c_long = 0,
    override_redirect: Bool = 0,
    colormap: Colormap = 0,
    cursor: Cursor = 0,
};

pub const MotifWmHints = extern struct {
    flags: c_ulong = 0,
    functions: c_ulong = 0,
    decorations: c_ulong = 0,
    input_mode: c_long = 0,
    status: c_ulong = 0,
};

pub const XClassHint = extern struct {
    res_name: ?[*:0]u8 = null,
    res_class: ?[*:0]u8 = null,
};

pub const XWMHints = extern struct {
    flags: c_long = 0,
    input: Bool = 0,
    initial_state: c_int = 0,
    icon_pixmap: Pixmap = 0,
    icon_window: Window = 0,
    icon_x: c_int = 0,
    icon_y: c_int = 0,
    icon_mask: Pixmap = 0,
    window_group: Window = 0,
};

pub const XSizeHints = extern struct {
    flags: c_long = 0,
    x: c_int = 0,
    y: c_int = 0,
    width: c_int = 0,
    height: c_int = 0,
    min_width: c_int = 0,
    min_height: c_int = 0,
    max_width: c_int = 0,
    max_height: c_int = 0,
    width_inc: c_int = 0,
    height_inc: c_int = 0,
    min_aspect: extern struct { x: c_int = 0, y: c_int = 0 } = .{},
    max_aspect: extern struct { x: c_int = 0, y: c_int = 0 } = .{},
    base_width: c_int = 0,
    base_height: c_int = 0,
    win_gravity: c_int = 0,
};

pub const WindowState = extern struct {
    display: *Display,
    handle: Window,
    parent: Window,
    colormap: Colormap = 0,
    callback_id: usize = 0,
    should_close: bool = false,
    width: u32 = 0,
    height: u32 = 0,
    x: i32 = 0,
    y: i32 = 0,
    cursor: Cursor = 0,
    ic: XIC = null,
    cursor_mode: c_int = 0,
    virtual_cursor_x: f64 = 0,
    virtual_cursor_y: f64 = 0,
    restore_cursor_x: f64 = 0,
    restore_cursor_y: f64 = 0,
    user_pointer: ?*anyopaque = null,
    monitor: ?*anyopaque = null,
    decorated: bool = true,
    resizable: bool = true,
    floating: bool = false,
    mouse_passthrough: bool = false,
    raw_mouse_motion: bool = false,
    auto_iconify: bool = true,
    override_redirect: bool = false,
    transparent: bool = false,
    visible: bool = false,
    iconified: bool = false,
    maximized: bool = false,
    last_cursor_pos_x: i32 = 0,
    last_cursor_pos_y: i32 = 0,
    warp_cursor_pos_x: i32 = std.math.minInt(i32),
    warp_cursor_pos_y: i32 = std.math.minInt(i32),
    key_press_times: [256]Time = @splat(0),
    min_width: u32 = 0,
    min_height: u32 = 0,
    max_width: u32 = 0,
    max_height: u32 = 0,
    aspect_numerator: u32 = 0,
    aspect_denominator: u32 = 0,
    xdnd_source: Window = 0,
    xdnd_version: c_long = 0,
    xdnd_format: Atom = 0,
};

pub const Xlib = struct {
    lib: std.DynLib,
    XOpenDisplay: *const fn (?[*:0]const u8) callconv(.c) ?*Display,
    XCloseDisplay: *const fn (*Display) callconv(.c) c_int,
    XConnectionNumber: *const fn (*Display) callconv(.c) c_int,
    XDefaultScreen: *const fn (*Display) callconv(.c) c_int,
    XDefaultDepth: *const fn (*Display, c_int) callconv(.c) c_int,
    XDefaultVisual: *const fn (*Display, c_int) callconv(.c) ?*Visual,
    XRootWindow: *const fn (*Display, c_int) callconv(.c) Window,
    XBlackPixel: *const fn (*Display, c_int) callconv(.c) c_ulong,
    XWhitePixel: *const fn (*Display, c_int) callconv(.c) c_ulong,
    XCreateColormap: *const fn (*Display, Window, *Visual, c_int) callconv(.c) Colormap,
    XCreateSimpleWindow: *const fn (*Display, Window, c_int, c_int, c_uint, c_uint, c_uint, c_ulong, c_ulong) callconv(.c) Window,
    XCreateWindow: *const fn (*Display, Window, c_int, c_int, c_uint, c_uint, c_uint, c_int, c_uint, ?*Visual, c_ulong, *XSetWindowAttributes) callconv(.c) Window,
    XDestroyWindow: *const fn (*Display, Window) callconv(.c) c_int,
    XFreeColormap: *const fn (*Display, Colormap) callconv(.c) c_int,
    XCloseIM: *const fn (XIM) callconv(.c) Status,
    XCreateIC: *const fn (XIM, ...) callconv(.c) XIC,
    XDestroyIC: *const fn (XIC) callconv(.c) void,
    XGetICValues: *const fn (XIC, ...) callconv(.c) ?[*:0]u8,
    XGetIMValues: *const fn (XIM, ...) callconv(.c) ?[*:0]u8,
    XInitThreads: *const fn () callconv(.c) Status,
    XOpenIM: *const fn (*Display, XPointer, ?[*:0]u8, ?[*:0]u8) callconv(.c) XIM,
    XRegisterIMInstantiateCallback: *const fn (*Display, XPointer, ?[*:0]u8, ?[*:0]u8, XIDProc, XPointer) callconv(.c) Bool,
    XResourceManagerString: *const fn (*Display) callconv(.c) ?[*:0]u8,
    XrmDestroyDatabase: *const fn (XrmDatabase) callconv(.c) void,
    XrmGetResource: *const fn (XrmDatabase, [*:0]const u8, [*:0]const u8, *?[*:0]u8, *XrmValue) callconv(.c) Bool,
    XrmGetStringDatabase: *const fn ([*:0]const u8) callconv(.c) XrmDatabase,
    XrmInitialize: *const fn () callconv(.c) void,
    XSetICFocus: *const fn (XIC) callconv(.c) void,
    XSetIMValues: *const fn (XIM, ...) callconv(.c) ?[*:0]u8,
    XSetLocaleModifiers: *const fn (?[*:0]const u8) callconv(.c) ?[*:0]const u8,
    XSupportsLocale: *const fn () callconv(.c) Bool,
    XUnregisterIMInstantiateCallback: *const fn (*Display, XPointer, ?[*:0]u8, ?[*:0]u8, XIDProc, XPointer) callconv(.c) Bool,
    XUnsetICFocus: *const fn (XIC) callconv(.c) void,
    Xutf8LookupString: *const fn (XIC, *XKeyEvent, [*]u8, c_int, ?*KeySym, *Status) callconv(.c) c_int,
    Xutf8SetWMProperties: *const fn (*Display, Window, [*:0]const u8, [*:0]const u8, ?[*]?[*:0]u8, c_int, ?*XSizeHints, ?*XWMHints, ?*XClassHint) callconv(.c) void,
    XCreateRegion: *const fn () callconv(.c) ?*Region,
    XDestroyRegion: *const fn (?*Region) callconv(.c) c_int,
    XMapWindow: *const fn (*Display, Window) callconv(.c) c_int,
    XMapRaised: *const fn (*Display, Window) callconv(.c) c_int,
    XUnmapWindow: *const fn (*Display, Window) callconv(.c) c_int,
    XStoreName: *const fn (*Display, Window, [*:0]const u8) callconv(.c) c_int,
    XChangeWindowAttributes: *const fn (*Display, Window, c_ulong, *XSetWindowAttributes) callconv(.c) c_int,
    XChangeProperty: *const fn (*Display, Window, Atom, Atom, c_int, c_int, ?[*]const u8, c_int) callconv(.c) c_int,
    XDeleteProperty: *const fn (*Display, Window, Atom) callconv(.c) c_int,
    XGetWindowProperty: *const fn (*Display, Window, Atom, c_long, c_long, Bool, Atom, *Atom, *c_int, *c_ulong, *c_ulong, *?[*]u8) callconv(.c) c_int,
    XQueryExtension: *const fn (*Display, [*:0]const u8, *c_int, *c_int, *c_int) callconv(.c) Bool,
    XCheckTypedWindowEvent: *const fn (*Display, Window, c_int, *XEvent) callconv(.c) Bool,
    XSelectInput: *const fn (*Display, Window, c_long) callconv(.c) c_int,
    XEventsQueued: *const fn (*Display, c_int) callconv(.c) c_int,
    XNextEvent: *const fn (*Display, *XEvent) callconv(.c) c_int,
    XPeekEvent: *const fn (*Display, *XEvent) callconv(.c) c_int,
    XPending: *const fn (*Display) callconv(.c) c_int,
    XFilterEvent: *const fn (*XEvent, Window) callconv(.c) Bool,
    XFlush: *const fn (*Display) callconv(.c) c_int,
    XInternAtom: *const fn (*Display, [*:0]const u8, Bool) callconv(.c) Atom,
    XSetWMProtocols: *const fn (*Display, Window, *Atom, c_int) callconv(.c) Status,
    XSendEvent: *const fn (*Display, Window, Bool, c_long, *XEvent) callconv(.c) Status,
    XSetSelectionOwner: *const fn (*Display, Atom, Window, Time) callconv(.c) c_int,
    XGetSelectionOwner: *const fn (*Display, Atom) callconv(.c) Window,
    XConvertSelection: *const fn (*Display, Atom, Atom, Atom, Window, Time) callconv(.c) c_int,
    XGetEventData: *const fn (*Display, *XGenericEventCookie) callconv(.c) Bool,
    XFreeEventData: *const fn (*Display, *XGenericEventCookie) callconv(.c) void,
    XLookupString: *const fn (*XKeyEvent, [*]u8, c_int, *KeySym, ?*anyopaque) callconv(.c) c_int,
    XKeysymToString: *const fn (KeySym) callconv(.c) ?[*:0]const u8,
    XKeycodeToKeysym: *const fn (*Display, KeyCode, c_int) callconv(.c) KeySym,
    XDisplayKeycodes: *const fn (*Display, *c_int, *c_int) callconv(.c) c_int,
    XGetKeyboardMapping: *const fn (*Display, KeyCode, c_int, *c_int) callconv(.c) ?[*]KeySym,
    XWarpPointer: *const fn (*Display, Window, Window, c_int, c_int, c_uint, c_uint, c_int, c_int) callconv(.c) c_int,
    XGrabPointer: *const fn (*Display, Window, Bool, c_uint, c_int, c_int, Window, Cursor, Time) callconv(.c) c_int,
    XUngrabPointer: *const fn (*Display, Time) callconv(.c) c_int,
    XQueryPointer: *const fn (*Display, Window, *Window, *Window, *c_int, *c_int, *c_int, *c_int, *c_uint) callconv(.c) Bool,
    XTranslateCoordinates: *const fn (*Display, Window, Window, c_int, c_int, *c_int, *c_int, *Window) callconv(.c) Bool,
    XMoveWindow: *const fn (*Display, Window, c_int, c_int) callconv(.c) c_int,
    XResizeWindow: *const fn (*Display, Window, c_uint, c_uint) callconv(.c) c_int,
    XMoveResizeWindow: *const fn (*Display, Window, c_int, c_int, c_uint, c_uint) callconv(.c) c_int,
    XGetWindowAttributes: *const fn (*Display, Window, *XWindowAttributes) callconv(.c) Status,
    XGetWMNormalHints: *const fn (*Display, Window, *XSizeHints, *c_long) callconv(.c) Status,
    XSetWMNormalHints: *const fn (*Display, Window, *XSizeHints) callconv(.c) void,
    XSetWMHints: *const fn (*Display, Window, *XWMHints) callconv(.c) c_int,
    XSetClassHint: *const fn (*Display, Window, *XClassHint) callconv(.c) c_int,
    XSetInputFocus: *const fn (*Display, Window, c_int, Time) callconv(.c) c_int,
    XGetInputFocus: *const fn (*Display, *Window, *c_int) callconv(.c) c_int,
    XRaiseWindow: *const fn (*Display, Window) callconv(.c) c_int,
    XIconifyWindow: *const fn (*Display, Window, c_int) callconv(.c) Status,
    XGetGeometry: *const fn (*Display, Drawable, *Window, *c_int, *c_int, *c_uint, *c_uint, *c_uint, *c_uint) callconv(.c) Status,
    XDisplayWidth: *const fn (*Display, c_int) callconv(.c) c_int,
    XDisplayHeight: *const fn (*Display, c_int) callconv(.c) c_int,
    XDisplayWidthMM: *const fn (*Display, c_int) callconv(.c) c_int,
    XDisplayHeightMM: *const fn (*Display, c_int) callconv(.c) c_int,
    XGetScreenSaver: *const fn (*Display, *c_int, *c_int, *c_int, *c_int) callconv(.c) c_int,
    XSetScreenSaver: *const fn (*Display, c_int, c_int, c_int, c_int) callconv(.c) c_int,
    XCreateFontCursor: *const fn (*Display, c_uint) callconv(.c) Cursor,
    XFreeCursor: *const fn (*Display, Cursor) callconv(.c) c_int,
    XDefineCursor: *const fn (*Display, Window, Cursor) callconv(.c) c_int,
    XUndefineCursor: *const fn (*Display, Window) callconv(.c) c_int,
    XCreateBitmapFromData: *const fn (*Display, Drawable, [*]const u8, c_uint, c_uint) callconv(.c) Pixmap,
    XCreatePixmapCursor: *const fn (*Display, Pixmap, Pixmap, *XColor, *XColor, c_uint, c_uint) callconv(.c) Cursor,
    XFreePixmap: *const fn (*Display, Pixmap) callconv(.c) c_int,
    XStoreBytes: *const fn (*Display, [*]const u8, c_int) callconv(.c) c_int,
    XFetchBytes: *const fn (*Display, *c_int) callconv(.c) ?[*]u8,
    XFree: *const fn (?*anyopaque) callconv(.c) c_int,
    XGetErrorText: *const fn (*Display, c_int, [*]u8, c_int) callconv(.c) c_int,
    XSetErrorHandler: *const fn (XErrorHandler) callconv(.c) XErrorHandler,
    XSync: *const fn (*Display, Bool) callconv(.c) c_int,
    XVisualIDFromVisual: *const fn (*Visual) callconv(.c) VisualID,
    XkbFreeKeyboard: *const fn (*XkbDescRec, c_uint, Bool) callconv(.c) void,
    XkbFreeNames: *const fn (*XkbDescRec, c_uint, Bool) callconv(.c) void,
    XkbGetMap: *const fn (*Display, c_uint, c_uint) callconv(.c) ?*XkbDescRec,
    XkbGetNames: *const fn (*Display, c_uint, *XkbDescRec) callconv(.c) Status,
    XkbGetState: *const fn (*Display, c_uint, *XkbStateRec) callconv(.c) Status,
    XkbKeycodeToKeysym: *const fn (*Display, KeyCode, c_uint, c_uint) callconv(.c) KeySym,
    XkbQueryExtension: *const fn (*Display, *c_int, *c_int, *c_int, *c_int, *c_int) callconv(.c) Bool,
    XkbSelectEventDetails: *const fn (*Display, c_uint, c_uint, c_ulong, c_ulong) callconv(.c) Bool,
    XkbSetDetectableAutoRepeat: *const fn (*Display, Bool, *Bool) callconv(.c) Bool,
};

pub var xlib: ?Xlib = null;
pub var display: ?*Display = null;
pub var screen: c_int = 0;
pub var root: Window = 0;
pub var xi_available = false;
pub var xi_major_opcode: c_int = 0;
pub var xkb_available = false;
pub var xkb_event_base: c_int = 0;
pub var xkb_group: c_uint = 0;
pub var im: XIM = null;
pub var xlib_utf8 = false;
pub var error_handler: XErrorHandler = null;
pub var error_code: c_int = Success;
pub var content_scale_x: f32 = 1.0;
pub var content_scale_y: f32 = 1.0;
pub var wm_delete_window: Atom = 0;
pub var wm_protocols: Atom = 0;
pub var wm_state: Atom = 0;
pub var utf8_string: Atom = 0;
pub var null_atom: Atom = 0;
pub var atom_pair: Atom = 0;
pub var targets: Atom = 0;
pub var multiple: Atom = 0;
pub var primary: Atom = 0;
pub var incr: Atom = 0;
pub var clipboard: Atom = 0;
pub var clipboard_manager: Atom = 0;
pub var save_targets: Atom = 0;
pub var glfw_selection: Atom = 0;
pub var net_wm_icon: Atom = 0;
pub var net_wm_pid: Atom = 0;
pub var net_wm_name: Atom = 0;
pub var net_wm_icon_name: Atom = 0;
pub var net_wm_ping: Atom = 0;
pub var net_supported: Atom = 0;
pub var net_supporting_wm_check: Atom = 0;
pub var net_wm_window_type: Atom = 0;
pub var net_wm_window_type_normal: Atom = 0;
pub var net_wm_fullscreen_monitors: Atom = 0;
pub var net_workarea: Atom = 0;
pub var net_current_desktop: Atom = 0;
pub var net_active_window: Atom = 0;
pub var net_frame_extents: Atom = 0;
pub var net_request_frame_extents: Atom = 0;
pub var net_wm_window_opacity: Atom = 0;
pub var net_wm_bypass_compositor: Atom = 0;
pub var net_wm_cm_sx: Atom = 0;
pub var net_wm_state: Atom = 0;
pub var net_wm_state_fullscreen: Atom = 0;
pub var net_wm_state_above: Atom = 0;
pub var net_wm_state_demands_attention: Atom = 0;
pub var net_wm_state_hidden: Atom = 0;
pub var net_wm_state_maximized_vert: Atom = 0;
pub var net_wm_state_maximized_horz: Atom = 0;
pub var motif_wm_hints: Atom = 0;
pub var xdnd_aware: Atom = 0;
pub var xdnd_enter: Atom = 0;
pub var xdnd_position: Atom = 0;
pub var xdnd_status: Atom = 0;
pub var xdnd_action_copy: Atom = 0;
pub var xdnd_drop: Atom = 0;
pub var xdnd_finished: Atom = 0;
pub var xdnd_selection: Atom = 0;
pub var xdnd_type_list: Atom = 0;
pub var text_uri_list: Atom = 0;
pub var detectable_autorepeat = false;

pub fn loadXlib() bool {
    if (xlib != null) return true;
    var lib = std.DynLib.open("libX11.so.6") catch std.DynLib.open("libX11.so") catch return false;
    errdefer lib.close();

    xlib = .{
        .lib = lib,
        .XOpenDisplay = lookup(&lib, "XOpenDisplay") orelse return false,
        .XCloseDisplay = lookup(&lib, "XCloseDisplay") orelse return false,
        .XConnectionNumber = lookup(&lib, "XConnectionNumber") orelse return false,
        .XDefaultScreen = lookup(&lib, "XDefaultScreen") orelse return false,
        .XDefaultDepth = lookup(&lib, "XDefaultDepth") orelse return false,
        .XDefaultVisual = lookup(&lib, "XDefaultVisual") orelse return false,
        .XRootWindow = lookup(&lib, "XRootWindow") orelse return false,
        .XBlackPixel = lookup(&lib, "XBlackPixel") orelse return false,
        .XWhitePixel = lookup(&lib, "XWhitePixel") orelse return false,
        .XCreateColormap = lookup(&lib, "XCreateColormap") orelse return false,
        .XCreateSimpleWindow = lookup(&lib, "XCreateSimpleWindow") orelse return false,
        .XCreateWindow = lookup(&lib, "XCreateWindow") orelse return false,
        .XDestroyWindow = lookup(&lib, "XDestroyWindow") orelse return false,
        .XFreeColormap = lookup(&lib, "XFreeColormap") orelse return false,
        .XCloseIM = lookup(&lib, "XCloseIM") orelse return false,
        .XCreateIC = lookup(&lib, "XCreateIC") orelse return false,
        .XDestroyIC = lookup(&lib, "XDestroyIC") orelse return false,
        .XGetICValues = lookup(&lib, "XGetICValues") orelse return false,
        .XGetIMValues = lookup(&lib, "XGetIMValues") orelse return false,
        .XInitThreads = lookup(&lib, "XInitThreads") orelse return false,
        .XOpenIM = lookup(&lib, "XOpenIM") orelse return false,
        .XRegisterIMInstantiateCallback = lookup(&lib, "XRegisterIMInstantiateCallback") orelse return false,
        .XResourceManagerString = lookup(&lib, "XResourceManagerString") orelse return false,
        .XrmDestroyDatabase = lookup(&lib, "XrmDestroyDatabase") orelse return false,
        .XrmGetResource = lookup(&lib, "XrmGetResource") orelse return false,
        .XrmGetStringDatabase = lookup(&lib, "XrmGetStringDatabase") orelse return false,
        .XrmInitialize = lookup(&lib, "XrmInitialize") orelse return false,
        .XSetICFocus = lookup(&lib, "XSetICFocus") orelse return false,
        .XSetIMValues = lookup(&lib, "XSetIMValues") orelse return false,
        .XSetLocaleModifiers = lookup(&lib, "XSetLocaleModifiers") orelse return false,
        .XSupportsLocale = lookup(&lib, "XSupportsLocale") orelse return false,
        .XUnregisterIMInstantiateCallback = lookup(&lib, "XUnregisterIMInstantiateCallback") orelse return false,
        .XUnsetICFocus = lookup(&lib, "XUnsetICFocus") orelse return false,
        .Xutf8LookupString = lookup(&lib, "Xutf8LookupString") orelse return false,
        .Xutf8SetWMProperties = lookup(&lib, "Xutf8SetWMProperties") orelse return false,
        .XCreateRegion = lookup(&lib, "XCreateRegion") orelse return false,
        .XDestroyRegion = lookup(&lib, "XDestroyRegion") orelse return false,
        .XMapWindow = lookup(&lib, "XMapWindow") orelse return false,
        .XMapRaised = lookup(&lib, "XMapRaised") orelse return false,
        .XUnmapWindow = lookup(&lib, "XUnmapWindow") orelse return false,
        .XStoreName = lookup(&lib, "XStoreName") orelse return false,
        .XChangeWindowAttributes = lookup(&lib, "XChangeWindowAttributes") orelse return false,
        .XChangeProperty = lookup(&lib, "XChangeProperty") orelse return false,
        .XDeleteProperty = lookup(&lib, "XDeleteProperty") orelse return false,
        .XGetWindowProperty = lookup(&lib, "XGetWindowProperty") orelse return false,
        .XQueryExtension = lookup(&lib, "XQueryExtension") orelse return false,
        .XCheckTypedWindowEvent = lookup(&lib, "XCheckTypedWindowEvent") orelse return false,
        .XSelectInput = lookup(&lib, "XSelectInput") orelse return false,
        .XEventsQueued = lookup(&lib, "XEventsQueued") orelse return false,
        .XNextEvent = lookup(&lib, "XNextEvent") orelse return false,
        .XPeekEvent = lookup(&lib, "XPeekEvent") orelse return false,
        .XPending = lookup(&lib, "XPending") orelse return false,
        .XFilterEvent = lookup(&lib, "XFilterEvent") orelse return false,
        .XFlush = lookup(&lib, "XFlush") orelse return false,
        .XInternAtom = lookup(&lib, "XInternAtom") orelse return false,
        .XSetWMProtocols = lookup(&lib, "XSetWMProtocols") orelse return false,
        .XSendEvent = lookup(&lib, "XSendEvent") orelse return false,
        .XSetSelectionOwner = lookup(&lib, "XSetSelectionOwner") orelse return false,
        .XGetSelectionOwner = lookup(&lib, "XGetSelectionOwner") orelse return false,
        .XConvertSelection = lookup(&lib, "XConvertSelection") orelse return false,
        .XGetEventData = lookup(&lib, "XGetEventData") orelse return false,
        .XFreeEventData = lookup(&lib, "XFreeEventData") orelse return false,
        .XLookupString = lookup(&lib, "XLookupString") orelse return false,
        .XKeysymToString = lookup(&lib, "XKeysymToString") orelse return false,
        .XKeycodeToKeysym = lookup(&lib, "XKeycodeToKeysym") orelse return false,
        .XDisplayKeycodes = lookup(&lib, "XDisplayKeycodes") orelse return false,
        .XGetKeyboardMapping = lookup(&lib, "XGetKeyboardMapping") orelse return false,
        .XWarpPointer = lookup(&lib, "XWarpPointer") orelse return false,
        .XGrabPointer = lookup(&lib, "XGrabPointer") orelse return false,
        .XUngrabPointer = lookup(&lib, "XUngrabPointer") orelse return false,
        .XQueryPointer = lookup(&lib, "XQueryPointer") orelse return false,
        .XTranslateCoordinates = lookup(&lib, "XTranslateCoordinates") orelse return false,
        .XMoveWindow = lookup(&lib, "XMoveWindow") orelse return false,
        .XResizeWindow = lookup(&lib, "XResizeWindow") orelse return false,
        .XMoveResizeWindow = lookup(&lib, "XMoveResizeWindow") orelse return false,
        .XGetWindowAttributes = lookup(&lib, "XGetWindowAttributes") orelse return false,
        .XGetWMNormalHints = lookup(&lib, "XGetWMNormalHints") orelse return false,
        .XSetWMNormalHints = lookup(&lib, "XSetWMNormalHints") orelse return false,
        .XSetWMHints = lookup(&lib, "XSetWMHints") orelse return false,
        .XSetClassHint = lookup(&lib, "XSetClassHint") orelse return false,
        .XSetInputFocus = lookup(&lib, "XSetInputFocus") orelse return false,
        .XGetInputFocus = lookup(&lib, "XGetInputFocus") orelse return false,
        .XRaiseWindow = lookup(&lib, "XRaiseWindow") orelse return false,
        .XIconifyWindow = lookup(&lib, "XIconifyWindow") orelse return false,
        .XGetGeometry = lookup(&lib, "XGetGeometry") orelse return false,
        .XDisplayWidth = lookup(&lib, "XDisplayWidth") orelse return false,
        .XDisplayHeight = lookup(&lib, "XDisplayHeight") orelse return false,
        .XDisplayWidthMM = lookup(&lib, "XDisplayWidthMM") orelse return false,
        .XDisplayHeightMM = lookup(&lib, "XDisplayHeightMM") orelse return false,
        .XGetScreenSaver = lookup(&lib, "XGetScreenSaver") orelse return false,
        .XSetScreenSaver = lookup(&lib, "XSetScreenSaver") orelse return false,
        .XCreateFontCursor = lookup(&lib, "XCreateFontCursor") orelse return false,
        .XFreeCursor = lookup(&lib, "XFreeCursor") orelse return false,
        .XDefineCursor = lookup(&lib, "XDefineCursor") orelse return false,
        .XUndefineCursor = lookup(&lib, "XUndefineCursor") orelse return false,
        .XCreateBitmapFromData = lookup(&lib, "XCreateBitmapFromData") orelse return false,
        .XCreatePixmapCursor = lookup(&lib, "XCreatePixmapCursor") orelse return false,
        .XFreePixmap = lookup(&lib, "XFreePixmap") orelse return false,
        .XStoreBytes = lookup(&lib, "XStoreBytes") orelse return false,
        .XFetchBytes = lookup(&lib, "XFetchBytes") orelse return false,
        .XFree = lookup(&lib, "XFree") orelse return false,
        .XGetErrorText = lookup(&lib, "XGetErrorText") orelse return false,
        .XSetErrorHandler = lookup(&lib, "XSetErrorHandler") orelse return false,
        .XSync = lookup(&lib, "XSync") orelse return false,
        .XVisualIDFromVisual = lookup(&lib, "XVisualIDFromVisual") orelse return false,
        .XkbFreeKeyboard = lookup(&lib, "XkbFreeKeyboard") orelse return false,
        .XkbFreeNames = lookup(&lib, "XkbFreeNames") orelse return false,
        .XkbGetMap = lookup(&lib, "XkbGetMap") orelse return false,
        .XkbGetNames = lookup(&lib, "XkbGetNames") orelse return false,
        .XkbGetState = lookup(&lib, "XkbGetState") orelse return false,
        .XkbKeycodeToKeysym = lookup(&lib, "XkbKeycodeToKeysym") orelse return false,
        .XkbQueryExtension = lookup(&lib, "XkbQueryExtension") orelse return false,
        .XkbSelectEventDetails = lookup(&lib, "XkbSelectEventDetails") orelse return false,
        .XkbSetDetectableAutoRepeat = lookup(&lib, "XkbSetDetectableAutoRepeat") orelse return false,
    };
    xlib_utf8 = true;
    return true;
}

pub fn unloadXlib() void {
    if (xlib) |*lib| lib.lib.close();
    xlib = null;
    xlib_utf8 = false;
    error_handler = null;
    error_code = Success;
    content_scale_x = 1.0;
    content_scale_y = 1.0;
}

fn lookup(lib: *std.DynLib, comptime name: [:0]const u8) ?@TypeOf(@field(@as(Xlib, undefined), name)) {
    return lib.lookup(@TypeOf(@field(@as(Xlib, undefined), name)), name);
}
