const std = @import("std");
const debug = std.debug;

pub const GrowFactor = enum {
    one,
    double,
    super_linearly,
};

pub fn grow(comptime factor: GrowFactor, current: usize, minimum: usize) usize {
    if (comptime factor == .one) {
        return growOne(current, minimum);
    } else if (comptime factor == .double) {
        return growDouble(current, minimum);
    } else if (comptime factor == .super_linearly) {
        return growSuperLinearly(current, minimum);
    }
}

pub inline fn growOne(current: usize, minimum: usize) usize {
    debug.assert(minimum > current);
    return minimum;
}

pub fn growDouble(current: usize, minimum: usize) usize {
    debug.assert(minimum > current);

    var new = current;
    if (current == 0) {
        @branchHint(.unlikely);
        new = 1;
    }

    while (true) {
        new *|= 2;
        if (new >= minimum) {
            return new;
        }
    }
}

pub fn growSuperLinearly(current: usize, minimum: usize) usize {
    debug.assert(minimum > current);

    var new = current;

    while (true) {
        new +|= new / 2 + 8;
        if (new >= minimum)
            return new;
    }
}

test "grow: takes correct function at comptime" {
    const testing = std.testing;

    try testing.expectEqual(1, grow(GrowFactor.one, 0, 1));
    try testing.expectEqual(2, grow(GrowFactor.double, 0, 1));
    try testing.expectEqual(8, grow(GrowFactor.super_linearly, 0, 1));
}

test "growOne: always returns minimum" {
    const math = std.math;
    const testing = std.testing;

    // Can grow with current value = 0
    try testing.expectEqual(1, growOne(0, 1));
    // Can grow with current value != 0
    try testing.expectEqual(2, growOne(1, 2));
    // Returns max int
    try testing.expectEqual(math.maxInt(usize), growOne(0, math.maxInt(usize)));
}

test "growDouble: grows by doubling, returns always larger or equal to minimum" {
    const math = std.math;
    const testing = std.testing;

    // Can grow with current value = 0
    try testing.expectEqual(2, growDouble(0, 2));
    // Can grow with current value != 0
    try testing.expectEqual(2, growDouble(1, 2));
    // Returns max int
    try testing.expectEqual(math.maxInt(usize), growDouble(0, math.maxInt(usize) - 1));
}

test "growSuperLinearly: grows superlinearly, returns always larger or equal to minimum" {
    const math = std.math;
    const testing = std.testing;

    // Can grow with current value = 0
    try testing.expectEqual(8, growSuperLinearly(0, 2));
    // Can grow with current value != 0
    try testing.expectEqual(9, growSuperLinearly(1, 2));
    // Returns max int
    try testing.expectEqual(math.maxInt(usize), growSuperLinearly(0, math.maxInt(usize) - 8));
}
