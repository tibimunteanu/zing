const std = @import("std");

const Allocator = std.mem.Allocator;

const FreeList = @This();

const NodeData = struct {
    offset: u64 = invalid_id,
    size: u64 = invalid_id,
};
const List = std.SinglyLinkedList(NodeData);
const Node = List.Node;

const invalid_id = std.math.maxInt(u64);
const invalid_node = Node{ .data = NodeData{} };

allocator: Allocator,
nodes: []Node,
total_size: u64,
list: List,

pub fn init(allocator: Allocator, total_size: u64) !FreeList {
    var self: FreeList = undefined;

    self.allocator = allocator;
    self.total_size = total_size;

    const max_entries = total_size / @sizeOf(*u8);
    self.nodes = try allocator.alloc(Node, max_entries);

    self.list = List{};
    self.reset();

    return self;
}

pub fn deinit(self: *FreeList) void {
    self.allocator.free(self.nodes);
    self.* = undefined;
}

pub fn alloc(self: *FreeList, size: u64) !u64 {
    var result_offset: u64 = undefined;

    var curr_node = self.list.first;
    var prev_node: ?*Node = null;

    while (curr_node) |node| : (curr_node = node.next) {
        if (node.data.size == size) {
            // NOTE: exact match. just return the node.
            result_offset = node.data.offset;
            if (prev_node) |prev| {
                _ = prev.removeNext();
            } else {
                _ = self.list.popFirst();
            }
            node.* = invalid_node;
            return result_offset;
        } else if (node.data.size > size) {
            // NOTE: larger. deduct the memory from it and move the offset by that amount.
            result_offset = node.data.offset;
            node.data.size -= size;
            node.data.offset += size;
            return result_offset;
        }
        prev_node = node;
    }

    std.log.warn("FreeList free space: {d}", .{self.getFreeSpace()});

    return error.OutOfFreeListSpace;
}

pub fn free(self: *FreeList, offset: u64, size: u64) !void {
    if (self.list.first == null) {
        var new_node = try self.getNode();
        new_node.data.offset = offset;
        new_node.data.size = size;

        self.list.first = new_node;
        return;
    } else {
        var curr_node = self.list.first;
        var prev_node: ?*Node = null;

        while (curr_node) |node| : (curr_node = node.next) {
            if (node.data.offset == offset) {
                // TODO: this should never fire as there should not exist a free node at the same offset as an allocated block.
                node.data.size *= size;

                // if next free node is adjacent, merge them
                if (node.next) |next| {
                    if (next.data.offset == node.data.offset + node.data.size) {
                        node.data.size += next.data.size;
                        _ = node.removeNext();
                        next.* = invalid_node;
                    }
                }
                return;
            } else if (node.data.offset > offset) {
                // NOTE: iterated beyond the space to be freed. get a new free node.
                var new_node = try self.getNode();
                new_node.data.offset = offset;
                new_node.data.size = size;

                if (prev_node) |prev| {
                    // insert the new node between node and prev
                    prev.insertAfter(new_node);
                } else {
                    // the new node becomes the head
                    self.list.prepend(new_node);
                }

                // if next free node is adjacent, merge them
                if (new_node.next) |next| {
                    if (next.data.offset == new_node.data.offset + new_node.data.size) {
                        new_node.data.size += next.data.size;
                        _ = new_node.removeNext();
                        next.* = invalid_node;
                    }
                }

                // if prev free node is adjacent, merge them
                if (prev_node) |prev| {
                    if (prev.data.offset + prev.data.size == new_node.data.offset) {
                        prev.data.size += new_node.data.size;
                        _ = prev.removeNext();
                        new_node.* = invalid_node;
                    }
                }
                return;
            }
            prev_node = node;
        }
    }
    return error.InvalidFreeListBlock;
}

pub fn reset(self: *FreeList) void {
    self.nodes[0].data.offset = 0;
    self.nodes[0].data.size = self.total_size;
    self.nodes[0].next = null;

    self.list.first = &self.nodes[0];

    for (self.nodes[1..]) |*node| {
        node.* = invalid_node;
    }
}

pub fn resize(self: *FreeList, new_total_size: u64) !void {
    if (new_total_size < self.total_size) {
        return error.CannotResizeFreeListToSmallerSize;
    }

    const size_diff = new_total_size - self.total_size;

    // take a copy of the free list
    var old = self.*;
    defer old.deinit();

    // create the new one
    self.* = try FreeList.init(self.allocator, new_total_size);

    // copy the data from the old to the new onw
    var curr_old_node = old.list.first;
    var curr_node = self.list.first.?;

    if (curr_old_node == null) {
        // NOTE: if there's no head, then the whole space is allocated.
        // set the new head at offset = old list size
        curr_node.data.offset = old.total_size;
        curr_node.data.size = size_diff;
    } else {
        while (curr_old_node) |old_node| : (curr_old_node = old_node.next) {
            var new_node = try self.getNode();
            new_node.data.offset = old_node.data.offset;
            new_node.data.size = old_node.data.size;
            curr_node.insertAfter(new_node);
            curr_node = new_node;

            if (old_node.next) |old_node_next| {
                old_node = old_node_next;
            } else {
                // finished copying all old nodes.
                if (old_node.data.offset + old_node.data.size == old.total_size) {
                    // the last old node was spanning to the end of the old free list
                    new_node.data.size += size_diff;
                } else {
                    var new_end_node = try self.getNode();
                    new_end_node.data.offset = old.total_size;
                    new_end_node.data.size = size_diff;
                    curr_node.insertAfter(new_end_node);
                }
                break;
            }
        }
    }
}

pub fn getFreeSpace(self: *FreeList) u64 {
    var total: u64 = 0;

    var curr_node = self.list.first;
    while (curr_node) |node| : (curr_node = node.next) {
        total += node.data.size;
    }

    return total;
}

inline fn getNode(self: *FreeList) !*Node {
    for (self.nodes) |*node| {
        if (node.data.offset == invalid_id) {
            return node;
        }
    }
    return error.ExceededMaxAllocations;
}

test "allocate and free" {
    const total_size = 512;

    var fl = try FreeList.init(std.testing.allocator, total_size);
    defer fl.deinit();

    const offset_1 = try fl.alloc(64);
    try std.testing.expectEqual(0, offset_1);

    const offset_2 = try fl.alloc(32);
    try std.testing.expectEqual(64, offset_2);

    const offset_3 = try fl.alloc(64);
    try std.testing.expectEqual(96, offset_3);

    var free_space = fl.getFreeSpace();
    try std.testing.expectEqual(total_size - 160, free_space);

    try fl.free(offset_2, 32);

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(total_size - 128, free_space);

    const offset_4 = try fl.alloc(64);
    try std.testing.expectEqual(160, offset_4);

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(total_size - 192, free_space);

    try fl.free(offset_1, 64);

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(total_size - 128, free_space);

    try fl.free(offset_3, 64);

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(total_size - 64, free_space);

    try fl.free(offset_4, 64);

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(total_size, free_space);

    const offset_5 = try fl.alloc(512);
    try std.testing.expectEqual(0, offset_5);

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(0, free_space);

    const offset_6_or_error = fl.alloc(64);
    try std.testing.expectError(error.OutOfFreeListSpace, offset_6_or_error);

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(0, free_space);

    try fl.free(offset_5, 512);

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(total_size, free_space);
}
