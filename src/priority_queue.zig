const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const MotionQueue = @import("game.zig").MotionQueue;
const RingBuffer = @import("ring_buffer.zig").RingBuffer;

// pub fn main() !void {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     const g_allocator = gpa.allocator();
//     defer {
//         // _ = gpa.detectLeaks();
//         // const deinit_status = gpa.deinit();
//         // if (deinit_status == .leak) std.testing.expect(false) catch {
//         //     @panic("gpa leaked");
//         // };
//     }
//     const allocator = g_allocator;
//     const stdout_file = std.io.getStdOut().writer();
//     var bw = std.io.bufferedWriter(stdout_file);
//     defer bw.flush() catch unreachable;
//     const outbw = bw.writer();

//     var pqueue = PriorityQueueTree.init(allocator);
//     defer pqueue.deinit();
//     try pqueue.insert(1);
//     try pqueue.insert(120);
//     try pqueue.insert(10);
//     try pqueue.insert(100);
//     // try outbw.print("{?}\n", .{pqueue.head});
//     try printNode(outbw, pqueue.head);

//     try outbw.print(" invariant: {}\n", .{pqueue.checkInvariant()});
//     // try pqueue.insert(2);
//     var pq2 = PriorityQueue.init(allocator);
//     defer pq2.deinit();
//     try pq2.insert(1);
//     try pq2.insert(4);
//     try pq2.insert(2);
//     try pq2.insert(3);
//     try outbw.print("pq2 {}\n", .{.{ .data = pq2.data, .count = pq2.count }});
//     try outbw.print("remove {?}\n", .{try pq2.remove()});
//     try outbw.print("remove {?}\n", .{try pq2.remove()});
//     try outbw.print("remove {?}\n", .{try pq2.remove()});
//     try outbw.print("pq2 {}\n", .{.{ .data = pq2.data, .count = pq2.count }});

//     const decls = @typeInfo(PriorityQueue).Struct.decls;
//     const Declaration = std.builtin.Type.Declaration;
//     const decls_copy = try allocator.dupe(Declaration, decls);

//     const lessThanFn = struct {
//         pub fn less(ctx: void, lhs: Declaration, rhs: Declaration) bool {
//             _ = ctx;
//             var li: usize = 0;
//             var ri: usize = 0;
//             while (lhs.name[li] != 0 and rhs.name[ri] != 0 and lhs.name[li] == rhs.name[ri]) : ({
//                 li += 1;
//                 ri += 1;
//             }) {}
//             return lhs.name[li] < rhs.name[ri];
//         }
//     };
//     for (decls_copy, 0..) |d, i| {
//         try outbw.print("{}:decls {s}\n", .{ i, d.name });
//     }
//     std.mem.sort(Declaration, decls_copy, {}, lessThanFn.less);
//     for (decls_copy, 0..) |d, i| {
//         try outbw.print("{}:decls {s}\n", .{ i, d.name });
//     }
//     allocator.free(decls_copy);
// }
pub fn PriorityQueue(T: type) type {
    return struct {
        data: []T,
        count: u64 = 0,
        allocator: Allocator,
        lessThanFn: *const fn (lhs: T, rhs: T) bool,
        animations: *RingBuffer(MotionQueue),
        swapAnimation: *const fn (animations: *RingBuffer(MotionQueue), n1: usize, n2: usize) void,
        const Self = @This();
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.data);
        }
        pub fn init(
            allocator: Allocator,
            lessThanFn: *const fn (lhs: T, rhs: T) bool,
            animations: *RingBuffer(MotionQueue),
            swapAnimation: *const fn (animations: *RingBuffer(MotionQueue), n1: usize, n2: usize) void,
        ) Self {
            return .{ .data = &[0]T{}, .count = 0, .allocator = allocator, .lessThanFn = lessThanFn, .swapAnimation = swapAnimation, .animations = animations };
        }
        pub fn fixInvariant(self: *Self) void {
            if (self.count == 0) {
                return;
            }
            var child_index: u64 = self.count - 1;
            var parent_index: u64 = undefined;
            while (child_index > 0) : (child_index = parent_index) {
                parent_index = (child_index - 1) / 2;
                if (self.lessThanFn(self.data[child_index], self.data[parent_index])) {
                    // if (self.data[parent_index].value > self.data[child_index].value) {
                    const tmp = self.data[child_index];
                    self.data[child_index] = self.data[parent_index];
                    self.data[parent_index] = tmp;
                    self.swapAnimation(self.animations, child_index, parent_index);
                } else {
                    break;
                }
            }
        }
        pub fn insert(self: *Self, value: T) !void {
            if (self.count == self.data.len) {
                // المجموع الجديد
                const size_new = 2 * self.count + 1;
                const data_new: []T = try self.allocator.alloc(T, size_new);
                @memcpy(data_new.ptr, self.data);
                self.allocator.free(self.data);
                self.data = data_new;
            }
            self.data[self.count] = value;
            self.count += 1;
            self.fixInvariant();
        }
        pub fn remove(self: *Self) !?T {
            const top = removeAssumeCapacity(self);
            if (2 * self.count + 1 < self.data.len) {
                const size_new = (self.data.len - 1) / 2;
                const data_new: []T = try self.allocator.alloc(T, size_new);
                @memcpy(data_new, self.data.ptr);
                self.allocator.free(self.data);
                self.data = data_new;
            }
            return top;
        }
        pub fn removeAssumeCapacity(self: *Self) ?T {
            if (self.count == 0)
                return null;
            const top = self.data[0];
            self.data[0] = self.data[self.count - 1];
            self.count -= 1;
            var parent_index: u64 = 0;
            var __guard: u64 = self.count;
            while (parent_index < self.count and __guard > 0) {
                __guard -= 1;
                var kid = 2 * parent_index + 1;
                if (kid >= self.count)
                    break;
                const right_kid = kid + 1;
                if (right_kid < self.count and self.lessThanFn(self.data[right_kid], self.data[kid]))
                    kid = right_kid;
                if (self.lessThanFn(self.data[kid], self.data[parent_index])) {
                    const tmp = self.data[kid];
                    self.data[kid] = self.data[parent_index];
                    self.data[parent_index] = tmp;

                    parent_index = kid;
                } else break;
            }
            return top;
        }
    };
}

// pub fn printNode(writer: anytype, n: ?*PriorityQueueTree.Node) !void {
//     if (n) |node| {
//         _ = try writer.write("{ ");
//         try writer.print(":data {}, :full {},", .{ node.data, node.full });
//         _ = try writer.write(" :left ");
//         try printNode(writer, node.left);
//         _ = try writer.write(", :right ");
//         try printNode(writer, node.right);
//         _ = try writer.write(" }");
//     } else {
//         try writer.writeAll("nil");
//     }
// }

// const PriorityQueueTree = struct {
//     head: ?*Node,
//     allocator: Allocator,

//     const Self = @This();
//     const Node = struct {
//         data: u8,
//         left: ?*Node = null,
//         right: ?*Node = null,
//         full: bool = true,

//         pub fn init(allocator: Allocator, value: u8) !*Node {
//             var node = try allocator.create(Node);
//             node.data = value;
//             node.left = null;
//             node.right = null;
//             node.full = true;
//             return node;
//         }
//     };
//     pub fn init(allocator: Allocator) PriorityQueueTree {
//         return PriorityQueueTree{ .head = null, .allocator = allocator };
//     }
//     pub fn deinit(self: *Self) void {
//         self.deinitNode(self.head);
//     }
//     fn deinitNode(self: *Self, n: ?*Node) void {
//         if (n) |node| {
//             self.deinitNode(node.left);
//             self.deinitNode(node.right);
//             self.allocator.destroy(node);
//         }
//     }
//     pub fn checkInvariant(self: Self) bool {
//         return checkInvariantNode(self.head);
//     }
//     fn checkInvariantNode(n: ?*Node) bool {
//         if (n) |node| {
//             const res_left = checkInvariantNode(node.left);
//             const res_right = checkInvariantNode(node.right);
//             if (!(res_left and res_right)) {
//                 return false;
//             }
//             if (node.left) |side| {
//                 if (side.data < node.data)
//                     return false;
//             }
//             if (node.right) |side| {
//                 if (side.data < node.data)
//                     return false;
//                 if (node.left == null)
//                     return false;
//             }
//             const full_kids = (node.left == null and node.right == null) or
//                 (node.left != null and node.right != null and node.left.?.full and node.right.?.full);
//             if (full_kids != node.full)
//                 return false;
//         }
//         return true;
//     }
//     pub fn insert(self: *Self, value: u8) !void {
//         if (self.head == null) {
//             self.head = try Node.init(self.allocator, value);
//             return;
//         }
//         var head = self.head.?;
//         const value_node = try Node.init(self.allocator, value);
//         if (insertNode(head, value_node)) |side| {
//             switch (side) {
//                 .left => if (head.left.?.data < head.data) {
//                     const child_node: *Node = head.left.?;
//                     head.left = child_node.left;
//                     child_node.left = head;

//                     const tmp: *Node = child_node.right.?;
//                     child_node.right = head.right;
//                     head.right = tmp;

//                     head = child_node;
//                 },
//                 .right => if (head.right.?.data < head.data) {
//                     const child_node: *Node = head.right.?;
//                     head.right = child_node.right;
//                     child_node.right = head;

//                     const tmp: *Node = child_node.left.?;
//                     child_node.left = head.left;
//                     head.left = tmp;

//                     head = child_node;
//                 },
//             }
//         }
//     }
//     const Side = enum { left, right };
//     pub fn insertNode(root: *Node, value_node: *Node) ?Side {
//         root.full = false;
//         // if (root.full) {
//         //     root.full = false;
//         // }
//         if (root.left) |left| {
//             const insert_left: bool = !left.full or (root.right != null and root.right.?.full);
//             if (insert_left) {
//                 if (insertNode(left, value_node)) |left_side| {
//                     if (fixInvariant(root, left, left_side)) {
//                         return Side.left;
//                     }
//                 }
//                 return null;
//             } else {
//                 if (root.right) |right| {
//                     if (insertNode(right, value_node)) |right_side| {
//                         if (fixInvariant(root, right, right_side)) {
//                             return Side.right;
//                         }
//                     }
//                     // if (root.right.full) {
//                     //     root.full = true;
//                     // }
//                     root.full = root.right.?.full;
//                     return null;
//                 } else {
//                     root.right = value_node;
//                     root.full = true;
//                     return Side.right;
//                 }
//             }
//         } else {
//             root.left = value_node;
//             return Side.left;
//         }
//     }
//     fn fixInvariant(root: *Node, child_node: *Node, grandchild_side: Side) bool {
//         switch (grandchild_side) {
//             .left => {
//                 var grandchild_node: *Node = child_node.left.?;
//                 if (grandchild_node.data < child_node.data) {
//                     if (child_node == root.left) {
//                         root.left = grandchild_node;
//                     } else if (child_node == root.right) {
//                         root.right = grandchild_node;
//                     } else unreachable;
//                     child_node.left = grandchild_node.left;
//                     grandchild_node.left = child_node;

//                     const tmp: ?*Node = child_node.right;
//                     child_node.right = grandchild_node.right;
//                     grandchild_node.right = tmp;

//                     const tmp_full: bool = child_node.full;
//                     child_node.full = grandchild_node.full;
//                     grandchild_node.full = tmp_full;
//                     return true;
//                 }
//                 return false;
//             },
//             .right => {
//                 var grandchild_node: *Node = child_node.right.?;
//                 if (grandchild_node.data < child_node.data) {
//                     if (child_node == root.left) {
//                         root.left = grandchild_node;
//                     } else if (child_node == root.right) {
//                         root.right = grandchild_node;
//                     } else unreachable;
//                     child_node.right = grandchild_node.right;
//                     grandchild_node.right = child_node;

//                     const tmp: ?*Node = child_node.left;
//                     child_node.left = grandchild_node.left;
//                     grandchild_node.left = tmp;

//                     const tmp_full: bool = child_node.full;
//                     child_node.full = grandchild_node.full;
//                     grandchild_node.full = tmp_full;
//                     return true;
//                 }
//                 return false;
//             },
//         }
//     }
//     pub fn remove(self: *Self) ?u8 {
//         _ = self;
//         return null;
//     }
// };
