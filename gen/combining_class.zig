const std = @import("std");
const ucd = @import("ucd.zig");

pub fn main() !void {
    const gpa = std.heap.smp_allocator;

    const combining_classes = try gpa.alloc(u8, 0x110000);

    {
        const file = try std.fs.cwd().openFile("data/extracted/DerivedCombiningClass.txt", .{});
        defer file.close();

        while (try ucd.nextLine(file)) |line| {
            const range = try ucd.asRange(ucd.column(line, 0).?);
            const value = try std.fmt.parseInt(u8, ucd.column(line, 1).?, 10);
            @memset(combining_classes[range.start..range.end], value);
        }
    }

    const block_size = 128;
    const s1, const s2 = try ucd.twoStageTable(u8, u8, block_size, gpa, combining_classes);

    const args = try std.process.argsAlloc(gpa);
    std.debug.assert(args.len == 2);

    const file = try std.fs.cwd().createFile(args[1], .{});
    defer file.close();
    const writer = file.writer();

    try ucd.printConst("bs", block_size, writer);
    try ucd.printConst("s1", s1, writer);
    try ucd.printConst("s2", s2, writer);
}
