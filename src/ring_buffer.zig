const std = @import("std");
const debug = std.debug;
const asserts = @import("asserts.zig");

pub fn RingBuffer(comptime T: type, comptime size: usize) type {
    comptime debug.assert(asserts.isPowerOf2(size));

    return struct {
        buffer: [size]T,
    };
}
