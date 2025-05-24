const std = @import("std");
const unicode = std.unicode;

const assert = std.debug.assert;

pub const ContextIterator = struct {
    context: *anyopaque,
    nextFn: *const fn (*anyopaque) anyerror!?Context,

    pub fn next(iter: ContextIterator) anyerror!?Context {
        return iter.nextFn(iter.context);
    }
};

pub const Context = struct {
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

    const lengths_table: [256]u3 align(32) = blk: {
        var table: [256]u3 = .{0} ** 256;

        // 0000 0000 - 0111 1111
        @memset(table[0x00..0x80], 1);
        // 1100 0000 - 1101 1111
        @memset(table[0xc0..0xe0], 2);
        // 1110 0000 - 1110 1111
        @memset(table[0xe0..0xf0], 3);
        // 1111 0000 - 1111 0111
        @memset(table[0xf0..0xf8], 4);

        break :blk table;
    };

    pub fn init(bytes: []const u8) !Utf8Decoder {
        if (!unicode.utf8ValidateSlice(bytes)) {
            return error.InvalidUtf8;
        }

        return .{ .bytes = bytes };
    }

    pub fn nextContext(utf8: *Utf8Decoder) ?Context {
        if (utf8.pos >= utf8.bytes.len) return null;

        var context: Context = .{
            .off = utf8.pos,
            .len = undefined,
            .code = undefined,
        };

        const first_byte = utf8.bytes[utf8.pos];
        utf8.pos += 1;
        switch (lengths_table[first_byte]) {
            inline 1...4 => |len| {
                const mask = switch (len) {
                    1 => 0xff,
                    2 => 0x1f,
                    3 => 0x0f,
                    4 => 0x07,
                    else => unreachable,
                };

                context.len = len;
                context.code = first_byte & mask;

                inline for (1..len) |_| {
                    context.code <<= 6;
                    context.code |= utf8.bytes[utf8.pos] & 0b0011_1111;
                    utf8.pos += 1;
                }

                return context;
            },
            else => unreachable,
        }

        unreachable;
    }

    pub fn nextCode(utf8: *Utf8Decoder) ?u21 {
        return if (utf8.nextContext()) |ctx| ctx.code else null;
    }

    pub fn contextIterator(utf8: *Utf8Decoder) ContextIterator {
        return .{ .context = utf8, .nextFn = typeErasedNextContext };
    }

    fn typeErasedNextContext(ptr: *anyopaque) error{}!?Context {
        const utf8: *Utf8Decoder = @alignCast(@ptrCast(ptr));
        return utf8.nextContext();
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

        pub fn nextContext(self: *Self) !?Context {
            if (self.start >= self.end) {
                self.base_offset += self.end;
                self.end = try self.unbuffered_reader.read(&self.buf);
                if (self.end == 0) return null;
                self.start = 0;
            }

            const len = try unicode.utf8ByteSequenceLength(self.buf[self.start]);
            const available = self.end - self.start;
            var codepoint: Context = .{
                .off = self.base_offset + self.start,
                .len = len,
                .code = undefined,
            };

            if (available >= len) {
                const slice = self.buf[self.start..][0..len];
                self.start += len;

                codepoint.code = try unicode.utf8Decode(slice);
            } else {
                var buf: [4]u8 = undefined;
                @memcpy(buf[0..available], self.buf[self.start..self.end]);

                self.base_offset += self.end;
                self.end = try self.unbuffered_reader.read(&self.buf);
                self.start = len - available;

                if (self.end < self.start) return error.Utf8ExpectedContinuation;
                @memcpy(buf[available..len], self.buf[0..self.start]);

                const slice = buf[0..len];
                codepoint.code = try unicode.utf8Decode(slice);
            }

            return codepoint;
        }

        pub fn nextCode(self: *@This()) !?u21 {
            return if (try self.nextContext()) |ctx| ctx.code else null;
        }

        pub fn contextIterator(self: *@This()) ContextIterator {
            return .{ .context = self, .nextFn = typeErasedNextContext };
        }

        fn typeErasedNextContext(ptr: *anyopaque) !?Context {
            const self: *@This() = @alignCast(@ptrCast(ptr));
            return self.nextContext();
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
