const core = @import("core");
const grow_factors = core.grow_factors;
const GrowFactor = grow_factors.GrowFactor;

pub fn List(T: type, grow_factor: GrowFactor) type {
    return ListAligned(T, grow_factor, @alignOf(T));
}

pub fn ListAligned(T: type, grow_factor: GrowFactor, alignment: u29) type {
    return struct {
        const Self = @This();
    };
}
