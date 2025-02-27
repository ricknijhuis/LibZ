const std = @import("std");

const BoundedArray = std.BoundedArray;

/// Allows registering event handlers for a given event type.
/// The given size specifies the max ammount of registered callbacks.
pub fn Events(EventT: type, comptime size: u32) type {
    comptime std.debug.assert(size > 0);

    return struct {
        const Self = @This();

        pub fn Callback(ContextT: type) type {
            return struct {
                context: ContextT,
                callback: *const fn (ctx: ContextT, event: *const EventT) bool,
            };
        }

        callbacks: BoundedArray(Callback(*anyopaque), @intCast(size)),

        pub fn init() Self {
            return .{
                .callbacks = .{},
            };
        }

        /// Registers a callback, the given function will be called if event of given type is fired using the fire function
        /// If a non null context is passed, that context will be send to the callback together with the event.
        pub fn register(
            self: *Self,
            context: anytype,
            comptime callbackFn: fn (@TypeOf(context), *const EventT) bool,
        ) void {
            std.debug.assert(@TypeOf(context) != @TypeOf(null));

            self.callbacks.addOneAssumeCapacity().* = .{
                .context = @alignCast(@ptrCast(context)),
                .callback = @ptrCast(&callbackFn),
            };
        }

        pub fn unregister(
            self: *Self,
            context: anytype,
            comptime callbackFn: fn (@TypeOf(context), *const EventT) bool,
        ) ?@TypeOf(context) {
            for (self.callbacks.slice(), 0..) |callback, i| {
                if (callback.context == @as(@TypeOf(callback.context), @alignCast(@ptrCast(context))) and
                    callback.callback == @as(@TypeOf(callback.callback), @ptrCast(&callbackFn)))
                {
                    return @alignCast(@ptrCast(self.callbacks.swapRemove(i).context));
                }
            }
            return null;
        }

        pub fn fire(self: *const Self, event: *const EventT) bool {
            for (self.callbacks.slice()) |callback| {
                if (callback.callback(callback.context, event)) {
                    return true;
                }
            }
            return false;
        }
    };
}

test "Events: if callback returns true, fire returns true" {
    const testing = std.testing;

    const Event = struct {
        foo: i32,
    };

    const Callback = struct {
        const Self = @This();
        bar: i32,
        pub fn handleEvent(self: *Self, event: *const Event) bool {
            self.bar += event.foo;
            return true;
        }
    };

    var events = Events(Event, 8).init();
    try testing.expectEqual(0, events.callbacks.len);

    var callback: Callback = .{
        .bar = 2,
    };

    events.register(&callback, comptime Callback.handleEvent);
    const handled = events.fire(&.{ .foo = 1 });
    try testing.expectEqual(true, handled);
}

test "Events: if callback returns false, fire returns false" {
    const testing = std.testing;

    const Event = struct {
        foo: i32,
    };

    const Callback = struct {
        const Self = @This();
        bar: i32,
        pub fn handleEvent(self: *Self, event: *const Event) bool {
            self.bar += event.foo;
            return false;
        }
    };

    var events = Events(Event, 8).init();
    try testing.expectEqual(0, events.callbacks.len);

    var callback: Callback = .{
        .bar = 2,
    };

    events.register(&callback, comptime Callback.handleEvent);

    const handled = events.fire(&.{ .foo = 1 });
    try testing.expectEqual(false, handled);
}

test "Events: all callbacks are executed till true is returned" {
    const testing = std.testing;

    const Event = struct {
        foo: i32,
    };

    const Callback = struct {
        const Self = @This();
        bar: i32,
        pub fn handleEvent(self: *Self, event: *const Event) bool {
            self.bar += event.foo;
            return false;
        }

        pub fn handleEventTrue(self: *Self, event: *const Event) bool {
            self.bar += event.foo;
            return true;
        }
    };

    var events = Events(Event, 8).init();
    try testing.expectEqual(0, events.callbacks.len);

    var callback: Callback = .{
        .bar = 2,
    };

    events.register(&callback, comptime Callback.handleEvent);
    events.register(&callback, comptime Callback.handleEvent);
    events.register(&callback, comptime Callback.handleEventTrue);
    events.register(&callback, comptime Callback.handleEvent);

    const handled = events.fire(&.{ .foo = 1 });
    try testing.expectEqual(true, handled);
    try testing.expectEqual(5, callback.bar);
}

test "Events: multiple callback context types can be registered" {
    const testing = std.testing;

    const Event = struct {
        foo: i32,
    };

    const Callback = struct {
        const Self = @This();
        bar: i32,
        pub fn handleEvent(self: *Self, event: *const Event) bool {
            self.bar += event.foo;
            return false;
        }
    };
    const Callback1 = struct {
        const Self = @This();
        bar: i32,
        pub fn handleEvent(self: *Self, event: *const Event) bool {
            self.bar += event.foo;
            return false;
        }
    };

    var events = Events(Event, 8).init();
    try testing.expectEqual(0, events.callbacks.len);

    var callback: Callback = .{
        .bar = 0,
    };

    var callback1: Callback1 = .{ .bar = 1 };

    events.register(&callback, comptime Callback.handleEvent);
    events.register(&callback1, comptime Callback1.handleEvent);

    _ = events.fire(&.{ .foo = 1 });
    try testing.expectEqual(1, callback.bar);
    try testing.expectEqual(2, callback1.bar);
}
