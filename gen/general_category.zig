const std = @import("std");
const ucd = @import("ucd.zig");

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

    const general_categories = try gpa.alloc(GeneralCategory, 0x110000);

    {
        const file = try std.fs.cwd().openFile("data/extracted/DerivedGeneralCategory.txt", .{});
        defer file.close();

        while (try ucd.nextLine(file)) |line| {
            const range = try ucd.asRange(ucd.column(line, 0).?);
            const general_category = std.meta.stringToEnum(GeneralCategory, ucd.column(line, 1).?).?;
            @memset(general_categories[range.start..range.end], general_category);
        }
    }

    const bs = 256;
    const s1, const s2 = try ucd.twoStageTable(u8, GeneralCategory, bs, gpa, general_categories);

    const args = try std.process.argsAlloc(gpa);
    std.debug.assert(args.len == 2);

    const output = try std.fs.cwd().createFile(args[1], .{});
    defer output.close();
    const writer = output.writer();

    try ucd.printConst("GeneralCategory", GeneralCategory, writer);
    try ucd.printConst("bs", bs, writer);
    try ucd.printConst("s1", s1, writer);
    try ucd.printConst("s2", s2, writer);
}
