const std = @import("std");
const parse = @import("parse.zig");

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

        line: while (try parse.nextLine(file)) |line| {
            const prop = parse.column(line, 1) orelse unreachable;
            if (std.mem.endsWith(u8, prop, "_QC")) {
                const range = try parse.columnAsRange(line, 0) orelse unreachable;

                var buf: [16]u8 = undefined;
                const prefix = std.ascii.lowerString(&buf, prop[0 .. prop.len - 3]);

                const value: Value = blk: {
                    const value_letter = parse.column(line, 2).?;
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

    const bs = 128;
    const s1, const s2 = try parse.twoStageTable(u8, QuickCheck, bs, gpa, quick_checks);

    const args = try std.process.argsAlloc(gpa);
    std.debug.assert(args.len == 2);

    const file = try std.fs.cwd().createFile(args[1], .{});
    defer file.close();
    const writer = file.writer();

    try writer.writeAll("pub const QuickCheck = packed struct(u8) {");
    for (std.meta.fieldNames(QuickCheck), 0..) |name, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.print("{s}: Value", .{name});
    }
    try writer.writeAll("};");

    try writer.writeAll("pub const Value = enum(u2) {");
    for (std.meta.fieldNames(Value), 0..) |name, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.print("{s}", .{name});
    }
    try writer.writeAll("};");

    try writer.print("pub const bs = {d};", .{bs});
    try parse.printArray(u8, "u8", s1, "s1", writer);

    try writer.print("pub const s2 = [{d}]QuickCheck{{", .{s2.len});
    for (s2, 0..) |it, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.writeAll(".{");
        inline for (comptime std.meta.fieldNames(QuickCheck), 0..) |name, j| {
            if (j > 0) try writer.writeByte(',');
            try writer.print(".{s} = .{s}", .{ name, @tagName(@field(it, name)) });
        }
        try writer.writeAll("}");
    }
    try writer.writeAll("};");
}
