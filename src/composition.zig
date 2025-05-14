const std = @import("std");
const table = @import("composition_table");

pub fn get(left: u21, right: u21) ?u21 {
    std.debug.assert(left < 0x110000);
    std.debug.assert(right < 0x110000);

    if (left >= l_base and left < l_base + l_count) {
        if (right >= v_base and right < v_base + v_count) {
            return hangulLV(left, right);
        }

        return null;
    }

    if (left >= s_base and (left - s_base) % t_count == 0) {
        if (right >= t_base and right < t_base + t_count) {
            return hangulLVT(left, right);
        }

        return null;
    }

    const left_id = table.ls2[
        @as(usize, @intCast(
            table.ls1[left / table.lbs],
        )) * table.lbs + left % table.lbs
    ];
    if (left_id == std.math.maxInt(u16)) return null;

    const right_id = table.rs2[
        @as(usize, @intCast(
            table.rs1[right / table.rbs],
        )) * table.rbs + right % table.rbs
    ];
    if (right_id == std.math.maxInt(u8)) return null;

    const index = left_id * table.width + right_id;
    const code = table.cs2[
        @as(usize, @intCast(
            table.cs1[index / table.cbs],
        )) * table.cbs + index % table.cbs
    ];
    if (code == 0) return null;

    return code;
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

fn hangulLV(l_part: u21, v_part: u21) ?u21 {
    std.debug.assert(l_part >= l_base and l_part < l_base + l_count);
    std.debug.assert(v_part >= v_base and v_part < v_base + v_count);

    const l_index = l_part - l_base;
    const v_index = v_part - v_base;
    const lv_index = l_index * n_count + v_index * t_count;
    return s_base + lv_index;
}

fn hangulLVT(lv_part: u21, t_part: u21) ?u21 {
    std.debug.assert(lv_part >= s_base and (lv_part - s_base) % t_count == 0);
    std.debug.assert(t_part >= t_base and t_part < t_base + t_count);

    const t_index = t_part - t_base;
    return lv_part + t_index;
}

test "get" {
    try std.testing.expectEqual(0xc1, get(0x41, 0x301));
    try std.testing.expectEqual(0xac00, get(0x1100, 0x1161));
    try std.testing.expectEqual(0xac01, get(0xac00, 0x11a8));
}
