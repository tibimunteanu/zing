const std = @import("std");
const ID = @import("../utils.zig").ID;

pub const Texture = struct {
    id: u32,
    width: u32,
    height: u32,
    channel_count: u8,
    has_transparency: bool,
    generation: ID,
    internal_data: *anyopaque,
};
