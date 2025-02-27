# ZLib

A utility library written in zig.



## Features

- Multithreaded job queue implementation.
- Events using callbacks


## Installation

```bash
  zig fetch --save git+https://github.com/ricknijhuis/ZLib.git
```
```zig
const zlib_dep = b.dependency("zlib", .{
    .target = target,
    .optimize = optimize
});
const zlib_lib = zlib_dep.artifact("ZLib");
```
## Usage/Examples

## JobQueue simple usage
```zig
    const testing = std.testing;
    const allocator = testing.allocator;

    // Defines the config for the jobs, available configs are:
    // - max_jobs_per_thread
    // - max_threads
    // - idle_sleep_ns
    const config: JobQueueConfig = .{
        .max_jobs_per_thread = 4,
    };
    // This preallocates the jobs per threads and the queues per thread
    var jobs = try JobQueue(config).init(allocator);
    // Don't forget to cleanup
    defer jobs.deinit();

    // Let's define a job, the job struct size can be at most 76 bytes, if more data is needed it
    // might be best to use a pointer to store to some allocated memory.
    const Job = struct {
        // this function is required. you can discard the parameter if not needed by using the _ syntax.
        pub fn exec(self: *@This()) void {
            std.debug.print("hello", .{});
        }
    }

    // Let's allocate our job, this is very fast as it uses a circular buffer pool to allocate
    // jobs from. Each thread has it's own pool so allocating can be done lock free.
    // Keep in mind that the 'max_jobs_per_thread' count is allocated per thread.
    // This will result in a memory footprint of:
    // 128(total job size) * max_jobs_per_thread * thread count
    const handle = jobs.allocate(Job{});

    // Now we schedule the job.
    // As soon as jobs.start is called it will be picked up by one of the threads.
    jobs.schedule(handle);

    // From this point onwards, any jobs scheduled will be picked up by one of the spawned threads.
    // You can pre-schedule some jobs and then call start but you can also call start first.
    // Is required to be called from the main thread.
    try jobs.start();

    // Here we make sure the job is completed until we continue,
    // while we are waiting this call might pickup other jobs so we do something useful while waiting.
    jobs.wait(handle);

    // Now we stop the threads from picking up other jobs. after this call we can join our threads.
    jobs.stop();

    // Here we call thread.join on all our threads,
    // if stop is not called it will block the calling thread indefinetley.
    // you can always call join though and call stop from another thread.
    // A nicer way to do this might be using something like:
    // defer jobs.join();
    // defer jobs.stop();
    jobs.join();
```

