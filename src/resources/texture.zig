const std = @import("std");

pub const Texture = struct {
    id: u32,
    width: u32,
    height: u32,
    channel_count: u8,
    has_transparency: bool,
    generation: u32,
    internal_data: *anyopaque,
};
