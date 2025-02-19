const std = @import("std");
const debug = std.debug;
const asserts = @import("asserts.zig");

const Atomic = std.atomic.Value;
const Thread = std.Thread;
const BoundedArray = std.BoundedArray;
const FixedDeque = @import("fixed_deque.zig").FixedDeque;

pub const JobHandle = packed struct(u32) {
    index: u16,
    thread: u16,
};

pub const JobQueueConfig = struct {
    // For each thread a seperate queue will be created, this config dictates the size of that queue.
    max_jobs_per_thread: u16,

    // Dictates max number of threads
    max_threads: u16 = 32,

    // Amount of time to wait before trying to fetch a new job from the queue, If the queue is empty,
    // lowering this setting will result in high CPU and thus battery usage.
    idle_sleep_ns: u16 = 50,
};

pub fn JobQueue(comptime config: JobQueueConfig) type {
    const cache_line_size = 64;

    // Should atleast have 2 threads to be able to spawn
    comptime debug.assert(config.max_threads >= 2);

    // For optimization we only allow a count of a multiple of 2
    comptime debug.assert(asserts.isPowerOf2(config.max_jobs_per_thread));

    const ExecData = [52]u8;
    const ExecFn = *const fn (*ExecData) void;

    const Job = struct {
        const Self = @This();

        // The function to call
        exec: ExecFn align(cache_line_size),

        // Data passed to the function
        data: ExecData,

        // Parent job that spawned this job, can be executed in parallel of this job
        parent: ?JobHandle,

        // Jobs that need to be awaited before this job is completed, can be executed in parallel of this job
        job_count: u32,

        // Child jobs, these need to be executed after this job has run
        child_count: u32,
        child_jobs: [14]JobHandle,

        pub fn init(comptime T: type, job: *const T) Self {
            var self: Self = .{
                .exec = undefined,
                .data = undefined,
                .parent = undefined,
                .job_count = 1,
                .child_count = 0,
                .child_jobs = .{undefined} ** 14,
            };

            const bytes = std.mem.asBytes(job);
            @memcpy(self.data[0..bytes.len], bytes);

            const exec: *const fn (*T) void = &@field(T, "exec");

            self.exec = @as(ExecFn, @ptrCast(exec));

            return self;
        }

        pub fn isCompleted(self: *const Self) bool {
            return @atomicLoad(u32, &self.job_count, .monotonic) == 0;
        }
    };

    // comptime debug.assert(@sizeOf(Job) == 128);

    return struct {
        pub const max_jobs_per_thread = config.max_jobs_per_thread;
        pub const sleep_time_ns = config.idle_sleep_ns;
        const max_thread_count = config.max_threads;
        const max_thread_queue_count = max_thread_count + 1;

        const Self = @This();
        const Deque = FixedDeque(*Job, max_jobs_per_thread);
        const ThreadQueues = BoundedArray(Deque, max_thread_queue_count);
        const ThreadJobs = BoundedArray(Jobs, max_thread_queue_count);
        const Jobs = BoundedArray(Job, config.max_jobs_per_thread);
        const Threads = BoundedArray(Thread, max_thread_count);

        const jobs_per_thread_mask = max_jobs_per_thread - 1;

        // Each thread has it's own queue, because we allow for job stealing from other threads the queue
        // itself is not thread local
        threadlocal var thread_queue_index: u32 = 0;

        // Each thread has it's own job buffer containing max_jobs_per_thread jobs.
        // Jobs are allocated from this buffer and deallocated to this buffer. is implemented as a ringbuffer.
        // JobHandle points to an index of this storage.
        // threadlocal var jobs_buffery: Jobs = .{undefined} ** max_jobs_per_thread;
        jobs: ThreadJobs = undefined,

        // All the queues, one per spawned thread plus one for the main thread
        queues: ThreadQueues = undefined,

        // All the threads, should be at most @min(getCpuCount() - 1, max_threads)
        threads: Threads = undefined,

        // Main thread ID, stored so we can assert start is called from the main thread.
        main_thread: Atomic(u64) = .{ .raw = 0 },

        // While true, the threads will keep trying to pick jobs from the queue, if set to false only
        // The picked up jobs will be completed
        is_running: Atomic(bool) = .{ .raw = false },

        pub fn init() Self {
            const thread_count = @min(max_thread_count, (Thread.getCpuCount() catch 2) - 1);
            const thread_queue_count = thread_count + 1;

            var self: Self = .{
                .jobs = ThreadJobs.init(thread_queue_count) catch unreachable,
                .queues = ThreadQueues.init(thread_queue_count) catch unreachable,
                .threads = Threads.init(thread_count) catch unreachable,
            };

            for (self.queues.slice()) |*queue| {
                queue.* = Deque.init();
            }

            return self;
        }

        pub fn start(self: *Self) !void {
            const current_thread = Thread.getCurrentId();
            const prev_thread = self.main_thread.swap(current_thread, .monotonic);
            debug.assert(prev_thread == 0);

            const was_running = self.is_running.swap(true, .monotonic);
            debug.assert(was_running == false);

            for (self.threads.slice(), 0..) |*thread, i| {
                thread.* = try Thread.spawn(.{}, run, .{ self, @as(u32, @intCast(i + 1)) });
            }
        }

        pub fn stop(self: *Self) void {
            const was_running = self.is_running.swap(false, .monotonic);
            debug.assert(was_running);
        }

        pub fn join(self: *Self) void {
            debug.assert(self.isMainThread());

            for (self.threads.slice()) |thread| {
                thread.join();
            }
        }

        pub fn allocate(self: *Self, job: anytype) JobHandle {
            const JobType = @TypeOf(job);

            var jobs = self.getThreadJobBuffer();
            defer jobs.len += 1;

            const job_index: u32 = @intCast(jobs.len & jobs_per_thread_mask);
            jobs.buffer[job_index] = Job.init(JobType, &job);

            return .{
                .index = @intCast(job_index),
                .thread = @intCast(thread_queue_index),
            };
        }

        pub fn schedule(self: *Self, handle: JobHandle) void {
            const queue = self.getThreadQueue();
            const job = self.getJobFromBuffer(handle);

            queue.push(job);
        }

        pub fn wait(self: *Self, handle: JobHandle) void {
            const job = self.getJobFromBuffer(handle);
            while (!job.isCompleted()) {
                self.execNextJob();
            }
        }

        pub fn waitResult(self: *Self, T: type, handle: JobHandle) T {
            const job = self.getJobFromBuffer(handle);
            while (!job.isCompleted()) {
                self.execNextJob();
            }
            return std.mem.bytesToValue(T, &job.data);
        }

        pub fn result(self: *Self, T: type, handle: JobHandle) T {
            debug.assert(self.isCompleted(handle));
            const job = self.getJobFromBuffer(handle);
            return std.mem.bytesToValue(T, &job.data);
        }

        pub fn isMainThread(self: *Self) bool {
            const current_thread = Thread.getCurrentId();
            const main_thread = self.main_thread.load(.monotonic);
            debug.assert(main_thread != 0);

            return main_thread == current_thread;
        }

        pub fn isCompleted(self: *const Self, handle: JobHandle) bool {
            const job = self.getJobFromBufferConst(handle);
            return job.isCompleted();
        }

        fn run(self: *Self, queue_index: u32) void {
            debug.assert(thread_queue_index == 0);

            thread_queue_index = queue_index;

            while (self.is_running.load(.monotonic)) {
                self.execNextJob();
            }
        }

        fn execNextJob(self: *Self) void {
            if (self.getJob()) |job| {
                job.exec(&job.data);
                self.finishJob(job);
            }
        }

        fn getJob(self: *Self) ?*Job {
            var queue = self.getThreadQueue();
            if (queue.pop()) |job| {
                return job;
            }

            for (1..self.queues.len) |i| {
                const index = (i + thread_queue_index) % self.queues.len;
                debug.assert(thread_queue_index != index);

                if (self.queues.buffer[index].steal()) |job| {
                    return job;
                }
            }

            Thread.sleep(config.idle_sleep_ns);

            return null;
        }

        fn finishJob(self: *Self, job: *Job) void {
            const prev = @atomicRmw(u32, &job.job_count, .Sub, 1, .monotonic);
            if (prev == 1) {
                if (job.parent) |parent| {
                    const parent_job = self.getJobFromBuffer(parent);
                    self.finishJob(parent_job);
                }
            }
        }

        inline fn getThreadQueue(self: *Self) *Deque {
            return &self.queues.buffer[thread_queue_index];
        }

        inline fn getThreadJobBuffer(self: *Self) *Jobs {
            return &self.jobs.buffer[thread_queue_index];
        }

        inline fn getJobFromBuffer(self: *Self, handle: JobHandle) *Job {
            debug.assert(handle.thread == thread_queue_index);
            return &self.jobs.buffer[thread_queue_index].buffer[handle.index];
        }

        inline fn getJobFromBufferConst(self: *const Self, handle: JobHandle) *const Job {
            debug.assert(handle.thread == thread_queue_index);
            return &self.jobs.buffer[thread_queue_index].buffer[handle.index];
        }
    };
}

test "JobQueue: size" {
    const testing = std.testing;
    try testing.expectEqual(1, @sizeOf(JobQueue(.{ .max_jobs_per_thread = 4096 }).Jobs));
}

test "JobQueue: can init" {
    const testing = std.testing;
    const config: JobQueueConfig = .{
        .max_jobs_per_thread = 4,
    };
    const jobs = JobQueue(config).init();

    try testing.expectEqual(0, jobs.main_thread.raw);
    try testing.expectEqual(false, jobs.is_running.raw);
}

test "JobQueue: can start and stop" {
    const testing = std.testing;
    const config: JobQueueConfig = .{
        .max_jobs_per_thread = 4,
    };

    var jobs = JobQueue(config).init();

    try jobs.start();
    try testing.expectEqual(true, jobs.is_running.raw);

    jobs.stop();
    try testing.expectEqual(false, jobs.is_running.raw);
}

test "JobQueue: can join before stop" {
    const testing = std.testing;
    const config: JobQueueConfig = .{
        .max_jobs_per_thread = 4,
    };

    var jobs = JobQueue(config).init();

    try jobs.start();
    try testing.expectEqual(true, jobs.is_running.raw);

    // TODO: add job to join threads
    // jobs.join();
    jobs.stop();
    try testing.expectEqual(false, jobs.is_running.raw);
}

test "JobQueue: can join after stop" {
    const testing = std.testing;
    const config: JobQueueConfig = .{
        .max_jobs_per_thread = 4,
    };

    var jobs = JobQueue(config).init();

    try jobs.start();
    try testing.expectEqual(true, jobs.is_running.raw);

    jobs.stop();
    jobs.join();
    try testing.expectEqual(false, jobs.is_running.raw);
}

test "JobQueue: can allocate a jobs" {
    const testing = std.testing;
    const config: JobQueueConfig = .{
        .max_jobs_per_thread = 4,
    };

    const Job = struct {
        pub fn exec(_: *@This()) void {}
    };

    var jobs = JobQueue(config).init();

    try jobs.start();

    const job = jobs.allocate(Job{});
    try testing.expectEqual(0, job.index);

    const job1 = jobs.allocate(Job{});
    try testing.expectEqual(1, job1.index);

    defer jobs.join();
    defer jobs.stop();
}

test "JobQueue: allocating more jobs than config.max_jobs_per_thread will overwrite previously allocated job" {
    const testing = std.testing;
    const config: JobQueueConfig = .{
        .max_jobs_per_thread = 4,
    };

    const Job = struct {
        pub fn exec(_: *@This()) void {}
    };

    var jobs = JobQueue(config).init();

    try jobs.start();

    const job = jobs.allocate(Job{});
    try testing.expectEqual(0, job.index);

    const job1 = jobs.allocate(Job{});
    try testing.expectEqual(1, job1.index);

    const job2 = jobs.allocate(Job{});
    try testing.expectEqual(2, job2.index);

    const job3 = jobs.allocate(Job{});
    try testing.expectEqual(3, job3.index);

    // This will overwrite job at index 0 as it's a ringbuffer.
    const job4 = jobs.allocate(Job{});
    try testing.expectEqual(0, job4.index);

    defer jobs.join();
    defer jobs.stop();
}

test "JobQueue: can schedule jobs before start on main thread" {
    const testing = std.testing;
    const config: JobQueueConfig = .{
        .max_jobs_per_thread = 4,
    };

    const Job = struct {
        foo: u32 = 0,
        pub fn exec(self: *@This()) void {
            self.foo += 1;
        }
    };

    var jobs = JobQueue(config).init();
    const handle = jobs.allocate(Job{});
    jobs.schedule(handle);

    const handle1 = jobs.allocate(Job{});
    jobs.schedule(handle1);

    try testing.expectEqual(2, jobs.getThreadQueue().len());

    try jobs.start();

    defer jobs.join();
    defer jobs.stop();
}
