const std = @import("std");
const codepoint = @import("codepoint");

const props_table = @import("case_props_table");
const mapping_table = @import("case_mapping_table");
const folding_table = @import("case_folding_table");

pub const CaseProps = props_table.CaseProps;

pub const Fold = struct {
    source: codepoint.Iterator,
    codes: []const u21 = &.{},
    pos: u8 = 0,

    pub fn nextSimple(fold: Fold) !?u21 {
        if (try fold.source.next()) |cp| {
            return simpleFolding(cp.code);
        }

        return null;
    }

    pub fn nextFull(fold: *Fold) !?u21 {
        if (fold.pos < fold.codes.len) {
            defer fold.pos += 1;
            return fold.codes[fold.pos];
        }

        if (try fold.source.next()) |cp| {
            if (fullFolding(cp.code)) |full| {
                fold.codes = full;
                fold.pos = 1;
                return fold.codes[0];
            } else {
                return cp.code;
            }
        }

        return null;
    }
};

test "Fold" {
    const input = "HeLlo!";
    var utf8: codepoint.Utf8 = .{ .bytes = input };
    var fold: Fold = .{ .source = utf8.iterator() };

    const expected = "hello!";
    var pos: usize = 0;
    while (try fold.nextFull()) |code| {
        var buf: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(code, &buf);

        try std.testing.expect(
            std.mem.startsWith(u8, expected[pos..], buf[0..len]),
        );
        pos += len;
    }
    try std.testing.expectEqual(expected.len, pos);

    utf8.pos = 0;
    pos = 0;
    while (try fold.nextSimple()) |code| {
        var buf: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(code, &buf);

        try std.testing.expect(
            std.mem.startsWith(u8, expected[pos..], buf[0..len]),
        );
        pos += len;
    }
    try std.testing.expectEqual(expected.len, pos);
}

pub fn props(code: u21) CaseProps {
    std.debug.assert(code < 0x110000);
    return props_table.s2[
        @as(u32, @intCast(
            props_table.s1[code / props_table.bs],
        )) * props_table.bs + code % props_table.bs
    ];
}

pub fn isUppercase(code: u21) bool {
    return props(code).uppercase;
}

pub fn isLowercase(code: u21) bool {
    return props(code).lowercase;
}

pub fn isCased(code: u21) bool {
    return props(code).cased;
}

pub fn isCaseIgnorable(code: u21) bool {
    return props(code).case_ignorable;
}

pub fn changesWhenLowercased(code: u21) bool {
    return props(code).changes_when_lowercased;
}

pub fn changesWhenTitlecased(code: u21) bool {
    return props(code).changes_when_titlecased;
}

pub fn changesWhenUppercased(code: u21) bool {
    return props(code).changes_when_uppercased;
}

pub fn changesWhenCasefolded(code: u21) bool {
    return props(code).changes_when_casefolded;
}

pub fn changesWhenCasemapped(code: u21) bool {
    const mask: u8 = @bitCast(CaseProps{
        .changes_when_lowercased = true,
        .changes_when_titlecased = true,
        .changes_when_uppercased = true,
    });

    const value: u8 = @bitCast(props(code));
    return (value & mask) != 0;
}

test "changesWhenCasemapped" {
    try std.testing.expectEqual(true, changesWhenCasemapped('a'));
    try std.testing.expectEqual(true, changesWhenCasemapped('A'));
    try std.testing.expectEqual(false, changesWhenCasemapped(' '));
}

pub fn lowerMapping(code: u21) ?[]const u21 {
    std.debug.assert(code < 0x110000);

    const high_bits = code / mapping_table.lower_bs;
    const low_bits = code % mapping_table.lower_bs;

    const idx: u32 = @as(u32, @intCast(mapping_table.lower_s1[high_bits])) * mapping_table.lower_bs + low_bits;

    const len = mapping_table.lower_s2_len[idx];
    if (len == 0) return null;

    const off = mapping_table.lower_s2_off[idx];
    return mapping_table.codes[off..][0..len];
}

test "lowerMapping" {
    try std.testing.expectEqualSlices(u21, &[_]u21{'a'}, lowerMapping('A').?);
    try std.testing.expectEqualSlices(u21, &[_]u21{'á'}, lowerMapping('Á').?);

    try std.testing.expectEqual(null, lowerMapping('a'));
    try std.testing.expectEqual(null, lowerMapping(' '));
}

pub fn upperMapping(code: u21) ?[]const u21 {
    std.debug.assert(code < 0x110000);

    const high_bits = code / mapping_table.upper_bs;
    const low_bits = code % mapping_table.upper_bs;

    const idx: u32 = @as(u32, @intCast(mapping_table.upper_s1[high_bits])) * mapping_table.upper_bs + low_bits;

    const len = mapping_table.upper_s2_len[idx];
    if (len == 0) return null;

    const off = mapping_table.upper_s2_off[idx];
    return mapping_table.codes[off..][0..len];
}

test "upperMapping" {
    try std.testing.expectEqualSlices(u21, &[_]u21{'A'}, upperMapping('a').?);
    try std.testing.expectEqualSlices(u21, &[_]u21{'Á'}, upperMapping('á').?);
    try std.testing.expectEqualSlices(u21, &[_]u21{ 'F', 'F', 'I' }, upperMapping('ﬃ').?);

    try std.testing.expectEqual(null, upperMapping('A'));
    try std.testing.expectEqual(null, upperMapping(' '));
}

pub fn titleMapping(code: u21) ?[]const u21 {
    std.debug.assert(code < 0x110000);

    const high_bits = code / mapping_table.title_bs;
    const low_bits = code % mapping_table.title_bs;

    const idx: u32 = @as(u32, @intCast(mapping_table.title_s1[high_bits])) * mapping_table.title_bs + low_bits;

    const len = mapping_table.title_s2_len[idx];
    if (len == 0) return null;

    const off = mapping_table.title_s2_off[idx];
    return mapping_table.codes[off..][0..len];
}

test "titleMapping" {
    try std.testing.expectEqualSlices(u21, &[_]u21{'A'}, titleMapping('a').?);
    try std.testing.expectEqualSlices(u21, &[_]u21{'Á'}, titleMapping('á').?);
    try std.testing.expectEqualSlices(u21, &[_]u21{ 'F', 'f', 'i' }, titleMapping('ﬃ').?);

    try std.testing.expectEqual(null, titleMapping('A'));
    try std.testing.expectEqual(null, titleMapping(' '));
}

pub fn fullFolding(code: u21) ?[]const u21 {
    std.debug.assert(code < 0x110000);

    const high_bits = code / folding_table.bs;
    const low_bits = code % folding_table.bs;

    const idx: u32 = @as(u32, @intCast(folding_table.s1[high_bits])) * folding_table.bs + low_bits;

    const len = folding_table.s2_len[idx];
    if (len == 0) return null;

    const off = folding_table.s2_off[idx];
    return folding_table.codes[off..][0..len];
}

test "fullFolding" {
    try std.testing.expectEqualSlices(u21, &[_]u21{'a'}, fullFolding('A').?);
    try std.testing.expectEqualSlices(u21, &[_]u21{ 0x1f00, 0x03b9 }, fullFolding(0x1f88).?);
}

pub fn simpleFolding(code: u21) u21 {
    std.debug.assert(code < 0x110000);

    const high_bits = code / folding_table.bs;
    const low_bits = code % folding_table.bs;

    const idx: u32 = @as(u32, @intCast(folding_table.s1[high_bits])) * folding_table.bs + low_bits;

    const len = folding_table.s2_len[idx];
    if (len == 0) return code;

    const off = folding_table.s2_off[idx];
    return folding_table.codes[off + len * @intFromBool(len > 1)];
}

test "simpleFolding" {
    try std.testing.expectEqual('a', simpleFolding('A'));
    try std.testing.expectEqual(0x1f80, simpleFolding(0x1f88));
}
