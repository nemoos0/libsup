const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run unit test");

    const codepoint_mod = b.createModule(.{
        .root_source_file = b.path("src/codepoint.zig"),
        .target = target,
        .optimize = optimize,
    });

    test_step.dependOn(&b.addRunArtifact(
        b.addTest(.{
            .name = "codepoint_test",
            .root_module = codepoint_mod,
        }),
    ).step);

    const general_category_gen = b.addRunArtifact(
        b.addExecutable(.{
            .name = "general_category_gen",
            .root_module = b.createModule(.{
                .root_source_file = b.path("gen/general_category.zig"),
                .target = b.graph.host,
            }),
        }),
    );
    const general_category_table = general_category_gen.addOutputFileArg("general_category_table.zig");

    const general_category_mod = b.createModule(.{
        .root_source_file = b.path("src/general_category.zig"),
        .target = target,
        .optimize = optimize,
    });
    general_category_mod.addAnonymousImport("general_category_table", .{
        .root_source_file = general_category_table,
    });

    test_step.dependOn(&b.addRunArtifact(
        b.addTest(.{
            .name = "general_category_test",
            .root_module = general_category_mod,
        }),
    ).step);

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

    const quick_check_gen = b.addRunArtifact(
        b.addExecutable(.{
            .name = "quick_check_gen",
            .root_module = b.createModule(.{
                .root_source_file = b.path("gen/quick_check.zig"),
                .target = b.graph.host,
            }),
        }),
    );
    const quick_check_table = quick_check_gen.addOutputFileArg("quick_check_table.zig");

    const quick_check_mod = b.createModule(.{
        .root_source_file = b.path("src/quick_check.zig"),
        .target = target,
        .optimize = optimize,
    });
    quick_check_mod.addAnonymousImport("quick_check_table", .{
        .root_source_file = quick_check_table,
    });

    test_step.dependOn(&b.addRunArtifact(
        b.addTest(.{
            .name = "quick_check_test",
            .root_module = quick_check_mod,
        }),
    ).step);

    const normalization_mod = b.createModule(.{
        .root_source_file = b.path("src/normalization.zig"),
        .target = target,
        .optimize = optimize,
    });
    normalization_mod.addImport("codepoint", codepoint_mod);
    normalization_mod.addImport("quick_check", quick_check_mod);
    normalization_mod.addImport("combining_class", combining_class_mod);
    normalization_mod.addImport("composition", composition_mod);
    normalization_mod.addImport("decomposition", decomposition_mod);

    test_step.dependOn(&b.addRunArtifact(
        b.addTest(.{
            .name = "normalization_test",
            .root_module = normalization_mod,
        }),
    ).step);

    const case_mapping_gen = b.addRunArtifact(
        b.addExecutable(.{
            .name = "case_mapping_gen",
            .root_module = b.createModule(.{
                .root_source_file = b.path("gen/case_mapping.zig"),
                .target = b.graph.host,
            }),
        }),
    );
    const case_mapping_table = case_mapping_gen.addOutputFileArg("case_mapping_table.zig");

    const case_mapping_mod = b.createModule(.{
        .root_source_file = b.path("src/case_mapping.zig"),
        .target = target,
        .optimize = optimize,
    });
    case_mapping_mod.addAnonymousImport("case_mapping_table", .{
        .root_source_file = case_mapping_table,
    });

    test_step.dependOn(&b.addRunArtifact(
        b.addTest(.{
            .name = "case_mapping_test",
            .root_module = case_mapping_mod,
        }),
    ).step);

    const case_folding_gen = b.addRunArtifact(
        b.addExecutable(.{
            .name = "case_folding_gen",
            .root_module = b.createModule(.{
                .root_source_file = b.path("gen/case_folding.zig"),
                .target = b.graph.host,
            }),
        }),
    );
    const case_folding_table = case_folding_gen.addOutputFileArg("case_folding_table.zig");

    const case_folding_mod = b.createModule(.{
        .root_source_file = b.path("src/case_folding.zig"),
        .target = target,
        .optimize = optimize,
    });
    case_folding_mod.addAnonymousImport("case_folding_table", .{
        .root_source_file = case_folding_table,
    });

    test_step.dependOn(&b.addRunArtifact(
        b.addTest(.{
            .name = "case_folding_test",
            .root_module = case_folding_mod,
        }),
    ).step);
}
