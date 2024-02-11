const std = @import("std");

pub const Texture = struct {
    name: []const u8,
    width: u32,
    height: u32,
    channel_count: u8,
    has_transparency: bool,
    generation: ?u32,
    internal_data: ?*anyopaque,

    pub fn init() Texture {
        var self: Texture = undefined;
        self.name = "";
        self.width = 0;
        self.height = 0;
        self.channel_count = 0;
        self.has_transparency = false;
        self.generation = null;
        self.internal_data = null;
        return self;
    }

    pub fn deinit(self: *Texture) void {
        self.name = "";
        self.width = 0;
        self.height = 0;
        self.channel_count = 0;
        self.has_transparency = false;
        self.generation = null;
        self.internal_data = null;
    }
};
