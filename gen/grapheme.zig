const std = @import("std");
const ucd = @import("ucd.zig");

// Segment  | CR | LF | Control | NonIndicExtend | IndicLinker | IndicExtendNoZWJ | ZWJ | RI                 | Prepend | SpacingMark | L | V | T | LV | LVT | Pic  | IndicConsonant | Any |
//
// Prop     | CR | LF | Control | Extend                                          | ZWJ | Regional_Indicator | Prepend | SpacingMark | L | V | T | LV | LVT | Any                         |
// Indic    | None                               | Linker      | Extend                 | None                                                                     | Consonant      |     |
// Pic      | false                                                                                                                                         | true | false                |

/// Intersection between GraphemeBreakProp, IndicConjunctBreak and Extended_Pictographic
const Segment = enum(u5) {
    /// GraphemeBreakProp.CR
    CR,
    /// GraphemeBreakProp.LF
    LF,
    /// GraphemeBreakProp.Control
    Control,
    /// GraphemeBreakProp.Extend - IndicConjunctBreak.Linker - IndicConjunctBreak.Extend
    NonIndicExtend,
    /// GraphemeBreakProp.ZWJ
    ZWJ,
    /// GraphemeBreakProp.Regional_Indicator
    RI,
    /// GraphemeBreakProp.Prepend
    Prepend,
    /// GraphemeBreakProp.SpacingMark
    SpacingMark,
    /// GraphemeBreakProp.L
    L,
    /// GraphemeBreakProp.V
    V,
    /// GraphemeBreakProp.T
    T,
    /// GraphemeBreakProp.LV
    LV,
    /// GraphemeBreakProp.LVT
    LVT,
    /// IndicConjunctBreak.Consonant
    IndicConsonant,
    /// IndicConjunctBreak.Linker
    IndicLinker,
    /// IndicConjunctBreak.Extend - GraphemeBreakProp.ZWJ
    IndicExtendNoZWJ,
    /// Extended_Pictographic
    Pic,
    /// GraphemeBreakProp.Any - IndicConjunctBreak.Consonant - Extended_Pictographic
    Any,
};

const GraphemeBreakProp = enum(u4) {
    CR,
    LF,
    Control,
    Extend,
    ZWJ,
    Regional_Indicator,
    Prepend,
    SpacingMark,
    L,
    V,
    T,
    LV,
    LVT,
    Any,
};

const IndicConjunctBreak = enum(u2) {
    None,
    Linker,
    Consonant,
    Extend,
};

pub fn main() !void {
    const gpa = std.heap.smp_allocator;

    const segments = try gpa.alloc(Segment, 0x110000);
    @memset(segments, .Any);

    {
        const file = try std.fs.cwd().openFile("data/auxiliary/GraphemeBreakProperty.txt", .{});
        defer file.close();

        while (try ucd.nextLine(file)) |line| {
            const prop = std.meta.stringToEnum(GraphemeBreakProp, ucd.column(line, 1).?).?;

            const segment: Segment = switch (prop) {
                .CR => .CR,
                .LF => .LF,
                .Control => .Control,
                .Extend => .NonIndicExtend,
                .ZWJ => .ZWJ,
                .Regional_Indicator => .RI,
                .Prepend => .Prepend,
                .SpacingMark => .SpacingMark,
                .L => .L,
                .V => .V,
                .T => .T,
                .LV => .LV,
                .LVT => .LVT,
                .Any => .Any,
            };

            const range = try ucd.asRange(ucd.column(line, 0).?);
            @memset(segments[range.start..range.end], segment);
        }
    }

    {
        const file = try std.fs.cwd().openFile("data/DerivedCoreProperties.txt", .{});
        defer file.close();

        while (try ucd.nextLine(file)) |line| {
            if (std.mem.eql(u8, "InCB", ucd.column(line, 1).?)) {
                const range = try ucd.asRange(ucd.column(line, 0).?);
                const indic = std.meta.stringToEnum(
                    IndicConjunctBreak,
                    ucd.column(line, 2).?,
                ).?;

                for (range.start..range.end) |code| {
                    switch (indic) {
                        .None => std.debug.assert(segments[code] == .Any),
                        .Consonant => {
                            std.debug.assert(segments[code] == .Any);
                            segments[code] = .IndicConsonant;
                        },
                        .Linker => {
                            std.debug.assert(segments[code] == .NonIndicExtend);
                            segments[code] = .IndicLinker;
                        },
                        .Extend => {
                            std.debug.assert(segments[code] == .NonIndicExtend or segments[code] == .ZWJ);
                            if (segments[code] != .ZWJ) segments[code] = .IndicExtendNoZWJ;
                        },
                    }
                }
            }
        }
    }

    {
        const file = try std.fs.cwd().openFile("data/emoji/emoji-data.txt", .{});
        defer file.close();

        while (try ucd.nextLine(file)) |line| {
            if (std.mem.eql(u8, "Extended_Pictographic", ucd.column(line, 1).?)) {
                const range = try ucd.asRange(ucd.column(line, 0).?);
                for (range.start..range.end) |code| {
                    std.debug.assert(segments[code] == .Any);
                    segments[code] = .Pic;
                }
            }
        }
    }

    const bs = 256;
    const s1, const s2 = try ucd.twoStageTable(u8, Segment, bs, gpa, segments);

    const args = try std.process.argsAlloc(gpa);
    std.debug.assert(args.len == 2);

    const output = try std.fs.cwd().createFile(args[1], .{});
    defer output.close();
    const writer = output.writer();

    try ucd.printConst("Segment", Segment, writer);
    try ucd.printConst("bs", bs, writer);
    try ucd.printConst("s1", s1, writer);
    try ucd.printConst("s2", s2, writer);
}
