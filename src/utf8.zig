const std = @import("std");
const builtin = @import("builtin");
const code_point = @import("code_point");

const unicode = std.unicode;
const assert = std.debug.assert;

const VLEN = std.simd.suggestVectorLength(u8) orelse 1;
const Chunk = @Vector(VLEN, u8);

pub const Decoder = struct {
    bytes: []const u8,
    pos: usize = 0,

    const lengths_table: [16]u3 align(16) = blk: {
        var t: [16]u3 = .{0} ** 16;

        // 0000 0000 - 0111 1111
        @memset(t[0x0..0x8], 1);
        // 1100 0000 - 1101 1111
        @memset(t[0xc..0xe], 2);
        // 1110 0000 - 1110 1111
        @memset(t[0xe..0xf], 3);
        // 1111 0000 - 1111 0111
        @memset(t[0xf..], 4);

        break :blk t;
    };

    pub fn init(bytes: []const u8) !Decoder {
        if (!validate(bytes)) {
            return error.InvalidUtf8;
        }

        return .{ .bytes = bytes };
    }

    pub fn nextFat(utf8: *Decoder) ?code_point.Fat {
        if (utf8.pos >= utf8.bytes.len) return null;

        const first_byte = utf8.bytes[utf8.pos];
        utf8.pos += 1;

        if (first_byte < 0x80) return .{
            .off = utf8.pos - 1,
            .len = 1,
            .code = first_byte,
        };

        var fat: code_point.Fat = .{
            .off = utf8.pos - 1,
            .len = undefined,
            .code = undefined,
        };

        switch (lengths_table[first_byte >> 4]) {
            inline 2...4 => |len| {
                const mask = switch (len) {
                    2 => 0x1f,
                    3 => 0x0f,
                    4 => 0x07,
                    else => unreachable,
                };

                fat.len = len;
                fat.code = first_byte & mask;

                inline for (1..len) |_| {
                    fat.code = (utf8.bytes[utf8.pos] & 0x3f) | (fat.code << 6);
                    utf8.pos += 1;
                }

                return fat;
            },
            else => unreachable,
        }
    }

    pub fn nextCode(utf8: *Decoder) ?u21 {
        return if (utf8.nextFat()) |ctx| ctx.code else null;
    }

    pub fn fatIterator(utf8: *Decoder) code_point.FatIterator {
        return .{ .context = utf8, .nextFn = typeErasedNextFat };
    }

    fn typeErasedNextFat(ptr: *anyopaque) error{}!?code_point.Fat {
        const utf8: *Decoder = @alignCast(@ptrCast(ptr));
        return utf8.nextFat();
    }

    pub fn codeIterator(utf8: *Decoder) code_point.Iterator {
        return .{ .context = utf8, .nextFn = typeErasedNextCode };
    }

    fn typeErasedNextCode(ptr: *anyopaque) error{}!?u21 {
        const utf8: *Decoder = @alignCast(@ptrCast(ptr));
        return utf8.nextCode();
    }
};

test "Decoder" {
    const string = "ábç 퀀 😀";
    var decoder: Decoder = try .init(string);

    const view = try unicode.Utf8View.init(string);
    var iter = view.iterator();

    while (iter.nextCodepoint()) |expected| {
        try std.testing.expectEqual(expected, try decoder.codeIterator().next());
    }
    try std.testing.expectEqual(null, try decoder.codeIterator().next());
}

pub const Encoder = struct {
    source: code_point.Iterator,
    buffer: std.BoundedArray(u8, 4) = .{},

    pub const Reader = std.io.Reader(*Encoder, anyerror, read);

    pub fn read(encoder: *Encoder, dest: []u8) !usize {
        var pos: usize = 0;

        while (pos < dest.len) : (pos += 1) {
            const byte = encoder.buffer.pop() orelse break;
            dest[pos] = byte;
        } else return pos;

        while (pos + 4 < dest.len) {
            const code = try encoder.source.next() orelse return pos;

            const len = try unicode.utf8Encode(code, dest[pos..]);
            pos += len;
        }

        while (pos < dest.len) {
            const code = try encoder.source.next() orelse return pos;

            var buf: [4]u8 = undefined;
            var len = try unicode.utf8Encode(code, &buf);

            const available = @min(len, dest.len - pos);
            @memcpy(dest[pos..][0..available], buf[0..available]);
            pos += available;

            while (len > available) {
                len -= 1;
                encoder.buffer.appendAssumeCapacity(buf[len]);
            }
        }

        return pos;
    }

    pub fn reader(encoder: *Encoder) Reader {
        return .{ .context = encoder };
    }

    pub fn pump(encoder: Encoder, writer: anytype) !void {
        while (try encoder.source.next()) |code| {
            assert(code < 0x110000);

            if (code < 1 << 7) {
                try writer.writeByte(@intCast(code));
            } else if (code < 1 << 11) {
                try writer.writeByte(@intCast((code >> 6) | 0xc0));
                try writer.writeByte(@intCast(code & 0x3f | 0x80));
            } else if (code < 1 << 16) {
                try writer.writeByte(@intCast((code >> 12) | 0xe0));
                try writer.writeByte(@intCast((code >> 6) & 0x3f | 0x80));
                try writer.writeByte(@intCast(code & 0x3f | 0x80));
            } else {
                try writer.writeByte(@intCast((code >> 18) | 0xf0));
                try writer.writeByte(@intCast((code >> 12) & 0x3f | 0x80));
                try writer.writeByte(@intCast((code >> 6) & 0x3f | 0x80));
                try writer.writeByte(@intCast(code & 0x3f | 0x80));
            }
        }
    }
};

test "Encoder.pump" {
    const string = "ábç 퀀 😀";
    var decoder: Decoder = try .init(string);
    var encoder: Encoder = .{ .source = decoder.codeIterator() };

    var output: std.ArrayList(u8) = .init(std.testing.allocator);
    defer output.deinit();

    try encoder.pump(output.writer());
    try std.testing.expectEqualStrings(string, output.items);
}

test "Encoder.reader" {
    const string = "ábç 퀀 😀";
    var decoder: Decoder = try .init(string);
    var encoder: Encoder = .{ .source = decoder.codeIterator() };

    var output: std.ArrayList(u8) = .init(std.testing.allocator);
    defer output.deinit();

    var fifo: std.fifo.LinearFifo(u8, .{ .Static = 1 }) = .init();
    try fifo.pump(encoder.reader(), output.writer());
    try std.testing.expectEqualStrings(string, output.items);
}

pub fn readerDecoder(reader: anytype) ReaderDecoder(4096, @TypeOf(reader)) {
    return .{ .unbuffered_reader = reader };
}

pub fn ReaderDecoder(comptime buffer_size: usize, comptime ReaderType: type) type {
    assert(buffer_size >= 4);

    return struct {
        unbuffered_reader: ReaderType,
        buf: [buffer_size]u8 = undefined,
        base_offset: usize = 0,
        start: usize = 0,
        end: usize = 0,

        const Self = @This();

        /// https://bjoern.hoehrmann.de/utf-8/decoder/dfa
        pub fn nextFat(self: *Self) !?code_point.Fat {
            if (self.start >= self.end) {
                self.base_offset += self.end;
                self.end = try self.unbuffered_reader.read(&self.buf);
                if (self.end == 0) return null;
                self.start = 0;
            }

            const off = self.base_offset + self.start;

            var byte = self.buf[self.start];
            self.start += 1;

            if (byte < 0x80) return .{ .off = off, .len = 1, .code = byte };

            var class = classes[byte];
            var state = transitions.get(.accept).get(class);

            if (state == .reject) return error.Utf8InacceptStartByte;
            if (self.start >= self.end) {
                self.base_offset += self.end;
                self.end = try self.unbuffered_reader.read(&self.buf);
                if (self.end == 0) return error.Utf8ExpectedContinuation;
                self.start = 0;
            }

            var code: u21 = byte & masks.get(class);

            byte = self.buf[self.start];
            class = classes[byte];
            state = transitions.get(state).get(class);
            code = (byte & 0x3f) | (code << 6);
            self.start += 1;

            if (state == .accept) return .{ .off = off, .len = 2, .code = code };
            if (state == .reject) return error.Utf8ExpectedContinuation;
            if (self.start >= self.end) {
                self.base_offset += self.end;
                self.end = try self.unbuffered_reader.read(&self.buf);
                if (self.end == 0) return error.Utf8ExpectedContinuation;
                self.start = 0;
            }

            byte = self.buf[self.start];
            class = classes[byte];
            state = transitions.get(state).get(class);
            code = (byte & 0x3f) | (code << 6);
            self.start += 1;

            if (state == .accept) return .{ .off = off, .len = 3, .code = code };
            if (state == .reject) return error.InacceptUtf8;
            if (self.start >= self.end) {
                self.base_offset += self.end;
                self.end = try self.unbuffered_reader.read(&self.buf);
                if (self.end == 0) return error.Utf8ExpectedContinuation;
                self.start = 0;
            }

            byte = self.buf[self.start];
            class = classes[byte];
            state = transitions.get(state).get(class);
            code = (byte & 0x3f) | (code << 6);
            self.start += 1;

            if (state == .reject) return error.InacceptUtf8;
            assert(state == .accept);
            return .{ .off = off, .len = 4, .code = code };
        }

        pub fn nextCode(self: *@This()) !?u21 {
            return if (try self.nextFat()) |ctx| ctx.code else null;
        }

        pub fn fatIterator(self: *@This()) code_point.FatIterator {
            return .{ .context = self, .nextFn = typeErasedNextFat };
        }

        fn typeErasedNextFat(ptr: *anyopaque) !?code_point.Fat {
            const self: *@This() = @alignCast(@ptrCast(ptr));
            return self.nextFat();
        }

        pub fn codeIterator(self: *@This()) code_point.Iterator {
            return .{ .context = self, .nextFn = typeErasedNextCode };
        }

        fn typeErasedNextCode(ptr: *anyopaque) !?u21 {
            const self: *@This() = @alignCast(@ptrCast(ptr));
            return self.nextCode();
        }
    };
}

test "ReaderDecoder" {
    const string = "ábç 퀀 😀";
    var stream = std.io.fixedBufferStream(string);
    var decoder = readerDecoder(stream.reader());

    const view = try unicode.Utf8View.init(string);
    var iter = view.iterator();

    while (iter.nextCodepoint()) |expected| {
        try std.testing.expectEqual(expected, try decoder.codeIterator().next());
    }
    try std.testing.expectEqual(null, try decoder.codeIterator().next());
}

const Class = enum(u4) {
    /// ASCII 0x00 - 0x7f
    b1,
    /// Continuation bytes 0x80 - 0x8f
    c1,
    /// Continuation bytes 0x90 - 0x9f
    c2,
    /// Continuation bytes 0xa0 - 0xbf
    c3,
    /// Invalid 0xc0 - 0xc1 | 0xf5 - 0xff
    xx,
    /// Two byte sequence 0xc2 - 0xdf
    b2,
    /// Three byte sequence overflow 0xe0
    b3o,
    /// Three byte sequence 0xe1 - 0xec | 0xee - 0xef
    b3,
    /// Three byte sequence surrogate 0xed
    b3s,
    /// Four byte sequence overflow 0xf0
    b4o,
    /// Four byte sequence 0xf1 - 0xf3
    b4,
    /// Four byte sequence too long 0xf4
    b4l,
};

const State = enum(u4) {
    accept,
    reject,

    one_more,
    two_more,
    three_more,

    three_byte_overlong,
    three_byte_surrogate,

    four_byte_overlong,
    four_byte_too_large,
};

const classes: [256]Class = .{
    // ASCII
    .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, // 0x0f
    .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, // 0x1f
    .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, // 0x2f
    .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, // 0x3f
    .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, // 0x4f
    .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, // 0x5f
    .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, // 0x6f
    .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, .b1, // 0x7f
    // Continuation
    .c1, .c1, .c1, .c1, .c1, .c1, .c1, .c1, .c1, .c1, .c1, .c1, .c1, .c1, .c1, .c1, // 0x8f
    .c2, .c2, .c2, .c2, .c2, .c2, .c2, .c2, .c2, .c2, .c2, .c2, .c2, .c2, .c2, .c2, // 0x9f
    .c3, .c3, .c3, .c3, .c3, .c3, .c3, .c3, .c3, .c3, .c3, .c3, .c3, .c3, .c3, .c3, // 0xaf
    .c3, .c3, .c3, .c3, .c3, .c3, .c3, .c3, .c3, .c3, .c3, .c3, .c3, .c3, .c3, .c3, // 0xbf
    // Two bytes sequences
    .xx, .xx, .b2, .b2, .b2, .b2, .b2, .b2, .b2, .b2, .b2, .b2, .b2, .b2, .b2, .b2, // 0xcf
    .b2, .b2, .b2, .b2, .b2, .b2, .b2, .b2, .b2, .b2, .b2, .b2, .b2, .b2, .b2, .b2, // 0xdf
    // Three bytes sequences
    .b3o, .b3, .b3, .b3, .b3, .b3, .b3, .b3, .b3, .b3, .b3, .b3, .b3, .b3s, .b3, .b3, // 0xef
    // Four bytes sequences
    .b4o, .b4, .b4, .b4, .b4l, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, // 0xff
};

const transitions: std.EnumArray(State, std.EnumArray(Class, State)) = .init(.{
    .accept = .initDefault(.reject, .{
        .b1 = .accept,
        .b2 = .one_more,
        .b3 = .two_more,
        .b4 = .three_more,
        .b3o = .three_byte_overlong,
        .b3s = .three_byte_surrogate,
        .b4o = .four_byte_overlong,
        .b4l = .four_byte_too_large,
    }),
    .reject = .initDefault(.reject, .{}),

    .one_more = .initDefault(.reject, .{ .c1 = .accept, .c2 = .accept, .c3 = .accept }),
    .two_more = .initDefault(.reject, .{ .c1 = .one_more, .c2 = .one_more, .c3 = .one_more }),
    .three_more = .initDefault(.reject, .{ .c1 = .two_more, .c2 = .two_more, .c3 = .two_more }),

    .three_byte_overlong = .initDefault(.reject, .{ .c3 = .one_more }),
    .three_byte_surrogate = .initDefault(.reject, .{ .c1 = .one_more, .c2 = .one_more }),

    .four_byte_overlong = .initDefault(.reject, .{ .c2 = .two_more, .c3 = .two_more }),
    .four_byte_too_large = .initDefault(.reject, .{ .c1 = .two_more }),
});

const masks: std.EnumArray(Class, u8) = .init(.{
    .b1 = 0xff,
    .b2 = 0x1f,
    .b3 = 0x0f,
    .b4 = 0x07,
    .b3o = 0x0f,
    .b3s = 0x0f,
    .b4o = 0x07,
    .b4l = 0x07,
    .c1 = 0x3f,
    .c2 = 0x3f,
    .c3 = 0x3f,
    .xx = 0x00,
});

// TODO: make it usable with different data structures
pub fn validate(input: []const u8) bool {
    const mod = input.len % VLEN;

    var prefix: [VLEN]u8 = .{0} ** VLEN;
    for (VLEN - mod..VLEN) |i| {
        prefix[i] = input[i + mod - VLEN];
    }

    if (input.len == mod) {
        return simdValidateSlice(@splat(0), &prefix);
    } else {
        if (!simdValidatePair(@splat(0), prefix)) return false;

        return simdValidateSlice(prefix, input[mod..]);
    }
}

fn simdValidateSlice(prefix: Chunk, input: []const u8) bool {
    assert(input.len != 0);
    assert(input.len % VLEN == 0);

    var lookback: Chunk = prefix;
    var rest = input;
    while (rest.len > 0) {
        const chunk: Chunk = rest[0..VLEN].*;
        rest = rest[VLEN..];
        defer lookback = chunk;

        if (!simdValidatePair(lookback, chunk)) return false;
    }

    const end_mask: Chunk = .{0xff} ** (VLEN - 3) ++ .{0xf0} ++ .{0xe0} ++ .{0xc0};
    return @reduce(.And, lookback < end_mask);
}

fn simdValidatePair(lookback: Chunk, chunk: Chunk) bool {
    const shift = std.simd.mergeShift(lookback, chunk, VLEN - 1);

    const nibble_high = shift >> @splat(4);
    const nibble_low = shift & @as(Chunk, @splat(0xf));
    const nibble_next = chunk >> @splat(4);

    const flags_high = shuffle(std.simd.repeat(VLEN, lookup_high), nibble_high);
    const flags_low = shuffle(std.simd.repeat(VLEN, lookup_low), nibble_low);
    const flags_next = shuffle(std.simd.repeat(VLEN, lookup_next), nibble_next);

    const flags = flags_high & flags_low & flags_next;

    const continue_value: u8 = @bitCast(Flags{ .continuation = true });
    const continue_mask: Chunk = @splat(continue_value);

    if (@reduce(.Or, flags & ~continue_mask != @as(Chunk, @splat(0)))) return false;

    return @reduce(.And, continuationMask(lookback, chunk) == flags);
}

fn continuationMask(
    lookback: Chunk,
    chunk: Chunk,
) Chunk {
    const shift2 = std.simd.mergeShift(lookback, chunk, VLEN - 2);
    const mask2: Chunk = @splat(0xe0);

    const shift3 = std.simd.mergeShift(lookback, chunk, VLEN - 3);
    const mask3: Chunk = @splat(0xf0);

    const expect_continue = @as(Chunk, @intFromBool(shift2 >= mask2)) | @as(Chunk, @intFromBool(shift3 >= mask3));

    const continue_splat: Chunk = @splat(@bitCast(Flags{ .continuation = true }));
    return expect_continue * continue_splat;
}

/// https://github.com/ziglang/zig/issues/12815
fn shuffle(
    lookup: Chunk,
    mask: Chunk,
) Chunk {
    return switch (builtin.cpu.arch) {
        .x86_64 => mm_shuffle_epi8(lookup, mask),
        else => blk: {
            var result: [VLEN]u8 = undefined;
            comptime var vec_i = 0;
            inline while (vec_i < VLEN) : (vec_i += 1) {
                result[vec_i] = lookup[mask[vec_i]];
            }
            break :blk result;
        },
    };
}

/// https://github.com/ziglang/zig/issues/12815
/// https://ziggit.dev/t/simd-is-there-an-equivalent-to-mm-shuffle-ep/2251/7
inline fn mm_shuffle_epi8(
    x: Chunk,
    mask: Chunk,
) Chunk {
    return asm (
        \\vpshufb %[mask], %[x], %[out]
        : [out] "=x" (-> Chunk),
        : [x] "+x" (x),
          [mask] "x" (mask),
    );
}

/// Source: Validating UTF-8 In Less Than One Instruction Per Byte, Table 8
const Flags = packed struct(u8) {
    too_short: bool = false,
    too_long: bool = false,
    overlong_three: bool = false,
    too_large: bool = false,
    surrogate: bool = false,
    overlong_two: bool = false,
    overlong_four: bool = false,
    continuation: bool = false,
};

const lookup_high: @Vector(16, u8) = blk: {
    var t: [16]Flags = .{Flags{}} ** 16;

    for (0b0_000..0b0_111 + 1) |i| t[i].too_long = true;
    for (0b11_00..0b11_11 + 1) |i| t[i].too_short = true;
    t[0b1100].overlong_two = true;
    t[0b1110].surrogate = true;
    t[0b1110].overlong_three = true;
    t[0b1111].overlong_four = true;
    t[0b1111].too_large = true;
    for (0b10_00..0b10_11 + 1) |i| t[i].continuation = true;

    break :blk @bitCast(t);
};

const lookup_low: @Vector(16, u8) = blk: {
    var t: [16]Flags = .{Flags{}} ** 16;

    for (0b0000..0b1111 + 1) |i| t[i].too_long = true;
    for (0b0000..0b1111 + 1) |i| t[i].too_short = true;
    for (0b0000..0x0001 + 1) |i| t[i].overlong_two = true;
    t[0b1101].surrogate = true;
    t[0b0000].overlong_three = true;
    t[0b0000].overlong_four = true;
    for (0b0101..0b1111 + 1) |i| t[i].overlong_four = true;
    for (0b0100..0b1111 + 1) |i| t[i].too_large = true;
    for (0b0000..0b1111 + 1) |i| t[i].continuation = true;

    break :blk @bitCast(t);
};

const lookup_next: @Vector(16, u8) = blk: {
    var t: [16]Flags = .{Flags{}} ** 16;

    for (0b10_00..0b10_11 + 1) |i| t[i].too_long = true;
    for (0b0_000..0b0_111 + 1) |i| t[i].too_short = true;
    for (0b11_00..0b11_11 + 1) |i| t[i].too_short = true;
    for (0b10_00..0b10_11 + 1) |i| t[i].overlong_two = true;
    for (0b101_0..0b101_1 + 1) |i| t[i].surrogate = true;
    for (0b100_0..0b100_1 + 1) |i| t[i].overlong_three = true;
    t[0b1000].overlong_four = true;
    for (0b10_01..0b10_11 + 1) |i| t[i].too_large = true;
    for (0b10_00..0b10_11 + 1) |i| t[i].continuation = true;

    break :blk @bitCast(t);
};
