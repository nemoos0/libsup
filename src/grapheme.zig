const std = @import("std");
const codepoint = @import("codepoint");
const grapheme_table = @import("grapheme_table");

pub const Grapheme = struct {
    offset: usize,
    len: u16,
};

pub const Iterator = struct {
    source: codepoint.Iterator,
    codepoints: [2]?codepoint.Codepoint = .{ null, null },
    segments: [2]Segment = .{ .Any, .Any },

    pub fn init(source: codepoint.Iterator) !Iterator {
        var iter: Iterator = .{ .source = source };
        try iter.read();
        return iter;
    }

    fn read(iter: *Iterator) !void {
        iter.codepoints[0] = iter.codepoints[1];
        iter.segments[0] = iter.segments[1];

        if (try iter.source.next()) |cp| {
            iter.codepoints[1] = cp;
            iter.segments[1] = getSegment(cp.code);
        } else {
            iter.codepoints[1] = null;
            iter.segments[1] = .Any;
        }
    }

    pub fn next(iter: *Iterator) !?Grapheme {
        if (iter.codepoints[1] == null) return null;

        var grapheme: Grapheme = .{
            .offset = iter.codepoints[1].?.offset,
            .len = iter.codepoints[1].?.len,
        };

        try iter.read();

        var state: State = .{};

        while (iter.codepoints[1]) |right| {
            state = state.step(iter.segments[0]);

            const break_condition: BreakCondition = .init(
                iter.segments[0],
                iter.segments[1],
            );

            switch (break_condition) {
                .always => break,
                .never => {},
                .unless_ri => if (state.ri != .after_ri) break,
                .unless_pic => if (state.pic != .after_zwj) break,
                .unless_indic => if (state.indic != .after_linker) break,
            }

            grapheme.len += right.len;

            try iter.read();
        }

        return grapheme;
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
    ri: Ri = .none,
    pic: Pic = .none,
    indic: Indic = .none,

    const Ri = enum { none, after_ri };
    const Pic = enum { none, after_pic, after_zwj };
    const Indic = enum { none, after_consonant, after_linker };

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
            var table: Table = .initFill(.initFill(.none));
            table.getPtr(.none).set(.RI, .after_ri);
            break :blk table;
        };

        return table.get(ri).get(segment);
    }

    inline fn stepPic(pic: Pic, segment: Segment) Pic {
        const Row = std.EnumArray(Segment, Pic);
        const Table = std.EnumArray(Pic, Row);

        const table: Table = comptime blk: {
            var table: Table = .initFill(.initFill(.none));

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
            var table: Table = .initFill(.initFill(.none));

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

    var utf8: codepoint.Utf8 = .{ .bytes = input };
    var graph: Iterator = try .init(utf8.iterator());

    for (&[_]Grapheme{
        .{ .offset = 0, .len = 1 },
        .{ .offset = 1, .len = 1 },
        .{ .offset = 2, .len = 1 },
        .{ .offset = 3, .len = 1 },
        .{ .offset = 4, .len = 1 },
    }) |expected| {
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
        var graphemes: std.ArrayListUnmanaged(Grapheme) = .empty;

        const without_last_column = content["÷ ".len..std.mem.lastIndexOf(u8, content, " ÷").?];

        var codepoint_block_iter = std.mem.tokenizeSequence(u8, without_last_column, " ÷ ");
        while (codepoint_block_iter.next()) |codepoint_block| {
            var grapheme: Grapheme = .{
                .offset = string.items.len,
                .len = undefined,
            };

            var codepoint_iter = std.mem.tokenizeSequence(u8, codepoint_block, " × ");
            while (codepoint_iter.next()) |codepoint_slice| {
                const code = try std.fmt.parseInt(u21, codepoint_slice, 16);

                try string.ensureUnusedCapacity(arena, 4);
                string.items.len += try std.unicode.utf8Encode(
                    code,
                    string.unusedCapacitySlice(),
                );
            }

            grapheme.len = @intCast(string.items.len - grapheme.offset);
            try graphemes.append(arena, grapheme);
        }

        var utf8: codepoint.Utf8 = .{ .bytes = string.items };
        var graph: Iterator = try .init(utf8.iterator());

        for (graphemes.items) |expected| {
            try std.testing.expectEqualDeep(expected, try graph.next());
        }
        try std.testing.expectEqual(null, try graph.next());
    }
}
