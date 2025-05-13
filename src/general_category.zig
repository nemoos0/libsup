const std = @import("std");
const table = @import("general_category_table");

pub const GeneralCategory = table.GeneralCategory;

pub fn get(code: u21) GeneralCategory {
    std.debug.assert(code < 0x110000);
    return table.s2[
        @as(u32, @intCast(
            table.s1[code / table.block_size],
        )) * table.block_size + code % table.block_size
    ];
}

test "get" {
    try std.testing.expectEqual(GeneralCategory.Lu, get('A'));
    try std.testing.expectEqual(GeneralCategory.Ll, get('a'));
    try std.testing.expectEqual(GeneralCategory.Zs, get(' '));
}
