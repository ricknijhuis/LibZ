const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core_mod = b.createModule(.{
        .root_source_file = b.path("src/core/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const containers_mod = b.createModule(.{
        .root_source_file = b.path("src/containers/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    containers_mod.addImport("core", core_mod);

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib_mod.addImport("core", core_mod);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "LibZ",
        .root_module = lib_mod,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    const core_unit_tests = b.addTest(.{
        .root_module = core_mod,
    });

    const containers_unit_tests = b.addTest(.{
        .root_module = containers_mod,
    });

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_core_unit_tests = b.addRunArtifact(core_unit_tests);
    const run_containers_unit_tests = b.addRunArtifact(containers_unit_tests);
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_core_unit_tests.step);
    test_step.dependOn(&run_containers_unit_tests.step);
    test_step.dependOn(&run_lib_unit_tests.step);
}
