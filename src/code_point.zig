const std = @import("std");
const unicode = std.unicode;

const assert = std.debug.assert;

pub const FatIterator = struct {
    context: *anyopaque,
    nextFn: *const fn (*anyopaque) anyerror!?Fat,

    pub fn next(iter: FatIterator) anyerror!?Fat {
        return iter.nextFn(iter.context);
    }
};

pub const Fat = struct {
    code: u21,
    off: usize,
    len: u3,
};

pub const CodeIterator = struct {
    context: *anyopaque,
    nextFn: *const fn (*anyopaque) anyerror!?u21,

    pub fn next(iter: CodeIterator) anyerror!?u21 {
        return iter.nextFn(iter.context);
    }
};

pub const Utf8Decoder = struct {
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

    pub fn init(bytes: []const u8) !Utf8Decoder {
        if (!unicode.utf8ValidateSlice(bytes)) {
            return error.InvalidUtf8;
        }

        return .{ .bytes = bytes };
    }

    pub fn nextFat(utf8: *Utf8Decoder) ?Fat {
        if (utf8.pos >= utf8.bytes.len) return null;

        const first_byte = utf8.bytes[utf8.pos];
        utf8.pos += 1;

        if (first_byte < 0x80) return .{
            .off = utf8.pos - 1,
            .len = 1,
            .code = first_byte,
        };

        var fat: Fat = .{
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

    pub fn nextCode(utf8: *Utf8Decoder) ?u21 {
        return if (utf8.nextFat()) |ctx| ctx.code else null;
    }

    pub fn fatIterator(utf8: *Utf8Decoder) FatIterator {
        return .{ .context = utf8, .nextFn = typeErasedNextFat };
    }

    fn typeErasedNextFat(ptr: *anyopaque) error{}!?Fat {
        const utf8: *Utf8Decoder = @alignCast(@ptrCast(ptr));
        return utf8.nextFat();
    }

    pub fn codeIterator(utf8: *Utf8Decoder) CodeIterator {
        return .{ .context = utf8, .nextFn = typeErasedNextCode };
    }

    fn typeErasedNextCode(ptr: *anyopaque) error{}!?u21 {
        const utf8: *Utf8Decoder = @alignCast(@ptrCast(ptr));
        return utf8.nextCode();
    }
};

test "Utf8Decoder" {
    const string = "ábç 퀀 😀";
    var decoder: Utf8Decoder = try .init(string);

    const view = try unicode.Utf8View.init(string);
    var iter = view.iterator();

    while (iter.nextCodepoint()) |expected| {
        try std.testing.expectEqual(expected, try decoder.codeIterator().next());
    }
    try std.testing.expectEqual(null, try decoder.codeIterator().next());
}

pub const Utf8Encoder = struct {
    source: CodeIterator,
    buffer: std.BoundedArray(u8, 4) = .{},

    pub const Reader = std.io.Reader(*Utf8Encoder, anyerror, read);

    pub fn read(encoder: *Utf8Encoder, dest: []u8) !usize {
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

    pub fn reader(encoder: *Utf8Encoder) Reader {
        return .{ .context = encoder };
    }

    pub fn pump(encoder: Utf8Encoder, writer: anytype) !void {
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

test "Utf8Encoder.pump" {
    const string = "ábç 퀀 😀";
    var decoder: Utf8Decoder = try .init(string);
    var encoder: Utf8Encoder = .{ .source = decoder.codeIterator() };

    var output: std.ArrayList(u8) = .init(std.testing.allocator);
    defer output.deinit();

    try encoder.pump(output.writer());
    try std.testing.expectEqualStrings(string, output.items);
}

test "Utf8Encoder.reader" {
    const string = "ábç 퀀 😀";
    var decoder: Utf8Decoder = try .init(string);
    var encoder: Utf8Encoder = .{ .source = decoder.codeIterator() };

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
        pub fn nextFat(self: *Self) !?Fat {
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

        pub fn fatIterator(self: *@This()) FatIterator {
            return .{ .context = self, .nextFn = typeErasedNextFat };
        }

        fn typeErasedNextFat(ptr: *anyopaque) !?Fat {
            const self: *@This() = @alignCast(@ptrCast(ptr));
            return self.nextFat();
        }

        pub fn codeIterator(self: *@This()) CodeIterator {
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
