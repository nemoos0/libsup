const std = @import("std");
const table = @import("case_folding_table");
const codepoint = @import("codepoint");

const Folder = struct {
    source: codepoint.Iterator,
    codes: []const u21 = &.{},
    pos: u8,

    pub fn nextSimple(fold: Folder) !?u21 {
        if (try fold.source.next()) |cp| {
            return getSimple(cp.code);
        }

        return null;
    }

    pub fn nextFull(fold: Folder) !?u21 {
        if (fold.pos < fold.codes.len) {
            defer fold.pos += 1;
            return fold.codes[fold.pos];
        }

        if (try fold.source.next()) |cp| {
            if (getFull(cp.code)) |full| {
                fold.source = full;
                fold.pos = 1;
                return fold.source[0];
            } else {
                return cp.code;
            }
        }

        return null;
    }
};

pub fn getFull(code: u21) ?[]const u21 {
    std.debug.assert(code < 0x110000);

    const high_bits = code / table.bs;
    const low_bits = code % table.bs;

    const idx: u32 = @as(u32, @intCast(table.s1[high_bits])) * table.bs + low_bits;

    const len = table.s2_len[idx];
    if (len == 0) return null;

    const off = table.s2_off[idx];
    return table.codes[off..][0..len];
}

test "getFull" {
    try std.testing.expectEqualSlices(u21, &[_]u21{'a'}, getFull('A').?);
    try std.testing.expectEqualSlices(u21, &[_]u21{ 0x1f00, 0x03b9 }, getFull(0x1f88).?);
}

pub fn getSimple(code: u21) u21 {
    std.debug.assert(code < 0x110000);

    const high_bits = code / table.bs;
    const low_bits = code % table.bs;

    const idx: u32 = @as(u32, @intCast(table.s1[high_bits])) * table.bs + low_bits;

    const len = table.s2_len[idx];
    if (len == 0) return code;

    const off = table.s2_off[idx];
    return table.codes[off + len * @intFromBool(len > 1)];
}

test "getSimple" {
    try std.testing.expectEqual('a', getSimple('A'));
    try std.testing.expectEqual(0x1f80, getSimple(0x1f88));
}
