const std = @import("std");
const code_point = @import("code_point");

const word_table = @import("word_table");

const assert = std.debug.assert;

pub const Iterator = struct {
    source: code_point.FatIterator,
    fats: [2]?code_point.Fat = .{ null, null },
    pending: ?usize = null,

    pub fn init(source: code_point.FatIterator) !Iterator {
        var iter: Iterator = .{ .source = source };
        try iter.advance();
        return iter;
    }

    fn advance(iter: *Iterator) !void {
        iter.fats[0] = iter.fats[1];
        iter.fats[1] = try iter.source.next();
    }

    pub fn next(iter: *Iterator) !?usize {
        if (iter.pending) |pending| {
            iter.pending = null;
            return pending;
        }

        if (iter.fats[1] == null) return null;

        var state: State = .{};
        while (true) {
            try iter.advance();

            if (iter.fats[1] == null) break;

            const left = iter.fats[0].?;
            const right = iter.fats[1].?;

            const left_prop = getProp(left.code);
            const right_prop = getProp(right.code);

            state = state.step(left_prop);

            const break_condition: BreakCondition = .init(left_prop, right_prop);

            switch (break_condition) {
                .previous => {
                    // NOTE: I have no idea why but this works
                    if (right_prop == .WSegSpace) break;

                    const break_condition2: BreakCondition = .init(state.previous, right_prop);
                    switch (break_condition2) {
                        .previous => unreachable,

                        .always => break,
                        .never => {},

                        .seek_one => iter.pending = right.off,

                        .unless_letter => if (state.letter == .after_mid) {
                            assert(iter.pending != null);
                            iter.pending = null;
                        } else break,
                        .unless_hebrew => if (state.hebrew == .after_quote) {
                            assert(iter.pending != null);
                            iter.pending = null;
                        } else break,
                        .unless_numeric => if (state.numeric == .after_mid) {
                            assert(iter.pending != null);
                            iter.pending = null;
                        } else break,
                        .unless_ri => if (state.ri != .after_ri) break,
                    }
                },

                .always => break,
                .never => {},

                .seek_one => iter.pending = right.off,

                .unless_letter => if (state.letter == .after_mid) {
                    assert(iter.pending != null);
                    iter.pending = null;
                } else break,
                .unless_hebrew => if (state.hebrew == .after_quote) {
                    assert(iter.pending != null);
                    iter.pending = null;
                } else break,
                .unless_numeric => if (state.numeric == .after_mid) {
                    assert(iter.pending != null);
                    iter.pending = null;
                } else break,
                .unless_ri => if (state.ri != .after_ri) break,
            }
        }

        const left = iter.fats[0].?;
        if (iter.pending) |pending| {
            iter.pending = left.off + left.len;
            return pending;
        } else {
            return left.off + left.len;
        }
    }
};

test "Iterator" {
    const utf8 = @import("utf8");

    const string = "The quick (“brown”) fox can’t jump 32.3 feet, right?";
    var decoder: utf8.Decoder = try .init(string);
    var words: Iterator = try .init(decoder.fatIterator());

    var pos: usize = 0;
    for (&[_][]const u8{
        "The",     " ", "quick", " ", "(",    "“", "brown", "”", ")", " ",     "fox", " ",
        "can’t", " ", "jump",  " ", "32.3", " ",   "feet",  ",",   " ", "right", "?",
    }) |expected| {
        const next = try words.next();
        try std.testing.expectEqualStrings(expected, string[pos..next.?]);
        pos = next.?;
    }
    try std.testing.expectEqual(null, try words.next());
}

test "conformance" {
    const utf8 = @import("utf8");

    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const file = try std.fs.cwd().openFile("data/auxiliary/WordBreakTest.txt", .{});
    defer file.close();
    const reader = file.reader();

    while (try reader.readUntilDelimiterOrEofAlloc(arena, '\n', 4096)) |line| : (_ = arena_state.reset(.retain_capacity)) {
        const content = line[0 .. std.mem.indexOfAny(u8, line, "#@") orelse line.len];
        if (content.len == 0) continue;

        var string: std.ArrayListUnmanaged(u8) = .empty;
        var words: std.ArrayListUnmanaged(usize) = .empty;

        const without_last_column = content["÷ ".len..std.mem.lastIndexOf(u8, content, " ÷").?];

        var codepoint_block_iter = std.mem.tokenizeSequence(u8, without_last_column, " ÷ ");
        while (codepoint_block_iter.next()) |codepoint_block| {
            var codepoint_iter = std.mem.tokenizeSequence(u8, codepoint_block, " × ");
            while (codepoint_iter.next()) |codepoint_slice| {
                const code = try std.fmt.parseInt(u21, codepoint_slice, 16);

                try string.ensureUnusedCapacity(arena, 4);
                string.items.len += try std.unicode.utf8Encode(
                    code,
                    string.unusedCapacitySlice(),
                );
            }

            try words.append(arena, string.items.len);
        }

        var decoder: utf8.Decoder = .{ .bytes = string.items };
        var word_iter: Iterator = try .init(decoder.fatIterator());

        for (words.items) |expected| {
            std.testing.expectEqual(expected, try word_iter.next()) catch |err| {
                std.debug.print("{s}\n", .{line});
                return err;
            };
        }

        std.testing.expectEqual(null, try word_iter.next()) catch |err| {
            std.debug.print("{s}\n", .{line});
            return err;
        };
    }
}

const Prop = word_table.Prop;

fn getProp(code: u21) Prop {
    std.debug.assert(code < 0x110000);

    return word_table.s2[
        @as(u32, @intCast(
            word_table.s1[code / word_table.bs],
        )) * word_table.bs + code % word_table.bs
    ];
}

const State = struct {
    letter: Letter = .unknown,
    hebrew: Hebrew = .unknown,
    numeric: Numeric = .unknown,
    ri: Ri = .unknown,
    previous: Prop = .Any,

    const Letter = enum { unknown, after_letter, after_mid };
    const Hebrew = enum { unknown, after_hebrew, after_quote };
    const Numeric = enum { unknown, after_numeric, after_mid };
    const Ri = enum { unknown, after_ri };

    pub fn step(state: State, prop: Prop) State {
        var res: State = .{};

        if (prop == .Extend or prop == .Format or prop == .ZWJ) {
            return state;
        }
        res.previous = prop;

        if (prop == .ALetterPic or prop == .ALetterNoPic or prop == .Hebrew_Letter) {
            res.letter = .after_letter;
        } else if (state.letter == .after_letter and
            (prop == .MidLetter or prop == .MidNumLet or prop == .Single_Quote))
        {
            res.letter = .after_mid;
        } else {
            res.letter = .unknown;
        }

        if (prop == .Hebrew_Letter) {
            res.hebrew = .after_hebrew;
        } else if (state.hebrew == .after_hebrew and prop == .Double_Quote) {
            res.hebrew = .after_quote;
        } else {
            res.hebrew = .unknown;
        }

        if (prop == .Numeric) {
            res.numeric = .after_numeric;
        } else if (state.numeric == .after_numeric and
            (prop == .MidNum or prop == .MidNumLet or prop == .Single_Quote))
        {
            res.numeric = .after_mid;
        } else {
            res.numeric = .unknown;
        }

        if (state.ri == .unknown and prop == .Regional_Indicator) {
            res.ri = .after_ri;
        } else {
            res.ri = .unknown;
        }

        return res;
    }
};

const BreakCondition = enum {
    always,
    never,
    previous,

    seek_one,

    unless_letter,
    unless_hebrew,
    unless_numeric,
    unless_ri,

    pub fn init(left: Prop, right: Prop) BreakCondition {
        const Row = std.EnumArray(Prop, BreakCondition);
        const Table = std.EnumArray(Prop, Row);

        const table: Table = comptime blk: {
            // WB999
            var table: Table = .initFill(.initFill(.always));

            // WB15/WB16
            table.getPtr(.Regional_Indicator).set(.Regional_Indicator, .unless_ri);

            // WB13b
            table.getPtr(.ExtendNumLet).set(.ALetterPic, .never);
            table.getPtr(.ExtendNumLet).set(.ALetterNoPic, .never);
            table.getPtr(.ExtendNumLet).set(.Hebrew_Letter, .never);
            table.getPtr(.ExtendNumLet).set(.Numeric, .never);
            table.getPtr(.ExtendNumLet).set(.Katakana, .never);

            // WB13a
            table.getPtr(.ALetterPic).set(.ExtendNumLet, .never);
            table.getPtr(.ALetterNoPic).set(.ExtendNumLet, .never);
            table.getPtr(.Hebrew_Letter).set(.ExtendNumLet, .never);
            table.getPtr(.Numeric).set(.ExtendNumLet, .never);
            table.getPtr(.Katakana).set(.ExtendNumLet, .never);
            table.getPtr(.ExtendNumLet).set(.ExtendNumLet, .never);

            // WB13
            table.getPtr(.Katakana).set(.Katakana, .never);

            // WB12
            table.getPtr(.Numeric).set(.MidNum, .seek_one);
            table.getPtr(.Numeric).set(.MidNumLet, .seek_one);
            table.getPtr(.Numeric).set(.Single_Quote, .seek_one);

            // WB11
            table.getPtr(.MidNum).set(.Numeric, .unless_numeric);
            table.getPtr(.MidNumLet).set(.Numeric, .unless_numeric);
            table.getPtr(.Single_Quote).set(.Numeric, .unless_numeric);

            // WB10
            table.getPtr(.Numeric).set(.ALetterPic, .never);
            table.getPtr(.Numeric).set(.ALetterNoPic, .never);
            table.getPtr(.Numeric).set(.Hebrew_Letter, .never);

            // WB9
            table.getPtr(.ALetterPic).set(.Numeric, .never);
            table.getPtr(.ALetterNoPic).set(.Numeric, .never);
            table.getPtr(.Hebrew_Letter).set(.Numeric, .never);

            // WB8
            table.getPtr(.Numeric).set(.Numeric, .never);

            // WB7c
            table.getPtr(.Double_Quote).set(.Hebrew_Letter, .unless_hebrew);

            // WB7b
            table.getPtr(.Hebrew_Letter).set(.Double_Quote, .seek_one);

            // WB7a
            table.getPtr(.Hebrew_Letter).set(.Single_Quote, .never);

            // WB7
            table.getPtr(.MidLetter).set(.ALetterNoPic, .unless_letter);
            table.getPtr(.MidLetter).set(.ALetterPic, .unless_letter);
            table.getPtr(.MidLetter).set(.Hebrew_Letter, .unless_letter);
            table.getPtr(.MidNumLet).set(.ALetterNoPic, .unless_letter);
            table.getPtr(.MidNumLet).set(.ALetterPic, .unless_letter);
            table.getPtr(.MidNumLet).set(.Hebrew_Letter, .unless_letter);
            table.getPtr(.Single_Quote).set(.ALetterNoPic, .unless_letter);
            table.getPtr(.Single_Quote).set(.ALetterPic, .unless_letter);
            table.getPtr(.Single_Quote).set(.Hebrew_Letter, .unless_letter);

            // WB6
            table.getPtr(.ALetterNoPic).set(.MidLetter, .seek_one);
            table.getPtr(.ALetterPic).set(.MidLetter, .seek_one);
            table.getPtr(.Hebrew_Letter).set(.MidLetter, .seek_one);
            table.getPtr(.ALetterNoPic).set(.MidNumLet, .seek_one);
            table.getPtr(.ALetterPic).set(.MidNumLet, .seek_one);
            table.getPtr(.Hebrew_Letter).set(.MidNumLet, .seek_one);
            table.getPtr(.ALetterNoPic).set(.Single_Quote, .seek_one);
            table.getPtr(.ALetterPic).set(.Single_Quote, .seek_one);
            // WB7a is stronger than this for some reason
            // table.getPtr(.Hebrew_Letter).set(.Single_Quote, .seek_one);

            // WB5
            table.getPtr(.ALetterNoPic).set(.ALetterNoPic, .never);
            table.getPtr(.ALetterNoPic).set(.ALetterPic, .never);
            table.getPtr(.ALetterNoPic).set(.Hebrew_Letter, .never);
            table.getPtr(.ALetterPic).set(.ALetterNoPic, .never);
            table.getPtr(.ALetterPic).set(.ALetterPic, .never);
            table.getPtr(.ALetterPic).set(.Hebrew_Letter, .never);
            table.getPtr(.Hebrew_Letter).set(.ALetterNoPic, .never);
            table.getPtr(.Hebrew_Letter).set(.ALetterPic, .never);
            table.getPtr(.Hebrew_Letter).set(.Hebrew_Letter, .never);

            // WB4
            for (&table.values) |*row| row.set(.Extend, .never);
            for (&table.values) |*row| row.set(.Format, .never);
            for (&table.values) |*row| row.set(.ZWJ, .never);
            table.set(.Extend, Row.initFill(.previous));
            table.set(.Format, Row.initFill(.previous));
            table.set(.ZWJ, Row.initFill(.previous));

            // WB3d
            table.getPtr(.WSegSpace).set(.WSegSpace, .never);

            // WB3c
            table.getPtr(.ZWJ).set(.Pic, .never);
            table.getPtr(.ZWJ).set(.ALetterPic, .never);

            // WB3b
            for (&table.values) |*row| row.set(.Newline, .always);
            for (&table.values) |*row| row.set(.CR, .always);
            for (&table.values) |*row| row.set(.LF, .always);

            // WB3a
            table.set(.Newline, Row.initFill(.always));
            table.set(.CR, Row.initFill(.always));
            table.set(.LF, Row.initFill(.always));

            // WB3
            table.getPtr(.CR).set(.LF, .never);

            break :blk table;
        };

        return table.get(left).get(right);
    }
};
