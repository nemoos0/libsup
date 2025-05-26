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

    pub fn nextContext(utf8: *Utf8Decoder) ?Context {
        if (utf8.pos >= utf8.bytes.len) return null;

        const first_byte = utf8.bytes[utf8.pos];
        utf8.pos += 1;

        if (first_byte < 0x80) return .{
            .off = utf8.pos - 1,
            .len = 1,
            .code = first_byte,
        };

        var context: Context = .{
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

                context.len = len;
                context.code = first_byte & mask;

                inline for (1..len) |_| {
                    context.code = (utf8.bytes[utf8.pos] & 0x3f) | (context.code << 6);
                    utf8.pos += 1;
                }

                return context;
            },
            else => unreachable,
        }
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

        /// https://bjoern.hoehrmann.de/utf-8/decoder/dfa
        pub fn nextContext(self: *Self) !?Context {
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
            var state = transitions.get(.valid).get(class);

            if (state == .invalid) return error.Utf8InvalidStartByte;
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

            if (state == .valid) return .{ .off = off, .len = 2, .code = code };
            if (state == .invalid) return error.Utf8ExpectedContinuation;
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

            if (state == .valid) return .{ .off = off, .len = 3, .code = code };
            if (state == .invalid) return error.InvalidUtf8;
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

            if (state == .invalid) return error.InvalidUtf8;
            assert(state == .valid);
            return .{ .off = off, .len = 4, .code = code };
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

const Class = enum(u4) {
    /// 0x00 - 0x7f
    ascii,

    /// 0x80 - 0x8f
    extention_low,
    /// 0x90 - 0x9f
    extention_mid,
    /// 0xa0 - 0xbf
    extention_high,

    /// 0xc0 - 0xc1 | 0xf5 - 0xff
    invalid,

    /// 0xc2 - 0xdf
    two_byte,

    /// 0xe0
    three_byte_overlong,
    /// 0xe1 - 0xec | 0xee - 0xef
    three_byte,
    /// 0xed
    three_byte_surrogate,

    /// 0xf0
    four_byte_overlong,
    /// 0xf1 - 0xf3
    four_byte,
    /// 0xf4
    four_byte_too_large,
};

const State = enum(u4) {
    valid,
    invalid,

    one_more,
    two_more,
    three_more,

    three_byte_overlong,
    three_byte_surrogate,

    four_byte_overlong,
    four_byte_too_large,
};

const classes: [256]Class = blk: {
    var c: [256]Class = .{.invalid} ** 256;

    @memset(c[0x00..0x80], .ascii);

    @memset(c[0x80..0x90], .extention_low);
    @memset(c[0x90..0xa0], .extention_mid);
    @memset(c[0xa0..0xc0], .extention_high);

    @memset(c[0xc0..0xc2], .invalid);
    @memset(c[0xc2..0xe0], .two_byte);

    c[0xe0] = .three_byte_overlong;
    @memset(c[0xe1..0xed], .three_byte);
    c[0xed] = .three_byte_surrogate;
    @memset(c[0xee..0xf0], .three_byte);

    c[0xf0] = .four_byte_overlong;
    @memset(c[0xf1..0xf4], .four_byte);
    c[0xf4] = .four_byte_too_large;

    @memset(c[0xf5..], .invalid);

    break :blk c;
};

const masks: std.EnumArray(Class, u8) = .init(.{
    .ascii = 0xff,

    .extention_low = 0x3f,
    .extention_mid = 0x3f,
    .extention_high = 0x3f,

    .invalid = 0x00,

    .two_byte = 0x1f,

    .three_byte_overlong = 0x0f,
    .three_byte = 0x0f,
    .three_byte_surrogate = 0x0f,

    .four_byte_overlong = 0x07,
    .four_byte = 0x07,
    .four_byte_too_large = 0x07,
});

const transitions: std.EnumArray(State, std.EnumArray(Class, State)) = blk: {
    var t: std.EnumArray(State, std.EnumArray(Class, State)) = .initFill(.initFill(.invalid));

    t.getPtr(.valid).set(.ascii, State.valid);

    t.getPtr(.valid).set(.two_byte, State.one_more);

    t.getPtr(.valid).set(.three_byte, State.two_more);
    t.getPtr(.valid).set(.three_byte_overlong, State.three_byte_overlong);
    t.getPtr(.valid).set(.three_byte_surrogate, State.three_byte_surrogate);

    t.getPtr(.valid).set(.four_byte, State.three_more);
    t.getPtr(.valid).set(.four_byte_overlong, State.four_byte_overlong);
    t.getPtr(.valid).set(.four_byte_too_large, State.four_byte_too_large);

    t.getPtr(.one_more).set(.extention_low, State.valid);
    t.getPtr(.one_more).set(.extention_mid, State.valid);
    t.getPtr(.one_more).set(.extention_high, State.valid);

    t.getPtr(.two_more).set(.extention_low, State.one_more);
    t.getPtr(.two_more).set(.extention_mid, State.one_more);
    t.getPtr(.two_more).set(.extention_high, State.one_more);

    t.getPtr(.three_more).set(.extention_low, State.two_more);
    t.getPtr(.three_more).set(.extention_mid, State.two_more);
    t.getPtr(.three_more).set(.extention_high, State.two_more);

    t.getPtr(.three_byte_overlong).set(.extention_high, State.one_more);

    t.getPtr(.three_byte_surrogate).set(.extention_low, State.one_more);
    t.getPtr(.three_byte_surrogate).set(.extention_mid, State.one_more);

    t.getPtr(.four_byte_overlong).set(.extention_mid, State.two_more);
    t.getPtr(.four_byte_overlong).set(.extention_high, State.two_more);

    t.getPtr(.four_byte_too_large).set(.extention_low, State.two_more);

    break :blk t;
};
