const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run unit test");

    const encodings_mod = b.createModule(.{
        .root_source_file = b.path("src/encodings.zig"),
        .target = target,
        .optimize = optimize,
    });

    test_step.dependOn(&b.addRunArtifact(
        b.addTest(.{
            .name = "encodings_test",
            .root_module = encodings_mod,
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

    const grapheme_gen = b.addRunArtifact(
        b.addExecutable(.{
            .name = "grapheme_gen",
            .root_module = b.createModule(.{
                .root_source_file = b.path("gen/grapheme.zig"),
                .target = b.graph.host,
            }),
        }),
    );
    const grapheme_table = grapheme_gen.addOutputFileArg("grapheme_table.zig");

    const grapheme_mod = b.createModule(.{
        .root_source_file = b.path("src/grapheme.zig"),
        .target = target,
        .optimize = optimize,
    });
    grapheme_mod.addImport("encodings", encodings_mod);
    grapheme_mod.addAnonymousImport("grapheme_table", .{
        .root_source_file = grapheme_table,
    });

    test_step.dependOn(&b.addRunArtifact(
        b.addTest(.{
            .name = "grapheme_test",
            .root_module = grapheme_mod,
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

    const normalization_mod = b.createModule(.{
        .root_source_file = b.path("src/normalization.zig"),
        .target = target,
        .optimize = optimize,
    });
    normalization_mod.addImport("encodings", encodings_mod);
    normalization_mod.addAnonymousImport("combining_class_table", .{ .root_source_file = combining_class_table });
    normalization_mod.addAnonymousImport("decomposition_table", .{ .root_source_file = decomposition_table });
    normalization_mod.addAnonymousImport("composition_table", .{ .root_source_file = composition_table });
    normalization_mod.addAnonymousImport("quick_check_table", .{ .root_source_file = quick_check_table });

    test_step.dependOn(&b.addRunArtifact(
        b.addTest(.{
            .name = "normalization_test",
            .root_module = normalization_mod,
        }),
    ).step);

    const case_props_gen = b.addRunArtifact(
        b.addExecutable(.{
            .name = "case_props_gen",
            .root_module = b.createModule(.{
                .root_source_file = b.path("gen/case_props.zig"),
                .target = b.graph.host,
            }),
        }),
    );
    const case_props_table = case_props_gen.addOutputFileArg("case_props_table.zig");

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

    const case_mod = b.createModule(.{
        .root_source_file = b.path("src/case.zig"),
        .target = target,
        .optimize = optimize,
    });
    case_mod.addImport("encodings", encodings_mod);
    case_mod.addAnonymousImport("case_props_table", .{ .root_source_file = case_props_table });
    case_mod.addAnonymousImport("case_mapping_table", .{ .root_source_file = case_mapping_table });
    case_mod.addAnonymousImport("case_folding_table", .{ .root_source_file = case_folding_table });

    test_step.dependOn(&b.addRunArtifact(
        b.addTest(.{
            .name = "case_test",
            .root_module = case_mod,
        }),
    ).step);

    const sup_mod = b.addModule("sup", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    sup_mod.addImport("encodings", encodings_mod);
    sup_mod.addImport("grapheme", grapheme_mod);
    sup_mod.addImport("case", case_mod);
    sup_mod.addImport("normalization", normalization_mod);
}
