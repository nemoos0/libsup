const std = @import("std");
const ucd = @import("ucd.zig");

const CompatibilityTag = enum(u5) {
    none,

    font,
    noBreak,
    initial,
    medial,
    final,
    isolated,
    circle,
    super,
    sub,
    vertical,
    wide,
    narrow,
    small,
    square,
    fraction,
    compat,
};

const Decomposition = struct {
    source: u21,
    dest: []const u21,
    tag: CompatibilityTag,

    pub fn lenLessThan(_: void, a: Decomposition, b: Decomposition) bool {
        return a.dest.len < b.dest.len;
    }
};

pub fn main() !void {
    const gpa = std.heap.smp_allocator;

    var decomp_list: std.ArrayList(Decomposition) = .init(gpa);

    {
        const file = try std.fs.cwd().openFile("data/UnicodeData.txt", .{});
        defer file.close();

        while (try ucd.nextLine(file)) |line| {
            const decomp_column = ucd.column(line, 5).?;
            if (try asDecomp(gpa, decomp_column)) |tuple| {
                const source = try ucd.asCodepoint(ucd.column(line, 0).?);
                const tag, const dest = tuple;
                try decomp_list.append(.{ .source = source, .dest = dest, .tag = tag });
            }
        }
    }

    const Slice = struct { off: u16, len: u8, tag: CompatibilityTag };
    const slices = try gpa.alloc(Slice, 0x110000);
    @memset(slices, .{ .off = 0, .len = 0, .tag = .none });

    var code_list: std.ArrayList(u21) = .init(gpa);

    std.mem.sort(Decomposition, decomp_list.items, {}, Decomposition.lenLessThan);

    for (decomp_list.items) |decomp| {
        if (std.mem.indexOf(u21, code_list.items, decomp.dest)) |off| {
            slices[decomp.source].off = @intCast(off);
        } else {
            slices[decomp.source].off = @intCast(code_list.items.len);
            try code_list.appendSlice(decomp.dest);
        }
        slices[decomp.source].len = @intCast(decomp.dest.len);
        slices[decomp.source].tag = decomp.tag;
    }

    const block_size = 64;
    const s1, const s2 = try ucd.twoStageTable(u8, Slice, block_size, gpa, slices);

    const args = try std.process.argsAlloc(gpa);
    std.debug.assert(args.len == 2);

    const output = try std.fs.cwd().createFile(args[1], .{});
    defer output.close();
    const writer = output.writer();

    try ucd.printConst("CompatibilityTag", CompatibilityTag, writer);
    try ucd.printConst("bs", block_size, writer);
    try ucd.printConst("s1", s1, writer);

    try writer.print("pub const s2_off = [{}]u16{{", .{s2.len});
    for (s2, 0..) |it, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.print("{}", .{it.off});
    }
    try writer.writeAll("};");

    try writer.print("pub const s2_len = [{}]u8{{", .{s2.len});
    for (s2, 0..) |it, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.print("{}", .{it.len});
    }
    try writer.writeAll("};");

    try writer.print("pub const s2_tag = [{}]CompatibilityTag{{", .{s2.len});
    for (s2, 0..) |it, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.print(".{s}", .{@tagName(it.tag)});
    }
    try writer.writeAll("};");

    try ucd.printConst("codes", code_list.items, writer);
}

fn asDecomp(gpa: std.mem.Allocator, column: []const u8) !?struct { CompatibilityTag, []const u21 } {
    if (column.len == 0) return null;

    var tag: CompatibilityTag = .none;
    var decomp_list: std.ArrayList(u21) = .init(gpa);

    var iter = std.mem.splitScalar(u8, column, ' ');

    if (iter.peek().?[0] == '<') {
        tag = std.meta.stringToEnum(
            CompatibilityTag,
            std.mem.trim(u8, iter.next().?, "<>"),
        ).?;
    }

    while (iter.next()) |slice| {
        try decomp_list.append(try std.fmt.parseInt(u21, slice, 16));
    }

    return .{ tag, try decomp_list.toOwnedSlice() };
}
