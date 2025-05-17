const std = @import("std");
const ucd = @import("ucd.zig");

const Mapping = struct {
    source: u21,
    full: []const u21,
    simple: ?u21,
};

pub fn main() !void {
    const gpa = std.heap.smp_allocator;

    const full = try gpa.alloc(?[]const u21, 0x110000);
    const simple = try gpa.alloc(?u21, 0x110000);

    @memset(full, null);
    @memset(simple, null);

    {
        const file = try std.fs.cwd().openFile("data/CaseFolding.txt", .{});
        defer file.close();

        while (try ucd.nextLine(file)) |line| {
            const code = try ucd.asCodepoint(ucd.column(line, 0).?);
            const status = ucd.column(line, 1).?;

            switch (status[0]) {
                'C', 'F' => {
                    full[code] = try ucd.asCodepointSlice(gpa, ucd.column(line, 2).?);
                },
                'S' => {
                    std.debug.assert(full[code] != null);
                    simple[code] = try ucd.asCodepoint(ucd.column(line, 2).?);
                },
                'T' => {},
                else => unreachable,
            }
        }
    }

    const Slice = struct { off: u16, len: u8 };

    const slices = try gpa.alloc(Slice, 0x110000);
    var code_list: std.ArrayList(u21) = .init(gpa);

    for (0..0x110000) |i| {
        if (full[i]) |fullDest| {
            slices[i].off = @intCast(code_list.items.len);
            slices[i].len = @intCast(fullDest.len);

            try code_list.appendSlice(fullDest);
            if (fullDest.len > 1) {
                if (simple[i]) |simpleDest| {
                    try code_list.append(simpleDest);
                } else {
                    try code_list.append(@intCast(i));
                }
            }
        } else {
            std.debug.assert(simple[i] == null);
            slices[i] = .{ .off = 0, .len = 0 };
        }
    }

    const block_size = 128;
    const s1, const s2 = try ucd.twoStageTable(u8, Slice, block_size, gpa, slices);

    const args = try std.process.argsAlloc(gpa);
    std.debug.assert(args.len == 2);

    const output = try std.fs.cwd().createFile(args[1], .{});
    defer output.close();
    const writer = output.writer();

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

    try ucd.printConst("codes", code_list.items, writer);
}
