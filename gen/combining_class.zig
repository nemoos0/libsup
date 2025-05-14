const std = @import("std");
const parse = @import("parse.zig");

pub fn main() !void {
    const gpa = std.heap.smp_allocator;

    const combining_classes = try gpa.alloc(u8, 0x110000);

    {
        const file = try std.fs.cwd().openFile("data/extracted/DerivedCombiningClass.txt", .{});
        defer file.close();

        while (try parse.nextLine(file)) |line| {
            const range = try parse.columnAsRange(line, 0) orelse unreachable;
            const value = try std.fmt.parseInt(u8, parse.column(line, 1).?, 10);
            @memset(combining_classes[range.start..range.end], value);
        }
    }

    const bs = 128;
    const s1, const s2 = try parse.twoStageTable(u8, u8, bs, gpa, combining_classes);

    const args = try std.process.argsAlloc(gpa);
    std.debug.assert(args.len == 2);

    const file = try std.fs.cwd().createFile(args[1], .{});
    defer file.close();
    const writer = file.writer();

    try writer.print("pub const bs = {d};", .{bs});
    try parse.printArray(u8, "u8", s1, "s1", writer);
    try parse.printArray(u8, "u8", s2, "s2", writer);
}
