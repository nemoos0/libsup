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

    const decomposition_gen = b.addRunArtifact(
        b.addExecutable(.{
            .name = "decomposition_gen",
            .root_module = b.createModule(.{
                .root_source_file = b.path("gen/decomposition.zig"),
                .target = b.graph.host,
            }),
        }),
    );
    const decomposition_table = decomposition_gen.addOutputFileArg("decomposition_table.zig");

    const decomposition_mod = b.createModule(.{
        .root_source_file = b.path("src/decomposition.zig"),
        .target = target,
        .optimize = optimize,
    });
    decomposition_mod.addAnonymousImport("decomposition_table", .{
        .root_source_file = decomposition_table,
    });

    test_step.dependOn(&b.addRunArtifact(
        b.addTest(.{
            .name = "decomposition_test",
            .root_module = decomposition_mod,
        }),
    ).step);

    const composition_gen = b.addRunArtifact(
        b.addExecutable(.{
            .name = "composition_gen",
            .root_module = b.createModule(.{
                .root_source_file = b.path("gen/composition.zig"),
                .target = b.graph.host,
            }),
        }),
    );
    const composition_table = composition_gen.addOutputFileArg("composition_table.zig");

    const composition_mod = b.createModule(.{
        .root_source_file = b.path("src/composition.zig"),
        .target = target,
        .optimize = optimize,
    });
    composition_mod.addAnonymousImport("composition_table", .{
        .root_source_file = composition_table,
    });

    test_step.dependOn(&b.addRunArtifact(
        b.addTest(.{
            .name = "composition_test",
            .root_module = composition_mod,
        }),
    ).step);

    const combining_class_gen = b.addRunArtifact(
        b.addExecutable(.{
            .name = "combining_class_gen",
            .root_module = b.createModule(.{
                .root_source_file = b.path("gen/combining_class.zig"),
                .target = b.graph.host,
            }),
        }),
    );
    const combining_class_table = combining_class_gen.addOutputFileArg("combining_class_table.zig");

    const combining_class_mod = b.createModule(.{
        .root_source_file = b.path("src/combining_class.zig"),
        .target = target,
        .optimize = optimize,
    });
    combining_class_mod.addAnonymousImport("combining_class_table", .{
        .root_source_file = combining_class_table,
    });

    test_step.dependOn(&b.addRunArtifact(
        b.addTest(.{
            .name = "combining_class_test",
            .root_module = combining_class_mod,
        }),
    ).step);
}
