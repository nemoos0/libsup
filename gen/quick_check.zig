const std = @import("std");
const ucd = @import("ucd.zig");

const QuickCheck = packed struct(u8) {
    nfd: Value,
    nfc: Value,
    nfkd: Value,
    nfkc: Value,
};

const Value = enum(u2) { yes, no, maybe };

pub fn main() !void {
    const gpa = std.heap.smp_allocator;

    const quick_checks = try gpa.alloc(QuickCheck, 0x110000);
    @memset(quick_checks, .{
        .nfd = .yes,
        .nfc = .yes,
        .nfkd = .yes,
        .nfkc = .yes,
    });

    {
        const file = try std.fs.cwd().openFile("data/DerivedNormalizationProps.txt", .{});
        defer file.close();

        line: while (try ucd.nextLine(file)) |line| {
            const prop = ucd.column(line, 1) orelse unreachable;
            if (std.mem.endsWith(u8, prop, "_QC")) {
                const range = try ucd.asRange(ucd.column(line, 0).?);

                var buf: [16]u8 = undefined;
                const prefix = std.ascii.lowerString(&buf, prop[0 .. prop.len - 3]);

                const value: Value = blk: {
                    const value_letter = ucd.column(line, 2).?;
                    if (std.mem.eql(u8, "N", value_letter)) {
                        break :blk .no;
                    } else if (std.mem.eql(u8, "M", value_letter)) {
                        break :blk .maybe;
                    } else unreachable;
                };

                inline for (comptime std.meta.fieldNames(QuickCheck)) |name| {
                    if (std.mem.eql(u8, name, prefix)) {
                        for (range.start..range.end) |code| {
                            @field(quick_checks[code], name) = value;
                        }
                        continue :line;
                    }
                }

                unreachable;
            }
        }
    }

    const block_size = 128;
    const s1, const s2 = try ucd.twoStageTable(u8, QuickCheck, block_size, gpa, quick_checks);

    const args = try std.process.argsAlloc(gpa);
    std.debug.assert(args.len == 2);

    const file = try std.fs.cwd().createFile(args[1], .{});
    defer file.close();
    const writer = file.writer();

    try ucd.printConst("QuickCheck", QuickCheck, writer);
    try ucd.printConst("Value", Value, writer);
    try ucd.printConst("bs", block_size, writer);
    try ucd.printConst("s1", s1, writer);
    try ucd.printConst("s2", s2, writer);
}
