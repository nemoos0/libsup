const std = @import("std");
const ucd = @import("ucd.zig");

const Mapping = struct {
    source: u21,
    dest: []const u21,

    pub fn lenLessThan(_: void, a: Mapping, b: Mapping) bool {
        return a.dest.len < b.dest.len;
    }
};

pub fn main() !void {
    const gpa = std.heap.smp_allocator;

    var lower_mappings: std.ArrayList(Mapping) = .init(gpa);
    var upper_mappings: std.ArrayList(Mapping) = .init(gpa);
    var title_mappings: std.ArrayList(Mapping) = .init(gpa);

    {
        const file = try std.fs.cwd().openFile("data/SpecialCasing.txt", .{});
        defer file.close();

        while (try ucd.nextLine(file)) |line| {
            if (ucd.column(line, 5) == null) {
                const code = try ucd.asCodepoint(ucd.column(line, 0).?);
                const lower = try ucd.asCodepointSlice(gpa, ucd.column(line, 1).?);
                const title = try ucd.asCodepointSlice(gpa, ucd.column(line, 2).?);
                const upper = try ucd.asCodepointSlice(gpa, ucd.column(line, 3).?);

                if (lower.len != 1 or lower[0] != code) {
                    try lower_mappings.append(.{ .source = code, .dest = lower });
                }

                if (title.len != 1 or title[0] != code) {
                    try title_mappings.append(.{ .source = code, .dest = title });
                }

                if (upper.len != 1 or upper[0] != code) {
                    try upper_mappings.append(.{ .source = code, .dest = upper });
                }
            }
        }
    }

    {
        const file = try std.fs.cwd().openFile("data/UnicodeData.txt", .{});
        defer file.close();

        while (try ucd.nextLine(file)) |line| {
            const code = try ucd.asCodepoint(ucd.column(line, 0).?);

            if (ucd.asCodepointSlice(gpa, ucd.column(line, 12).?)) |upper| {
                for (upper_mappings.items) |it| {
                    if (it.source == code) break;
                } else {
                    try upper_mappings.append(.{ .source = code, .dest = upper });
                }
            } else |_| {}

            if (ucd.asCodepointSlice(gpa, ucd.column(line, 13).?)) |lower| {
                for (lower_mappings.items) |it| {
                    if (it.source == code) break;
                } else {
                    try lower_mappings.append(.{ .source = code, .dest = lower });
                }
            } else |_| {}

            if (ucd.asCodepointSlice(gpa, ucd.column(line, 14).?)) |title| {
                for (title_mappings.items) |it| {
                    if (it.source == code) break;
                } else {
                    try title_mappings.append(.{ .source = code, .dest = title });
                }
            } else |_| if (ucd.asCodepointSlice(gpa, ucd.column(line, 12).?)) |upper| {
                // NOTE: if title is null than it is equal to upper
                for (title_mappings.items) |it| {
                    if (it.source == code) break;
                } else {
                    try title_mappings.append(.{ .source = code, .dest = upper });
                }
            } else |_| {}
        }
    }

    const args = try std.process.argsAlloc(gpa);
    std.debug.assert(args.len == 2);

    const output = try std.fs.cwd().createFile(args[1], .{});
    defer output.close();
    const writer = output.writer();

    const Slice = struct { off: u16, len: u8 };

    var code_list: std.ArrayList(u21) = .init(gpa);

    // upper
    {
        const slices = try gpa.alloc(Slice, 0x110000);
        @memset(slices, .{ .off = 0, .len = 0 });

        std.mem.sort(Mapping, upper_mappings.items, {}, Mapping.lenLessThan);

        for (upper_mappings.items) |mapping| {
            if (std.mem.indexOf(u21, code_list.items, mapping.dest)) |off| {
                slices[mapping.source].off = @intCast(off);
            } else {
                slices[mapping.source].off = @intCast(code_list.items.len);
                try code_list.appendSlice(mapping.dest);
            }
            slices[mapping.source].len = @intCast(mapping.dest.len);
        }

        const block_size = 128;
        const s1, const s2 = try ucd.twoStageTable(u8, Slice, block_size, gpa, slices);
        std.debug.print("{}\n", .{s1.len + s2.len * 3});

        try ucd.printConst("upper_bs", block_size, writer);
        try ucd.printConst("upper_s1", s1, writer);

        try writer.print("pub const upper_s2_off = [{}]u16{{", .{s2.len});
        for (s2, 0..) |it, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.print("{}", .{it.off});
        }
        try writer.writeAll("};");

        try writer.print("pub const upper_s2_len = [{}]u8{{", .{s2.len});
        for (s2, 0..) |it, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.print("{}", .{it.len});
        }
        try writer.writeAll("};");
    }

    // title
    {
        const slices = try gpa.alloc(Slice, 0x110000);
        @memset(slices, .{ .off = 0, .len = 0 });

        std.mem.sort(Mapping, title_mappings.items, {}, Mapping.lenLessThan);

        for (title_mappings.items) |mapping| {
            if (std.mem.indexOf(u21, code_list.items, mapping.dest)) |off| {
                slices[mapping.source].off = @intCast(off);
            } else {
                slices[mapping.source].off = @intCast(code_list.items.len);
                try code_list.appendSlice(mapping.dest);
            }
            slices[mapping.source].len = @intCast(mapping.dest.len);
        }

        const block_size = 128;
        const s1, const s2 = try ucd.twoStageTable(u8, Slice, block_size, gpa, slices);
        std.debug.print("{}\n", .{s1.len + s2.len * 3});

        try ucd.printConst("title_bs", block_size, writer);
        try ucd.printConst("title_s1", s1, writer);

        try writer.print("pub const title_s2_off = [{}]u16{{", .{s2.len});
        for (s2, 0..) |it, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.print("{}", .{it.off});
        }
        try writer.writeAll("};");

        try writer.print("pub const title_s2_len = [{}]u8{{", .{s2.len});
        for (s2, 0..) |it, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.print("{}", .{it.len});
        }
        try writer.writeAll("};");
    }

    // lower
    {
        const slices = try gpa.alloc(Slice, 0x110000);
        @memset(slices, .{ .off = 0, .len = 0 });

        std.mem.sort(Mapping, lower_mappings.items, {}, Mapping.lenLessThan);

        for (lower_mappings.items) |mapping| {
            if (std.mem.indexOf(u21, code_list.items, mapping.dest)) |off| {
                slices[mapping.source].off = @intCast(off);
            } else {
                slices[mapping.source].off = @intCast(code_list.items.len);
                try code_list.appendSlice(mapping.dest);
            }
            slices[mapping.source].len = @intCast(mapping.dest.len);
        }

        const block_size = 128;
        const s1, const s2 = try ucd.twoStageTable(u8, Slice, block_size, gpa, slices);
        std.debug.print("{}\n", .{s1.len + s2.len * 3});

        try ucd.printConst("lower_bs", block_size, writer);
        try ucd.printConst("lower_s1", s1, writer);

        try writer.print("pub const lower_s2_off = [{}]u16{{", .{s2.len});
        for (s2, 0..) |it, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.print("{}", .{it.off});
        }
        try writer.writeAll("};");

        try writer.print("pub const lower_s2_len = [{}]u8{{", .{s2.len});
        for (s2, 0..) |it, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.print("{}", .{it.len});
        }
        try writer.writeAll("};");
    }

    try ucd.printConst("codes", code_list.items, writer);
}
