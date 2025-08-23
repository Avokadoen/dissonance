const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = .{
        .enable_ztracy = b.option(
            bool,
            "enable_ztracy",
            "Enable Tracy profile markers",
        ) orelse false,
        .enable_ecez_dev_markers = b.option(
            bool,
            "enable_ecez_dev_markers",
            "Enable Tracy profile markers added by ecez internally, should be false for most projects",
        ) orelse false,
    };

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "dissonance",
        .root_module = exe_mod,
    });

    // Link raylib
    {
        const raylib = raylib_dep.module("raylib"); // main raylib module
        const raygui = raylib_dep.module("raygui"); // raygui module
        const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library
        exe.linkLibrary(raylib_artifact);
        exe.root_module.addImport("raylib", raylib);
        exe.root_module.addImport("raygui", raygui);
    }

    // link ecez and ztracy
    {
        const ecez = b.dependency("ecez", .{
            .enable_ztracy = options.enable_ztracy,
            .enable_ecez_dev_markers = options.enable_ecez_dev_markers,
        });
        const ecez_module = ecez.module("ecez");

        exe.root_module.addImport("ecez", ecez_module);

        const ztracy_dep = ecez.builder.dependency("ztracy", .{
            .enable_ztracy = options.enable_ztracy,
        });
        const ztracy_module = ztracy_dep.module("root");

        exe.root_module.addImport("ztracy", ztracy_module);

        exe.linkLibrary(ztracy_dep.artifact("tracy"));
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
