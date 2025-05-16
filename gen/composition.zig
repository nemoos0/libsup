const std = @import("std");
const ucd = @import("ucd.zig");

const Composition = struct {
    source: [2]u21,
    dest: u21,
};

pub fn main() !void {
    const gpa = std.heap.smp_allocator;

    var comp_list: std.ArrayList(Composition) = .init(gpa);

    {
        const file = try std.fs.cwd().openFile("data/UnicodeData.txt", .{});
        defer file.close();

        while (try ucd.nextLine(file)) |line| {
            const decomp_column = ucd.column(line, 5).?;
            if (decomp_column.len == 0 or decomp_column[0] == '<') continue;

            if (std.mem.indexOfScalar(u8, decomp_column, ' ')) |space| {
                const code1 = try ucd.asCodepoint(decomp_column[0..space]);
                const code2 = try ucd.asCodepoint(decomp_column[space + 1 ..]);

                try comp_list.append(.{
                    .source = .{ code1, code2 },
                    .dest = try ucd.asCodepoint(ucd.column(line, 0).?),
                });
            }
        }
    }

    {
        const file = try std.fs.cwd().openFile("data/DerivedNormalizationProps.txt", .{});
        defer file.close();

        while (try ucd.nextLine(file)) |line| {
            if (std.mem.eql(u8, "Full_Composition_Exclusion", ucd.column(line, 1).?)) {
                const range = try ucd.asRange(ucd.column(line, 0).?);
                var i: usize = comp_list.items.len;
                while (i > 0) {
                    i -= 1;
                    const comp = comp_list.items[i];
                    if (comp.dest >= range.start and comp.dest < range.end) {
                        _ = comp_list.swapRemove(i);
                    }
                }
            }
        }
    }

    const left = try gpa.alloc(u16, 0x110000);
    const right = try gpa.alloc(u8, 0x110000);

    @memset(left, std.math.maxInt(u16));
    @memset(right, std.math.maxInt(u8));

    var left_count: u16 = 0;
    var right_count: u8 = 0;
    for (comp_list.items) |comp| {
        if (left[comp.source[0]] == std.math.maxInt(u16)) {
            left[comp.source[0]] = left_count;
            left_count += 1;
        }

        if (right[comp.source[1]] == std.math.maxInt(u8)) {
            right[comp.source[1]] = right_count;
            right_count += 1;
        }
    }

    var codes = try gpa.alloc(u21, left_count * right_count);
    @memset(codes, 0);

    for (comp_list.items) |comp| {
        codes[left[comp.source[0]] * right_count + right[comp.source[1]]] = comp.dest;
    }

    const lbs = 256;
    const ls1, const ls2 = try ucd.twoStageTable(u8, u16, lbs, gpa, left);

    const rbs = 256;
    const rs1, const rs2 = try ucd.twoStageTable(u8, u8, rbs, gpa, right);

    const cbs = 4;
    const cs1, const cs2 = try ucd.twoStageTable(u16, u21, cbs, gpa, codes);

    const args = try std.process.argsAlloc(gpa);
    std.debug.assert(args.len == 2);

    const output = try std.fs.cwd().createFile(args[1], .{});
    defer output.close();
    const writer = output.writer();

    try ucd.printConst("lbs", lbs, writer);
    try ucd.printConst("ls1", ls1, writer);
    try ucd.printConst("ls2", ls2, writer);

    try ucd.printConst("rbs", rbs, writer);
    try ucd.printConst("rs1", rs1, writer);
    try ucd.printConst("rs2", rs2, writer);

    try ucd.printConst("width", right_count, writer);
    try ucd.printConst("cbs", cbs, writer);
    try ucd.printConst("cs1", cs1, writer);
    try ucd.printConst("cs2", cs2, writer);
}
