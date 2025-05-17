const std = @import("std");
const table = @import("case_mapping_table");

pub fn getLower(code: u21) ?[]const u21 {
    std.debug.assert(code < 0x110000);

    const high_bits = code / table.lower_bs;
    const low_bits = code % table.lower_bs;

    const idx: u32 = @as(u32, @intCast(table.lower_s1[high_bits])) * table.lower_bs + low_bits;

    const len = table.lower_s2_len[idx];
    if (len == 0) return null;

    const off = table.lower_s2_off[idx];
    return table.codes[off..][0..len];
}

test "getLower" {
    try std.testing.expectEqualSlices(u21, &[_]u21{'a'}, getLower('A').?);
    try std.testing.expectEqualSlices(u21, &[_]u21{'á'}, getLower('Á').?);

    try std.testing.expectEqual(null, getLower('a'));
    try std.testing.expectEqual(null, getLower(' '));
}

pub fn getUpper(code: u21) ?[]const u21 {
    std.debug.assert(code < 0x110000);

    const high_bits = code / table.upper_bs;
    const low_bits = code % table.upper_bs;

    const idx: u32 = @as(u32, @intCast(table.upper_s1[high_bits])) * table.upper_bs + low_bits;

    const len = table.upper_s2_len[idx];
    if (len == 0) return null;

    const off = table.upper_s2_off[idx];
    return table.codes[off..][0..len];
}

test "getUpper" {
    try std.testing.expectEqualSlices(u21, &[_]u21{'A'}, getUpper('a').?);
    try std.testing.expectEqualSlices(u21, &[_]u21{'Á'}, getUpper('á').?);
    try std.testing.expectEqualSlices(u21, &[_]u21{ 'F', 'F', 'I' }, getUpper('ﬃ').?);

    try std.testing.expectEqual(null, getUpper('A'));
    try std.testing.expectEqual(null, getUpper(' '));
}

pub fn getTitle(code: u21) ?[]const u21 {
    std.debug.assert(code < 0x110000);

    const high_bits = code / table.title_bs;
    const low_bits = code % table.title_bs;

    const idx: u32 = @as(u32, @intCast(table.title_s1[high_bits])) * table.title_bs + low_bits;

    const len = table.title_s2_len[idx];
    if (len == 0) return null;

    const off = table.title_s2_off[idx];
    return table.codes[off..][0..len];
}

test "getTitle" {
    try std.testing.expectEqualSlices(u21, &[_]u21{'A'}, getTitle('a').?);
    try std.testing.expectEqualSlices(u21, &[_]u21{'Á'}, getTitle('á').?);
    try std.testing.expectEqualSlices(u21, &[_]u21{ 'F', 'f', 'i' }, getTitle('ﬃ').?);

    try std.testing.expectEqual(null, getTitle('A'));
    try std.testing.expectEqual(null, getTitle(' '));
}
