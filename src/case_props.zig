const std = @import("std");
const table = @import("case_props_table");

const CaseProps = table.CaseProps;

pub fn get(code: u21) CaseProps {
    std.debug.assert(code < 0x110000);
    return table.s2[
        @as(u32, @intCast(
            table.s1[code / table.bs],
        )) * table.bs + code % table.bs
    ];
}

pub fn isUppercase(code: u21) bool {
    return get(code).uppercase;
}

pub fn isLowercase(code: u21) bool {
    return get(code).lowercase;
}

pub fn isCased(code: u21) bool {
    return get(code).cased;
}

pub fn isCaseIgnorable(code: u21) bool {
    return get(code).case_ignorable;
}

pub fn changesWhenLowercased(code: u21) bool {
    return get(code).changes_when_lowercased;
}

pub fn changesWhenTitlecased(code: u21) bool {
    return get(code).changes_when_titlecased;
}

pub fn changesWhenUppercased(code: u21) bool {
    return get(code).changes_when_uppercased;
}

pub fn changesWhenCasefolded(code: u21) bool {
    return get(code).changes_when_casefolded;
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
