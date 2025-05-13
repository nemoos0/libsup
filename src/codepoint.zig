const std = @import("std");
const unicode = std.unicode;

const assert = std.debug.assert;

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

pub const Utf8Unchecked = struct {
    bytes: []const u8,
    pos: usize = 0,

    pub fn next(utf8: *Utf8Unchecked) ?Codepoint {
        if (utf8.pos >= utf8.bytes.len) return null;

        const first_byte = utf8.bytes[utf8.pos];
        const len = unicode.utf8ByteSequenceLength(first_byte) catch unreachable;
        var codepoint: Codepoint = .{
            .offset = utf8.pos,
            .len = len,
            .code = undefined,
        };

        utf8.pos += 1;
        switch (len) {
            1 => codepoint.code = first_byte,
            2 => {
                codepoint.code = first_byte & 0b0001_1111;
                codepoint.code <<= 6;
                codepoint.code |= utf8.bytes[utf8.pos] & 0b0011_1111;
                utf8.pos += 1;
            },
            3 => {
                codepoint.code = first_byte & 0b0000_1111;
                inline for (0..2) |_| {
                    codepoint.code <<= 6;
                    codepoint.code |= utf8.bytes[utf8.pos] & 0b0011_1111;
                    utf8.pos += 1;
                }
            },
            4 => {
                codepoint.code = first_byte & 0b0000_0111;
                inline for (0..3) |_| {
                    codepoint.code <<= 6;
                    codepoint.code |= utf8.bytes[utf8.pos] & 0b0011_1111;
                    utf8.pos += 1;
                }
            },
            else => unreachable,
        }

        return codepoint;
    }

    pub fn iterator(utf8: *Utf8Unchecked) Iterator {
        return .{ .context = utf8, .nextFn = typeErasedNextFn };
    }

    fn typeErasedNextFn(context: *anyopaque) anyerror!?Codepoint {
        const utf8: *@This() = @alignCast(@ptrCast(context));
        return utf8.next();
    }
};

pub const Utf8 = struct {
    bytes: []const u8,
    pos: usize = 0,

    pub fn next(utf8: *Utf8) !?Codepoint {
        if (utf8.pos >= utf8.bytes.len) return null;

        const first_byte = utf8.bytes[utf8.pos];
        const len = try unicode.utf8ByteSequenceLength(first_byte);
        const code = try unicode.utf8Decode(utf8.bytes[utf8.pos..][0..len]);

        defer utf8.pos += len;
        return .{ .offset = utf8.pos, .len = len, .code = code };
    }

    pub fn iterator(utf8: *Utf8) Iterator {
        return .{ .context = utf8, .nextFn = typeErasedNextFn };
    }

    fn typeErasedNextFn(context: *anyopaque) anyerror!?Codepoint {
        const utf8: *@This() = @alignCast(@ptrCast(context));
        return utf8.next();
    }
};

pub fn bufferedReader(reader: anytype) BufferedReader(4096, @TypeOf(reader)) {
    return .{ .unbuffered_reader = reader };
}

pub fn BufferedReader(comptime buffer_size: usize, comptime ReaderType: type) type {
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

    var utf8_unchecked: Utf8Unchecked = .{ .bytes = buf };
    var utf8: Utf8 = .{ .bytes = buf };

    var stream = std.io.fixedBufferStream(buf);
    var buffered_reader = bufferedReader(stream.reader());

    var offset: usize = 0;
    const view: unicode.Utf8View = .initUnchecked(buf);
    var iter = view.iterator();
    while (iter.nextCodepoint()) |code| {
        const len = unicode.utf8CodepointSequenceLength(code) catch unreachable;
        const expected: Codepoint = .{ .offset = offset, .len = len, .code = code };
        offset += len;

        try std.testing.expectEqualDeep(expected, try utf8_unchecked.iterator().next());
        try std.testing.expectEqualDeep(expected, try utf8.iterator().next());
        try std.testing.expectEqualDeep(expected, try buffered_reader.iterator().next());
    }
}
