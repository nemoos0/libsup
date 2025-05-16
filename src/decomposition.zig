const std = @import("std");
const table = @import("decomposition_table");

pub const CompatibilityTag = table.CompatibilityTag;

pub fn compatibilityTag(code: u21) CompatibilityTag {
    std.debug.assert(code < 0x110000);

    const high_bits = code / table.bs;
    const low_bits = code % table.bs;

    const idx: u32 = @as(u32, @intCast(table.s1[high_bits])) * table.bs + low_bits;
    return table.s2_tag[idx];
}

pub fn canonical(code: u21) ?[]const u21 {
    std.debug.assert(code < 0x110000);

    if (code >= s_base and code < s_base + s_count) {
        return hangul(code);
    }

    const high_bits = code / table.bs;
    const low_bits = code % table.bs;

    const idx: u32 = @as(u32, @intCast(table.s1[high_bits])) * table.bs + low_bits;

    const len = table.s2_len[idx];
    if (len == 0) return null;

    const tag = table.s2_tag[idx];
    if (tag != .none) return null;

    const off = table.s2_off[idx];
    return table.codes[off..][0..len];
}

/// Ensure `dest.len >= 4` to fit every possible decomposition.
/// Change this value only if you know what you are doing.
pub fn fullCanonical(code: u21, dest: []u21) u3 {
    std.debug.assert(code < 0x110000);
    std.debug.assert(dest.len > 0);

    if (code >= s_base and code < s_base + s_count) {
        return fullHangul(code, dest);
    }

    if (canonical(code)) |pair| {
        // NOTE: only the first codepoint can have further decomposition
        // as stated in UAX #44 section 5.7.3 Character Decomposition Mapping
        // https://www.unicode.org/reports/tr44/#Character_Decomposition_Mappings
        const len = fullCanonical(pair[0], dest);
        if (pair.len > 1) dest[len] = pair[1];
        return len + 1;
    } else {
        dest[0] = code;
        return 1;
    }
}

pub fn compatibility(code: u21) ?[]const u21 {
    std.debug.assert(code < 0x110000);

    if (code >= s_base and code < s_base + s_count) {
        return hangul(code);
    }

    const high_bits = code / table.bs;
    const low_bits = code % table.bs;

    const idx: u32 = @as(u32, @intCast(table.s1[high_bits])) * table.bs + low_bits;

    const len = table.s2_len[idx];
    if (len == 0) return null;

    const off = table.s2_off[idx];
    return table.codes[off..][0..len];
}

/// Ensure `dest.len >= 18` to fit every possible decomposition.
/// Change this value only if you know what you are doing.
pub fn fullCompatibility(code: u21, dest: []u21) u5 {
    std.debug.assert(code < 0x110000);
    std.debug.assert(dest.len > 0);

    if (code >= s_base and code < s_base + s_count) {
        return fullHangul(code, dest);
    }

    if (compatibility(code)) |slice| {
        var len: u5 = 0;
        for (slice) |it| {
            len += fullCompatibility(it, dest[len..]);
        }
        return len;
    } else {
        dest[0] = code;
        return 1;
    }
}

// NOTE: The Unicode Standard, Version 16.0 – Core Specification
// 3.12.2 Hangul Syllable Decomposition
const s_base = 0xAC00;
const l_base = 0x1100;
const v_base = 0x1161;
const t_base = 0x11A7;
const l_count = 19;
const v_count = 21;
const t_count = 28;
const n_count = (v_count * t_count);
const s_count = (l_count * n_count);

var hangul_buffer: [2]u21 = undefined;

fn hangul(code: u21) []const u21 {
    std.debug.assert(code >= s_base and code < s_base + s_count);

    const s_index = code - s_base;

    const t_index = s_index % t_count;
    if (t_index == 0) {
        const l_index = s_index / n_count;
        const v_index = (s_index % n_count) / t_count;
        const l_part = l_base + l_index;
        const v_part = v_base + v_index;

        hangul_buffer = .{ l_part, v_part };
    } else {
        const lv_index = s_index - t_index; // (s_index / t_count) * t_count;
        const lv_part = s_base + lv_index;
        const t_part = t_base + t_index;

        hangul_buffer = .{ lv_part, t_part };
    }

    return &hangul_buffer;
}

fn fullHangul(code: u21, dest: []u21) u2 {
    std.debug.assert(code >= s_base and code < s_base + s_count);
    std.debug.assert(dest.len >= 2);

    const s_index = code - s_base;

    const l_index = s_index / n_count;
    const v_index = (s_index % n_count) / t_count;
    const t_index = s_index % t_count;
    const l_part = l_base + l_index;
    const v_part = v_base + v_index;
    const t_part = t_base + t_index;

    var len: u2 = 2;
    len += @intFromBool(t_index > 0);
    @memcpy(
        dest[0..len],
        ([_]u21{ l_part, v_part, t_part })[0..len],
    );
    return len;
}

test "canonical" {
    var dest: [4]u21 = undefined;

    for (0..0x110000) |i| {
        _ = fullCanonical(@intCast(i), &dest);
    }

    try std.testing.expectEqual(2, fullCanonical(0xac00, &dest));
    try std.testing.expectEqualSlices(u21, &[_]u21{ 0x1100, 0x1161 }, dest[0..2]);
}

test "compatibility" {
    var dest: [18]u21 = undefined;

    for (0..0x110000) |i| {
        _ = fullCompatibility(@intCast(i), &dest);
    }
}
