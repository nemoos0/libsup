const std = @import("std");
const parse = @import("parse.zig");

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

        while (try parse.nextLine(file)) |line| {
            const decomp_column = parse.column(line, 5) orelse unreachable;
            if (decomp_column.len == 0 or decomp_column[0] == '<') continue;

            if (std.mem.indexOfScalar(u8, decomp_column, ' ')) |space| {
                const code1 = try std.fmt.parseInt(u21, decomp_column[0..space], 16);
                const code2 = try std.fmt.parseInt(u21, decomp_column[space + 1 ..], 16);

                try comp_list.append(.{
                    .source = .{ code1, code2 },
                    .dest = try parse.columnAsCodepoint(line, 0) orelse unreachable,
                });
            }
        }
    }

    {
        const file = try std.fs.cwd().openFile("data/DerivedNormalizationProps.txt", .{});
        defer file.close();

        while (try parse.nextLine(file)) |line| {
            if (std.mem.eql(u8, "Full_Composition_Exclusion", parse.column(line, 1).?)) {
                const range = try parse.columnAsRange(line, 0) orelse unreachable;
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

    std.debug.print("left: {}\n", .{left_count});
    std.debug.print("right: {}\n", .{right_count});
    std.debug.print("codes: {}\n", .{left_count * right_count});

    const lbs = 256;
    const ls1, const ls2 = try parse.twoStageTable(u8, u16, lbs, gpa, left);
    std.debug.print("left: {} . {} = {}\n", .{ ls1.len, ls2.len, ls1.len + ls2.len * 2 });

    const rbs = 256;
    const rs1, const rs2 = try parse.twoStageTable(u8, u8, rbs, gpa, right);
    std.debug.print("right: {} . {} = {}\n", .{ rs1.len, rs2.len, rs1.len + rs2.len });

    const cbs = 4;
    const cs1, const cs2 = try parse.twoStageTable(u16, u21, cbs, gpa, codes);
    std.debug.print("codes: {} . {} = {}\n", .{
        cs1.len,
        cs2.len,
        cs1.len * 2 + cs2.len * 4,
    });

    const args = try std.process.argsAlloc(gpa);
    std.debug.assert(args.len == 2);

    const output = try std.fs.cwd().createFile(args[1], .{});
    defer output.close();
    const writer = output.writer();

    try writer.print("pub const lbs = {};", .{lbs});
    try parse.printArray(u8, "u8", ls1, "ls1", writer);
    try parse.printArray(u16, "u16", ls2, "ls2", writer);

    try writer.print("pub const rbs = {};", .{rbs});
    try parse.printArray(u8, "u8", rs1, "rs1", writer);
    try parse.printArray(u8, "u8", rs2, "rs2", writer);

    try writer.print("pub const width = {};", .{right_count});
    try writer.print("pub const cbs = {};", .{cbs});
    try parse.printArray(u16, "u16", cs1, "cs1", writer);
    try parse.printArray(u21, "u21", cs2, "cs2", writer);
}
