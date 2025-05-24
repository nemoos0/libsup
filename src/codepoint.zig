const std = @import("std");
const unicode = std.unicode;

const assert = std.debug.assert;

const Iterator2 = struct {
    context: *anyopaque,
    nextFn: *const fn (*anyopaque) anyerror!?u21,
};

const IteratorWithContext = struct {
    context: *anyopaque,
    nextFn: *const fn (*anyopaque) anyerror!?Context,
};

pub const Context = struct {
    offset: usize,
    code: u21,
    len: u3,
};

pub const Codepoint = struct {
    offset: usize,
    code: u21,
    len: u3,
};

pub const Iterator = struct {
    context: *anyopaque,
    nextFn: *const fn (*anyopaque) anyerror!?Codepoint,

    pub fn next(iter: Iterator) anyerror!?Codepoint {
        return iter.nextFn(iter.context);
    }
};

pub const Utf8 = struct {
    bytes: []const u8,
    pos: usize = 0,

    pub fn init(bytes: []const u8) !Utf8 {
        if (!std.unicode.utf8ValidateSlice(bytes)) {
            return error.InvalidUtf8;
        }

        return .{ .bytes = bytes };
    }

    pub fn next(utf8: *Utf8) ?Codepoint {
        if (utf8.pos >= utf8.bytes.len) return null;

        var codepoint: Codepoint = .{
            .offset = utf8.pos,
            .len = undefined,
            .code = undefined,
        };

        const first_byte = utf8.bytes[utf8.pos];
        utf8.pos += 1;
        switch (first_byte) {
            0b0000_0000...0b0111_1111 => {
                codepoint.len = 1;
                codepoint.code = first_byte;
                return codepoint;
            },
            0b1100_0000...0b1101_1111 => {
                codepoint.len = 2;

                codepoint.code = first_byte & 0b0001_1111;
                codepoint.code <<= 6;
                codepoint.code |= utf8.bytes[utf8.pos] & 0b0011_1111;
                utf8.pos += 1;

                return codepoint;
            },
            0b1110_0000...0b1110_1111 => {
                codepoint.len = 3;

                codepoint.code = first_byte & 0b0000_1111;
                inline for (0..2) |_| {
                    codepoint.code <<= 6;
                    codepoint.code |= utf8.bytes[utf8.pos] & 0b0011_1111;
                    utf8.pos += 1;
                }

                return codepoint;
            },
            0b1111_0000...0b1111_0111 => {
                codepoint.len = 4;

                codepoint.code = first_byte & 0b0000_0111;
                inline for (0..3) |_| {
                    codepoint.code <<= 6;
                    codepoint.code |= utf8.bytes[utf8.pos] & 0b0011_1111;
                    utf8.pos += 1;
                }

                return codepoint;
            },
            else => unreachable,
        }

        unreachable;
    }

    pub fn iterator(utf8: *Utf8) Iterator {
        return .{ .context = utf8, .nextFn = typeErasedNextFn };
    }

    fn typeErasedNextFn(context: *anyopaque) anyerror!?Codepoint {
        const utf8: *@This() = @alignCast(@ptrCast(context));
        return utf8.next();
    }
};

pub fn fromReader(reader: anytype) FromReader(4096, @TypeOf(reader)) {
    return .{ .unbuffered_reader = reader };
}

pub fn FromReader(comptime buffer_size: usize, comptime ReaderType: type) type {
    assert(buffer_size >= 4);

    return struct {
        unbuffered_reader: ReaderType,
        buf: [buffer_size]u8 = undefined,
        base_offset: usize = 0,
        start: usize = 0,
        end: usize = 0,

        const Self = @This();

        pub fn next(self: *Self) !?Codepoint {
            if (self.start >= self.end) {
                self.base_offset += self.end;
                self.end = try self.unbuffered_reader.read(&self.buf);
                if (self.end == 0) return null;
                self.start = 0;
            }

            const len = try unicode.utf8ByteSequenceLength(self.buf[self.start]);
            const available = self.end - self.start;
            var codepoint: Codepoint = .{
                .offset = self.base_offset + self.start,
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

        pub fn iterator(self: *Self) Iterator {
            return .{ .context = self, .nextFn = typeErasedNextFn };
        }

        fn typeErasedNextFn(context: *anyopaque) anyerror!?Codepoint {
            const self: *@This() = @alignCast(@ptrCast(context));
            return self.next();
        }
    };
}

test "iterators" {
    const gpa = std.testing.allocator;

    const buf: []const u8 = blk: {
        var list: std.ArrayList(u8) = .init(gpa);

        for (0..0x110000) |i| {
            const code: u21 = @intCast(i);
            if (std.unicode.utf8ValidCodepoint(code)) {
                try list.ensureUnusedCapacity(4);
                list.items.len += std.unicode.utf8Encode(
                    code,
                    list.unusedCapacitySlice(),
                ) catch unreachable;
            }
        }

        break :blk try list.toOwnedSlice();
    };
    defer gpa.free(buf);

    var utf8: Utf8 = try .init(buf);

    var stream = std.io.fixedBufferStream(buf);
    var buffered_reader = fromReader(stream.reader());

    var offset: usize = 0;
    const view: unicode.Utf8View = .initUnchecked(buf);
    var iter = view.iterator();
    while (iter.nextCodepoint()) |code| {
        const len = unicode.utf8CodepointSequenceLength(code) catch unreachable;
        const expected: Codepoint = .{ .offset = offset, .len = len, .code = code };
        offset += len;

        try std.testing.expectEqualDeep(expected, try utf8.iterator().next());
        try std.testing.expectEqualDeep(expected, try buffered_reader.iterator().next());
    }
}
