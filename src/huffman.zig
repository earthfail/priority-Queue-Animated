const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const PriorityQueue = @import("priority_queue.zig").PriorityQueue;
const KV = std.AutoHashMap(u8, u32).KV;
// FIXME: reorganize the code because a cow could make a more beautiful shit.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const g_allocator = gpa.allocator();
    defer {
        _ = gpa.detectLeaks();
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.testing.expect(false) catch {
            @panic("gpa leaked");
        };
    }
    // _ = g_allocator;
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    defer bw.flush() catch unreachable;
    const outbw = bw.writer();
    // try outbw.print("Salam\n", .{});

    // const message = "salim khatib and his friends";
    const message = "aabbcccd";
    var freq = std.AutoArrayHashMap(u8, u32).init(g_allocator);
    for (message) |c| {
        const entry = try freq.getOrPut(c);
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }

    const Pool = struct {
        pool: []Node = undefined,
        i: usize = 1,
        pub fn init(allocator: Allocator, size: usize) !@This() {
            const pool = try allocator.alloc(Node, size);
            return .{ .pool = pool, .i = 1 };
        }
        pub fn request(self: *@This()) *Node {
            if (self.i == self.pool.len)
                return &self.pool[0];
            self.i += 1;
            return &self.pool[self.i - 1];
        }
    };
    try outbw.print("count: {}\n", .{freq.count()});
    const size = freq.count() * 2;
    var pool = try Pool.init(g_allocator, size);
    // var entries = try g_allocator.alloc(KV, count);

    var entries = PriorityQueue(*Node).init(g_allocator, lessfn);
    {
        var iter = freq.iterator();
        while (iter.next()) |entry| {
            // entries[i] = KV{ .key = entry.key_ptr.*, .value = entry.value_ptr.* };
            // const n = try g_allocator.create(Node);
            // n.right = null;
            // n.left = null;
            var n = pool.request();
            n.right = null;
            n.left = null;
            n.value = KV{ .key = entry.key_ptr.*, .value = entry.value_ptr.* };
            try entries.insert(n);
        }
    }
    while (entries.count > 1) {
        const first = entries.removeAssumeCapacity().?;
        const second = entries.removeAssumeCapacity().?;

        var n = pool.request();
        n.left = first;
        n.right = second;
        n.value.value = first.value.value + second.value.value;

        entries.insert(n) catch unreachable;
    }
    try outbw.print("nodes: {}\n", .{countNodes(entries.data[0])});
    try outbw.print("depth: {}\n", .{depthTree(entries.data[0])});
    // std.mem.sort(KV, entries, {}, lessfn);
    try printNode(outbw, entries.data[0]);
    try outbw.print("\n", .{});

    const Encode = struct {
        table: std.AutoArrayHashMap(u8, []u8),
        root: *Node,
        buffer: []u8,
        const Self = @This();
        pub fn init(allocator: Allocator, root: *Node) !Self {
            const max_depth = depthTree(root); // the number of branches to any leaf is strictly less than max_depth
            const buffer = try allocator.alloc(u8, max_depth);
            buffer[0] = 0; // in case we only have one character we encode it as 0
            return .{ .table = std.AutoArrayHashMap(u8, []u8).init(allocator), .root = root, .buffer = buffer };
        }
        pub fn deinit(self: *Self) void {
            self.table.allocator.free(self.buffer);
            {
                var iter = self.table.iterator();
                while (iter.next()) |entry| {
                    self.table.allocator.free(entry.value_ptr.*);
                }
            }
            self.table.deinit();
        }
        pub fn generate(self: *Self) !void {
            try generateNode(self, self.root, 0);
        }
        fn generateNode(self: *Self, n: *Node, i: usize) !void {
            if (n.left == null and n.right == null) {
                const encoding = try self.table.allocator.alloc(u8, i);
                @memcpy(encoding, self.buffer.ptr);
                try self.table.put(n.value.key, encoding);
            } else {
                assert(i < self.buffer.len);
                self.buffer[i] = 0;
                if (n.left) |side| {
                    try generateNode(self, side, i + 1);
                }
                self.buffer[i] = 1;
                if (n.right) |side| {
                    try generateNode(self, side, i + 1);
                }
            }
        }
    };
    var table = try Encode.init(g_allocator, entries.data[0]);
    try table.generate();
    {
        var iter = table.table.iterator();
        while (iter.next()) |entry| {
            try outbw.print("q: \\{c}, p: {any}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }
    // I regret not using defer. Don't be like me now, defer code and don't defer work.
    freq.deinit();
    entries.deinit();
    table.deinit();
    g_allocator.free(pool.pool);
}
fn depthTree(n: ?*Node) u32 {
    if (n) |node| {
        return 1 + @max(depthTree(node.left), depthTree(node.right));
    } else return 0;
}
fn countNodes(n: ?*Node) u32 {
    if (n) |node| {
        return 1 + countNodes(node.left) + countNodes(node.right);
    } else return 0;
}
// prints the tree in edn format. pipe the result into `bb -e "(pprint *input*)"` (babashka, a clojure interpreter)
fn printNode(writer: anytype, n: ?*Node) !void {
    if (n) |node| {
        _ = try writer.write("{ ");
        defer _ = writer.write(" }") catch null;
        const leaf: bool = node.left == null and node.right == null;
        if (leaf) {
            try writer.print(":letter \\{c}", .{node.value.key});
            return;
        }
        try writer.print(":freq {}, ", .{node.value.value});

        _ = try writer.write(":left ");
        try printNode(writer, node.left);
        _ = try writer.write(", :right ");
        try printNode(writer, node.right);
    } else {
        try writer.writeAll("nil");
    }
}
fn lessfn(lhs: *Node, rhs: *Node) bool {
    return lhs.value.value < rhs.value.value;
}
const Node = struct {
    value: KV,
    right: ?*Node = null,
    left: ?*Node = null,
};
