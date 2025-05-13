const std = @import("std");
const parse = @import("parse.zig");

const GeneralCategory = enum(u5) {
    // zig fmt: off
    Lu, Ll, Lt, Lm, Lo,
    Mn, Mc, Me,
    Nd, Nl, No,
    Pc, Pd, Ps, Pe, Pi, Pf, Po,
    Sm, Sc, Sk, So,
    Zs, Zl, Zp,
    Cc, Cf, Cs, Co, Cn,
    // zig fmt: on
};

pub fn main() !void {
    const gpa = std.heap.smp_allocator;

    const general_cetegories = try gpa.alloc(GeneralCategory, 0x110000);

    {
        const file = try std.fs.cwd().openFile("data/extracted/DerivedGeneralCategory.txt", .{});
        defer file.close();

        while (try parse.nextLine(file)) |line| {
            const range = try parse.columnAsRange(line, 0) orelse unreachable;
            const general_category = parse.columnAsEnum(GeneralCategory, line, 1).?;
            @memset(general_cetegories[range.start..range.end], general_category);
        }
    }

    const block_size = 256;
    const s1, const s2 = try parse.twoStageTable(u8, GeneralCategory, block_size, gpa, general_cetegories);

    const args = try std.process.argsAlloc(gpa);
    std.debug.assert(args.len == 2);

    const output = try std.fs.cwd().createFile(args[1], .{});
    defer output.close();
    const writer = output.writer();

    try writer.writeAll("pub const GeneralCategory = enum(u5) {");
    for (std.meta.fieldNames(GeneralCategory), 0..) |name, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.print("{s}", .{name});
    }
    try writer.writeAll("};");

    try writer.print("pub const block_size = {};", .{block_size});
    try writer.print("pub const s1 = [{}]u8{{", .{s1.len});
    for (s1, 0..) |it, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.print("{}", .{it});
    }
    try writer.writeAll("};");

    try writer.print("pub const s2 = [{}]GeneralCategory{{", .{s2.len});
    for (s2, 0..) |it, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.print(".{s}", .{@tagName(it)});
    }
    try writer.writeAll("};");
}
