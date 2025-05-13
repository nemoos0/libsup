const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gen_exe = b.addExecutable(.{
        .name = "gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("gen/general_category.zig"),
            .target = b.graph.host,
        }),
    });
    const gen_run = b.addRunArtifact(gen_exe);
    const general_category_table = gen_run.addOutputFileArg("general_category_table.zig");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/general_category.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addAnonymousImport("general_category_table", .{
        .root_source_file = general_category_table,
    });

    const mod_test = b.addTest(.{
        .name = "mod",
        .root_module = mod,
    });

    const mod_test_run = b.addRunArtifact(mod_test);

    const test_step = b.step("test", "Run unit test");
    test_step.dependOn(&mod_test_run.step);
}
