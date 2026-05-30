const std = @import("std");

pub fn BoundedArray(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        buffer: [capacity]T = undefined,
        len: usize = 0,

        pub fn init(len: usize) !Self {
            if (len > capacity) return error.Overflow;
            return .{ .len = len };
        }

        pub fn fromSlice(values: []const T) !Self {
            var self = try init(values.len);
            @memcpy(self.buffer[0..values.len], values);
            return self;
        }

        pub fn append(self: *Self, value: T) !void {
            if (self.len == capacity) return error.Overflow;
            self.buffer[self.len] = value;
            self.len += 1;
        }

        pub fn appendNTimes(self: *Self, value: T, count: usize) !void {
            if (self.len + count > capacity) return error.Overflow;
            for (0..count) |_| {
                self.buffer[self.len] = value;
                self.len += 1;
            }
        }

        pub fn resize(self: *Self, new_len: usize) !void {
            if (new_len > capacity) return error.Overflow;
            self.len = new_len;
        }

        pub fn slice(self: *Self) []T {
            return self.buffer[0..self.len];
        }

        pub fn constSlice(self: *const Self) []const T {
            return self.buffer[0..self.len];
        }

        pub fn get(self: *const Self, index: usize) T {
            std.debug.assert(index < self.len);
            return self.buffer[index];
        }
    };
}
