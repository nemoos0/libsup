const std = @import("std");
const table = @import("combining_class_table");

pub fn get(code: u21) u8 {
    std.debug.assert(code < 0x110000);

    return table.s2[
        @as(usize, @intCast(
            table.s1[code / table.bs],
        )) * table.bs + code % table.bs
    ];
}
