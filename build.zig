const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const assert_mod = b.createModule(.{
        .root_source_file = b.path("src/asserts/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const threading_mod = b.createModule(.{
        .root_source_file = b.path("src/threading/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    threading_mod.addImport("assert", assert_mod);

    const events_mod = b.createModule(.{
        .root_source_file = b.path("src/events/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_mod.addImport("assert", assert_mod);
    lib_mod.addImport("threading", threading_mod);
    lib_mod.addImport("events", events_mod);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "LibZ",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    const assert_unit_tests = b.addTest(.{
        .root_module = assert_mod,
    });

    const threading_unit_tests = b.addTest(.{
        .root_module = threading_mod,
    });

    const events_unit_tests = b.addTest(.{
        .root_module = events_mod,
    });

    const run_assert_unit_tests = b.addRunArtifact(assert_unit_tests);
    const run_threading_unit_tests = b.addRunArtifact(threading_unit_tests);
    const run_events_unit_tests = b.addRunArtifact(events_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_assert_unit_tests.step);
    test_step.dependOn(&run_threading_unit_tests.step);
    test_step.dependOn(&run_events_unit_tests.step);
}
