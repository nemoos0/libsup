const std = @import("std");
const utf8 = @import("utf8");
const code_point = @import("code_point");
const grapheme_table = @import("grapheme_table");

pub const Iterator = struct {
    source: code_point.FatIterator,
    codepoints: [2]?code_point.Fat = .{ null, null },

    pub fn init(source: code_point.FatIterator) !Iterator {
        var iter: Iterator = .{ .source = source };
        try iter.advance();
        return iter;
    }

    fn advance(iter: *Iterator) !void {
        iter.codepoints[0] = iter.codepoints[1];
        iter.codepoints[1] = try iter.source.next();
    }

    pub fn next(iter: *Iterator) !?usize {
        if (iter.codepoints[1] == null) return null;

        var state: State = .{};
        while (true) {
            try iter.advance();

            if (iter.codepoints[1] == null) break;

            const left = iter.codepoints[0].?.code;
            const right = iter.codepoints[1].?.code;

            if (right < 0x300 and // Not an Extend/SpacingMark/ZWJ
                left < 0x600 // Not a Prepend
            ) {
                if (left == '\r' and right == '\n') try iter.advance();
                break;
            }

            const lseg = getSegment(left);
            const rseg = getSegment(right);

            state = state.step(lseg);

            const break_condition: BreakCondition = .init(lseg, rseg);

            switch (break_condition) {
                .always => break,
                .never => {},
                .unless_ri => if (state.ri != .after_ri) break,
                .unless_pic => if (state.pic != .after_zwj) break,
                .unless_indic => if (state.indic != .after_linker) break,
            }
        }

        const left = iter.codepoints[0].?;
        return left.off + left.len;
    }
};

const Segment = grapheme_table.Segment;

fn getSegment(code: u21) Segment {
    std.debug.assert(code < 0x110000);

    return grapheme_table.s2[
        @as(u32, @intCast(
            grapheme_table.s1[code / grapheme_table.bs],
        )) * grapheme_table.bs + code % grapheme_table.bs
    ];
}

const State = struct {
    ri: Ri = .unknown,
    pic: Pic = .unknown,
    indic: Indic = .unknown,

    const Ri = enum { unknown, after_ri };
    const Pic = enum { unknown, after_pic, after_zwj };
    const Indic = enum { unknown, after_consonant, after_linker };

    pub fn step(state: State, segment: Segment) State {
        return .{
            .ri = stepRi(state.ri, segment),
            .pic = stepPic(state.pic, segment),
            .indic = stepIndic(state.indic, segment),
        };
    }

    inline fn stepRi(ri: Ri, segment: Segment) Ri {
        const Row = std.EnumArray(Segment, Ri);
        const Table = std.EnumArray(Ri, Row);

        const table: Table = comptime blk: {
            var table: Table = .initFill(.initFill(.unknown));
            table.getPtr(.unknown).set(.RI, .after_ri);
            break :blk table;
        };

        return table.get(ri).get(segment);
    }

    inline fn stepPic(pic: Pic, segment: Segment) Pic {
        const Row = std.EnumArray(Segment, Pic);
        const Table = std.EnumArray(Pic, Row);

        const table: Table = comptime blk: {
            var table: Table = .initFill(.initFill(.unknown));

            for (&table.values) |*row| row.set(.Pic, .after_pic);

            table.getPtr(.after_pic).set(.NonIndicExtend, .after_pic);
            table.getPtr(.after_pic).set(.IndicLinker, .after_pic);
            table.getPtr(.after_pic).set(.IndicExtendNoZWJ, .after_pic);

            table.getPtr(.after_pic).set(.ZWJ, .after_zwj);

            break :blk table;
        };

        return table.get(pic).get(segment);
    }

    inline fn stepIndic(indic: Indic, segment: Segment) Indic {
        const Row = std.EnumArray(Segment, Indic);
        const Table = std.EnumArray(Indic, Row);

        const table: Table = comptime blk: {
            var table: Table = .initFill(.initFill(.unknown));

            for (&table.values) |*row| row.set(.IndicConsonant, .after_consonant);

            table.getPtr(.after_consonant).set(.IndicExtendNoZWJ, .after_consonant);
            table.getPtr(.after_consonant).set(.ZWJ, .after_consonant);
            table.getPtr(.after_consonant).set(.IndicLinker, .after_linker);

            table.getPtr(.after_linker).set(.IndicExtendNoZWJ, .after_linker);
            table.getPtr(.after_linker).set(.ZWJ, .after_linker);
            table.getPtr(.after_linker).set(.IndicLinker, .after_linker);

            break :blk table;
        };

        return table.get(indic).get(segment);
    }
};

const BreakCondition = enum {
    always,
    never,
    unless_indic,
    unless_pic,
    unless_ri,

    pub fn init(left: Segment, right: Segment) BreakCondition {
        const Row = std.EnumArray(Segment, BreakCondition);
        const Table = std.EnumArray(Segment, Row);

        const table: Table = comptime blk: {
            // GB999
            var table: Table = .initFill(.initFill(.always));

            // GB12/GB13
            table.getPtr(.RI).set(.RI, .unless_ri);

            // GB11
            table.getPtr(.ZWJ).set(.Pic, .unless_pic);

            // GB9c
            table.getPtr(.IndicLinker).set(.IndicConsonant, .unless_indic);
            table.getPtr(.IndicExtendNoZWJ).set(.IndicConsonant, .unless_indic);
            table.getPtr(.ZWJ).set(.IndicConsonant, .unless_indic);

            // GB9b
            table.set(.Prepend, Row.initFill(.never));

            // GB9a
            for (&table.values) |*row| row.set(.SpacingMark, .never);

            // GB9
            for (&table.values) |*row| row.set(.NonIndicExtend, .never);
            for (&table.values) |*row| row.set(.IndicLinker, .never);
            for (&table.values) |*row| row.set(.IndicExtendNoZWJ, .never);
            for (&table.values) |*row| row.set(.ZWJ, .never);

            // GB8
            table.getPtr(.LVT).set(.T, .never);
            table.getPtr(.T).set(.T, .never);

            // GB7
            table.getPtr(.LV).set(.V, .never);
            table.getPtr(.LV).set(.T, .never);
            table.getPtr(.V).set(.V, .never);
            table.getPtr(.V).set(.T, .never);

            // GB6
            table.getPtr(.L).set(.L, .never);
            table.getPtr(.L).set(.V, .never);
            table.getPtr(.L).set(.LV, .never);
            table.getPtr(.L).set(.LVT, .never);

            // GB5
            for (&table.values) |*row| row.set(.Control, .always);
            for (&table.values) |*row| row.set(.CR, .always);
            for (&table.values) |*row| row.set(.LF, .always);

            // GB4
            table.set(.Control, Row.initFill(.always));
            table.set(.CR, Row.initFill(.always));
            table.set(.LF, Row.initFill(.always));

            // GB3
            table.getPtr(.CR).set(.LF, .never);

            break :blk table;
        };

        return table.get(left).get(right);
    }
};

test "Iterator" {
    const input = "Hello";

    var decoder: utf8.Utf8Decoder = .{ .bytes = input };
    var graph: Iterator = try .init(decoder.fatIterator());

    for (1..6) |expected| {
        try std.testing.expectEqualDeep(expected, try graph.next());
    }
    try std.testing.expectEqual(null, try graph.next());
}

test "conformance" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const file = try std.fs.cwd().openFile("data/auxiliary/GraphemeBreakTest.txt", .{});
    defer file.close();
    const reader = file.reader();

    while (try reader.readUntilDelimiterOrEofAlloc(arena, '\n', 4096)) |line| : (_ = arena_state.reset(.retain_capacity)) {
        const content = line[0 .. std.mem.indexOfAny(u8, line, "#@") orelse line.len];
        if (content.len == 0) continue;

        var string: std.ArrayListUnmanaged(u8) = .empty;
        var graphemes: std.ArrayListUnmanaged(usize) = .empty;

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

            try graphemes.append(arena, string.items.len);
        }

        var decoder: utf8.Utf8Decoder = .{ .bytes = string.items };
        var graph: Iterator = try .init(decoder.fatIterator());

        for (graphemes.items) |expected| {
            std.testing.expectEqualDeep(expected, try graph.next()) catch |err| {
                std.debug.print("{s}\n", .{line});
                return err;
            };
        }
        try std.testing.expectEqual(null, try graph.next());
    }
}
