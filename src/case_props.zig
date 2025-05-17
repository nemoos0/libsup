const std = @import("std");
const table = @import("case_props_table");

const CaseProps = table.CaseProps;

fn get(code: u21) CaseProps {
    std.debug.assert(code < 0x110000);
    return table.s2[
        @as(u32, @intCast(
            table.s1[code / table.bs],
        )) * table.bs + code % table.bs
    ];
}

pub fn changesWhenCasemapped(code: u21) bool {
    const mask: u8 = @bitCast(CaseProps{
        .changes_when_lowercased = true,
        .changes_when_titlecased = true,
        .changes_when_uppercased = true,
    });

    const value: u8 = @bitCast(get(code));
    return (value & mask) != 0;
}

test "changesWhenCasemapped" {
    try std.testing.expectEqual(true, changesWhenCasemapped('a'));
    try std.testing.expectEqual(true, changesWhenCasemapped('A'));
    try std.testing.expectEqual(false, changesWhenCasemapped(' '));
}
