const std = @import("std");

pub const Texture = struct {
    id: u32,
    width: u32,
    height: u32,
    channel_count: u8,
    has_transparency: bool,
    generation: ?u32,
    internal_data: ?*anyopaque,

    pub fn init() Texture {
        var self: Texture = undefined;
        self.id = 0;
        self.width = 0;
        self.height = 0;
        self.channel_count = 0;
        self.has_transparency = false;
        self.generation = null;
        self.internal_data = null;
        return self;
    }

    pub fn deinit(self: *Texture) void {
        self.id = 0;
        self.width = 0;
        self.height = 0;
        self.channel_count = 0;
        self.has_transparency = false;
        self.generation = null;
        self.internal_data = null;
    }
};
