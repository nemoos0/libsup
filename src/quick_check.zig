const std = @import("std");
const table = @import("quick_check_table");

pub const QuickCheck = table.QuickCheck;
pub const Value = table.Value;

pub fn get(code: u21) QuickCheck {
    std.debug.assert(code < 0x110000);

    return table.s2[
        @as(usize, @intCast(
            table.s1[code / table.bs],
        )) * table.bs + code % table.bs
    ];
}
