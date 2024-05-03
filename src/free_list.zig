const std = @import("std");

const Allocator = std.mem.Allocator;

const FreeList = @This();

const Config = struct {
    max_allocation_count: u64 = 100000,
};

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

pub fn init(allocator: Allocator, total_size: u64, options: Config) !FreeList {
    var self: FreeList = undefined;

    self.allocator = allocator;
    self.total_size = total_size;

    const min_allocation: u64 = @sizeOf(*u8);
    const max_entries: u64 = @min(total_size / min_allocation, options.max_allocation_count);
    self.nodes = try allocator.alloc(Node, max_entries);

    std.log.info("Created freelist of total size: {d} and max entries: {d}, mem req: {d:.2} Mb", .{
        total_size,
        max_entries,
        @as(f64, @floatFromInt(@sizeOf(FreeList) + @sizeOf(Node) * max_entries)) / 1024.0 / 1024.0,
    });

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
            result_offset = node.data.offset;

            if (prev_node) |prev| {
                _ = prev.removeNext();
            } else {
                _ = self.list.popFirst();
            }
            node.* = invalid_node;

            return result_offset;
        }

        if (node.data.size > size) {
            result_offset = node.data.offset;

            node.data.size -= size;
            node.data.offset += size;

            return result_offset;
        }
        prev_node = node;
    }

    return error.OutOfFreeListSpace;
}

pub fn free(self: *FreeList, offset: u64, size: u64) !void {
    if (self.list.first == null) {
        var new_node = try self.getNode();
        new_node.data.offset = offset;
        new_node.data.size = size;

        self.list.first = new_node;
        return;
    }

    var curr_node = self.list.first;
    var prev_node: ?*Node = null;

    while (curr_node) |node| : (curr_node = node.next) {
        if (node.data.offset == offset) {
            return error.NodeAlreadyFreed;
        }

        if (node.data.offset + node.data.size == offset) {
            // can be appended to the right of this node
            node.data.size += size;

            tryMergeNext(node);
            return;
        }

        if (node.data.offset > offset) {
            // iterated beyond the space to be freed so add a new node
            var new_node = try self.getNode();
            new_node.data.offset = offset;
            new_node.data.size = size;

            if (prev_node) |prev| {
                prev.insertAfter(new_node);
            } else {
                self.list.prepend(new_node);
            }

            tryMergeNext(new_node);
            tryMergePrev(new_node, prev_node);
            return;
        }

        if (node.next == null and node.data.offset + node.data.size < offset) {
            // reached last node and last node offset + last node size < offset add a new node
            var new_node = try self.getNode();
            new_node.data.offset = offset;
            new_node.data.size = size;

            node.insertAfter(new_node);
            return;
        }

        prev_node = node;
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

pub fn copyTo(self: *const FreeList, to: *FreeList) !void {
    if (self.total_size > to.total_size) {
        return error.CannotCopyToSmallerFreeList;
    }

    const size_diff = to.total_size - self.total_size;

    // copy the data from the old to the new onw
    var curr_from_node = self.list.first;

    if (curr_from_node == null) {
        // the whole space is allocated
        var to_first = to.list.first.?;
        to_first.data.offset = self.total_size;
        to_first.data.size = size_diff;

        return;
    }

    to.list.first.?.* = invalid_node;
    to.list.first = null;

    var curr_to_node = to.list.first;

    while (curr_from_node) |from_node| : (curr_from_node = from_node.next) {
        var new_node = try to.getNode();
        new_node.data.offset = from_node.data.offset;
        new_node.data.size = from_node.data.size;

        if (curr_to_node) |to_node| {
            to_node.insertAfter(new_node);
        } else {
            to.list.first = new_node;
        }

        curr_to_node = new_node;

        if (from_node.next == null) {
            if (from_node.data.offset + from_node.data.size == self.total_size) {
                // the last old node was spanning to the end of the old free list
                new_node.data.size += size_diff;
            } else {
                var new_end_node = try to.getNode();
                new_end_node.data.offset = self.total_size;
                new_end_node.data.size = size_diff;

                new_node.insertAfter(new_end_node);
            }
        }
    }
}

pub fn resize(self: *FreeList, new_total_size: u64, options: Config) !void {
    if (new_total_size < self.total_size) {
        return error.CannotResizeFreeListToSmallerSize;
    }

    var new_free_list = try FreeList.init(self.allocator, new_total_size, options);

    try self.copyTo(&new_free_list);

    self.deinit();
    self.* = new_free_list;
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

inline fn tryMergeNext(node: *Node) void {
    if (node.next) |next| {
        if (next.data.offset == node.data.offset + node.data.size) {
            node.data.size += next.data.size;
            _ = node.removeNext();
            next.* = invalid_node;
        }
    }
}

inline fn tryMergePrev(node: *Node, prev_node: ?*Node) void {
    if (prev_node) |prev| {
        if (prev.data.offset + prev.data.size == node.data.offset) {
            prev.data.size += node.data.size;
            _ = prev.removeNext();
            node.* = invalid_node;
        }
    }
}

test "allocate and free" {
    std.testing.log_level = .info;
    std.log.info("\n", .{});

    const printList = struct {
        fn print(self: *FreeList, op: []const u8) void {
            std.log.info("LIST AFTER: {s}", .{op});
            var node = self.list.first;
            while (node) |n| : (node = n.next) {
                std.log.info("- (offset: {d}, size: {d})", .{ n.data.offset, n.data.size });
            }
        }
    }.print;

    const total_size = 512;

    var fl = try FreeList.init(std.testing.allocator, total_size, .{});
    defer fl.deinit();

    const offset_1 = try fl.alloc(64);
    try std.testing.expectEqual(0, offset_1);
    printList(&fl, "alloc 64");

    const offset_2 = try fl.alloc(32);
    try std.testing.expectEqual(64, offset_2);
    printList(&fl, "alloc 32");

    const offset_3 = try fl.alloc(64);
    try std.testing.expectEqual(96, offset_3);
    printList(&fl, "alloc 64");

    var free_space = fl.getFreeSpace();
    try std.testing.expectEqual(total_size - 160, free_space);

    try fl.free(offset_2, 32);
    printList(&fl, "free 32 at 64");

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(total_size - 128, free_space);

    const offset_4 = try fl.alloc(64);
    try std.testing.expectEqual(160, offset_4);
    printList(&fl, "alloc 64");

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(total_size - 192, free_space);

    try fl.free(offset_1, 64);
    printList(&fl, "free 64 at 0");

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(total_size - 128, free_space);

    try fl.free(offset_3, 64);
    printList(&fl, "free 64 at 96");

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(total_size - 64, free_space);

    try fl.free(offset_4, 64);
    printList(&fl, "free 64 at 160");

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(total_size, free_space);

    const offset_5 = try fl.alloc(512);
    try std.testing.expectEqual(0, offset_5);
    printList(&fl, "alloc 512");

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(0, free_space);

    const offset_6_or_error = fl.alloc(64);
    try std.testing.expectError(error.OutOfFreeListSpace, offset_6_or_error);
    printList(&fl, "fail to alloc 64");

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(0, free_space);

    try fl.free(offset_5, 512);
    printList(&fl, "free 512 at 0");

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(total_size, free_space);

    const offset_7 = try fl.alloc(512);
    try std.testing.expectEqual(0, offset_7);
    printList(&fl, "alloc 512");

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(0, free_space);

    try fl.resize(1024, .{});
    printList(&fl, "resize to 1024");

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(512, free_space);

    try fl.resize(2048, .{});
    printList(&fl, "resize to 2048");

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(1536, free_space);

    const offset_8 = try fl.alloc(512);
    try std.testing.expectEqual(512, offset_8);
    printList(&fl, "alloc 512");

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(1024, free_space);

    try fl.free(offset_7, 512);
    printList(&fl, "free 512 at 0");

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(1536, free_space);

    try fl.resize(4096, .{});
    printList(&fl, "resize to 4096");

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(3584, free_space);

    const offset_9 = try fl.alloc(2048);
    try std.testing.expectEqual(1024, offset_9);
    printList(&fl, "alloc 2048");

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(1536, free_space);

    const offset_10 = try fl.alloc(1024);
    try std.testing.expectEqual(3072, offset_10);
    printList(&fl, "alloc 1024");

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(512, free_space);

    try fl.free(offset_9, 2048);
    printList(&fl, "free 2048 at 1024");

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(2560, free_space);

    try fl.resize(8192, .{});
    printList(&fl, "resize to 8192");

    free_space = fl.getFreeSpace();
    try std.testing.expectEqual(6656, free_space);

    try fl.resize(1024 * 1024 * 1024, .{});
    printList(&fl, "resize to 1 Gb");

    try fl.resize(2 * 1024 * 1024 * 1024, .{ .max_allocation_count = 1000000 });
    printList(&fl, "resize to 2 Gb");
}
