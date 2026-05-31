const objc = @import("objc.zig");

pub const Window = extern struct {
    window: objc.c.id,
    view: objc.c.id,
    delegate: objc.c.id,
    should_close: bool,
    maximized: bool,
    user_pointer: ?*anyopaque,
    callback_id: usize,
    cursor_mode: c_int,
    modifier_flags: usize,
};

pub const Cursor = extern struct {
    cursor: objc.c.id,
};
