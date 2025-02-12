const std = @import("std");
const mem = std.mem;
const core = @import("core");
const grow_factors = core.grow_factors;

const Allocator = std.mem.Allocator;
const GrowFactor = grow_factors.GrowFactor;

pub const ListConfig = struct {
    grow_factor: GrowFactor = GrowFactor.super_linearly,
    alignment: ?u29 = null,
    error_handling: bool = true,
};

pub fn List(comptime T: type, comptime config: ListConfig) type {
    return struct {
        const Self = @This();
        const Impl = if (config.error_handling) ListAlignedImpl else ListAlignedNoErrorImpl;

        pub const Slice = if (config.alignment) |a| ([]align(a) T) else []T;

        items: Slice,
        capacity: usize,

        pub const empty: Self = .{
            .items = &.{},
            .capacity = 0,
        };

        pub const initCapacity = Impl.initCapacity;

        const ListAlignedImpl = struct {
            pub fn initCapacity(allocator: anytype, capacity: usize) Allocator.Error!Self {
                var self: Self = Self.empty;
            }
        };

        const ListAlignedNoErrorImpl = struct {
            pub fn initCapacity(allocator: anytype, capacity: usize) Self {}
        };
    };
}
