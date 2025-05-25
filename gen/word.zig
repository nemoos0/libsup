const std = @import("std");
const ucd = @import("ucd.zig");

const Prop = enum(u5) {
    CR,
    LF,
    Newline,
    Extend,
    ZWJ,
    Regional_Indicator,
    Format,
    Katakana,
    Hebrew_Letter,
    Single_Quote,
    Double_Quote,
    MidNumLet,
    MidLetter,
    MidNum,
    Numeric,
    ExtendNumLet,
    WSegSpace,

    ALetterNoPic,
    ALetterPic,

    Pic,
    Any,
};

const WordBreakProp = enum(u5) {
    CR,
    LF,
    Newline,
    Extend,
    ZWJ,
    Regional_Indicator,
    Format,
    Katakana,
    Hebrew_Letter,
    ALetter,
    Single_Quote,
    Double_Quote,
    MidNumLet,
    MidLetter,
    MidNum,
    Numeric,
    ExtendNumLet,
    WSegSpace,
    Any,
};

pub fn main() !void {
    const gpa = std.heap.smp_allocator;

    const segments = try gpa.alloc(Prop, 0x110000);
    @memset(segments, .Any);

    {
        const file = try std.fs.cwd().openFile("data/auxiliary/WordBreakProperty.txt", .{});
        defer file.close();

        while (try ucd.nextLine(file)) |line| {
            const range = try ucd.asRange(ucd.column(line, 0).?);
            const prop = std.meta.stringToEnum(WordBreakProp, ucd.column(line, 1).?).?;
            const segment: Prop = switch (prop) {
                .CR => .CR,
                .LF => .LF,
                .Newline => .Newline,
                .Extend => .Extend,
                .ZWJ => .ZWJ,
                .Regional_Indicator => .Regional_Indicator,
                .Format => .Format,
                .Katakana => .Katakana,
                .Hebrew_Letter => .Hebrew_Letter,
                .ALetter => .ALetterNoPic,
                .Single_Quote => .Single_Quote,
                .Double_Quote => .Double_Quote,
                .MidNumLet => .MidNumLet,
                .MidLetter => .MidLetter,
                .MidNum => .MidNum,
                .Numeric => .Numeric,
                .ExtendNumLet => .ExtendNumLet,
                .WSegSpace => .WSegSpace,
                .Any => .Any,
            };
            @memset(segments[range.start..range.end], segment);
        }
    }

    {
        const file = try std.fs.cwd().openFile("data/emoji/emoji-data.txt", .{});
        defer file.close();

        while (try ucd.nextLine(file)) |line| {
            if (std.mem.eql(u8, "Extended_Pictographic", ucd.column(line, 1).?)) {
                const range = try ucd.asRange(ucd.column(line, 0).?);
                for (range.start..range.end) |code| {
                    switch (segments[code]) {
                        .ALetterNoPic => segments[code] = .ALetterPic,
                        .Any => segments[code] = .Pic,
                        else => unreachable,
                    }
                }
            }
        }
    }

    const bs = 128;
    const s1, const s2 = try ucd.twoStageTable(u8, Prop, bs, gpa, segments);

    const args = try std.process.argsAlloc(gpa);
    std.debug.assert(args.len == 2);

    const output = try std.fs.cwd().createFile(args[1], .{});
    defer output.close();
    const writer = output.writer();

    try ucd.printConst("Prop", Prop, writer);
    try ucd.printConst("bs", bs, writer);
    try ucd.printConst("s1", s1, writer);
    try ucd.printConst("s2", s2, writer);
}
