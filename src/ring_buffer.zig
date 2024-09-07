const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const copyForwards = std.mem.copyForwards;

pub fn RingBuffer(comptime T: type) type {
    return struct {
        data: []T,
        read_index: usize,
        write_index: usize,

        const Self = @This();
        pub const Error = error{Full};

        pub fn init(allocator: Allocator, capacity: usize) Allocator.Error!Self {
            const data = try allocator.alloc(T, capacity);

            return Self{ .data = data, .read_index = 0, .write_index = 0 };
        }
        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self);
            self.* = undefined;
        }
        pub fn append(self: *Self, item: T) Error!void {
            if (self.isFull()) return Error.Full;
            self.appendAssumeCapacity(item);
        }
        pub fn appendAssumeCapacity(self: *Self, item: T) void {
            self.data[self.mask(self.write_index)] = item;
            self.write_index = self.mask2(self.write_index + 1);
        }
        pub fn popOrNull(self: *Self) ?T {
            if (self.isEmpty()) return null;
            const item = self.data[self.mask(self.read_index)];
            self.read_index = self.mask2(self.read_index + 1);
            return item;
        }
        pub fn isFull(self: Self) bool {
            // difference between read_index and write_index is the amount of elements
            return self.mask2(self.read_index + self.data.len) == self.write_index;
        }
        pub fn isEmpty(self: Self) bool {
            return self.read_index == self.write_index;
        }
        pub fn mask(self: Self, index: usize) usize {
            return index % self.data.len;
        }
        pub fn mask2(self: Self, index: usize) usize {
            return index % (2 * self.data.len);
        }
    };
}
