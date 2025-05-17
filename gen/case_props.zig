const std = @import("std");
const ucd = @import("ucd.zig");

const CaseProps = packed struct(u8) {
    uppercase: bool = false,
    lowercase: bool = false,
    cased: bool = false,
    case_ignorable: bool = false,
    changes_when_lowercased: bool = false,
    changes_when_titlecased: bool = false,
    changes_when_uppercased: bool = false,
    changes_when_casefolded: bool = false,
};

pub fn main() !void {
    const gpa = std.heap.smp_allocator;

    const props = try gpa.alloc(CaseProps, 0x110000);
    @memset(props, .{});

    {
        const file = try std.fs.cwd().openFile("data/DerivedCoreProperties.txt", .{});
        defer file.close();

        while (try ucd.nextLine(file)) |line| {
            inline for (comptime std.meta.fieldNames(CaseProps)) |name| {
                if (std.ascii.eqlIgnoreCase(name, ucd.column(line, 1).?)) {
                    const range = try ucd.asRange(ucd.column(line, 0).?);
                    for (range.start..range.end) |i| @field(props[i], name) = true;
                }
            }
        }
    }

    const block_size = 128;
    const s1, const s2 = try ucd.twoStageTable(u8, CaseProps, block_size, gpa, props);

    const args = try std.process.argsAlloc(gpa);
    std.debug.assert(args.len == 2);

    const output = try std.fs.cwd().createFile(args[1], .{});
    defer output.close();
    const writer = output.writer();

    try ucd.printConst("CaseProps", CaseProps, writer);
    try ucd.printConst("bs", block_size, writer);
    try ucd.printConst("s1", s1, writer);
    try ucd.printConst("s2", s2, writer);
}
