const std = @import("std");

test "fuzz" {
    const Context = struct {
        pub fn testOne(_: @This(), input: []const u8) !void {
            if (std.unicode.utf8ValidateSlice(input) != validateUtf8(input)) {
                return error.InvalidSlice;
            }
        }
    };

    try std.testing.fuzz(Context{}, Context.testOne, .{});
}

pub fn main() !void {
    const gpa = std.heap.smp_allocator;

    const stdin = std.io.getStdIn();
    const input = try stdin.readToEndAlloc(gpa, std.math.maxInt(usize));
    defer gpa.free(input);

    for (0..input.len) |len| {
        if (std.unicode.utf8ValidateSlice(input[0..len]) != validateUtf8(input[0..len])) {
            std.debug.print("{}\n", .{len});
            return error.InvalidSlice;
        }
    }
}

/// Source: Validating UTF-8 In Less Than One Instruction Per Byte (2021) Keiser, J. & Lemire, D.
/// TODO: implement some fuzz testing on this function
pub fn validateUtf8(slice: []const u8) bool {
    var rest = slice;
    const len = 64;
    const Chunk = @Vector(len, u8);

    var lookback: Chunk = @splat(0);
    while (rest.len > 0) {
        const chunk: Chunk = blk: {
            if (rest.len >= len) {
                defer rest = rest[len..];
                break :blk rest[0..len].*;
            } else {
                defer rest = rest[0..0];
                var chunk: Chunk = @splat(0);
                for (0..rest.len) |i| chunk[i] = rest[i];
                break :blk chunk;
            }
        };
        defer lookback = chunk;

        const shift = std.simd.mergeShift(lookback, chunk, len - 1);

        const nibble_high = shift >> @splat(4);
        const nibble_low = shift & @as(Chunk, @splat(0xf));
        const nibble_next = chunk >> @splat(4);

        const lookup_high_padded: Chunk = std.simd.repeat(len, lookup_high);
        // BUG: this function is for x86_64 only
        const flags_high = mm_shuffle_epi8(len, lookup_high_padded, nibble_high);

        const lookup_low_padded: Chunk = std.simd.repeat(len, lookup_low);
        // BUG: this function is for x86_64 only
        const flags_low = mm_shuffle_epi8(len, lookup_low_padded, nibble_low);

        const lookup_next_padded: Chunk = std.simd.repeat(len, lookup_next);
        // BUG: this function is for x86_64 only
        const flags_next = mm_shuffle_epi8(len, lookup_next_padded, nibble_next);

        const flags = flags_high & flags_low & flags_next;

        // std.debug.print("{x: >8}\n", .{lookback});
        // std.debug.print("{x: >8}\n", .{chunk});
        // std.debug.print("{x: >8}\n", .{shift});
        // std.debug.print("{x: >8}\n", .{nibble_high});
        // std.debug.print("{x: >8}\n", .{nibble_low});
        // std.debug.print("{x: >8}\n", .{nibble_next});
        // std.debug.print("{b:0>8}\n", .{flags_high});
        // std.debug.print("{b:0>8}\n", .{flags_low});
        // std.debug.print("{b:0>8}\n", .{flags_next});
        // std.debug.print("{b:0>8}\n", .{flags});

        const continue_mask: Chunk = @splat(@as(u8, @bitCast(Invalid2Byte{ .continuation = true })));

        if (@reduce(.Or, flags & ~continue_mask != @as(Chunk, @splat(0)))) return false;

        const expected_continue: Chunk = checkContinuation(len, lookback, chunk);
        const exected_flags = expected_continue * continue_mask;

        if (@reduce(.Or, exected_flags != flags)) return false;
    }

    const end_mask: Chunk = .{0xff} ** (len - 3) ++ .{0xf0} ++ .{0xe0} ++ .{0xc0};
    const tail = blk: {
        if (slice.len >= len) {
            break :blk slice[slice.len - len ..][0..len].*;
        } else {
            var buf: [len]u8 = .{0} ** len;
            @memcpy(buf[len - slice.len ..], slice);
            break :blk buf;
        }
    };

    return @reduce(.And, tail < end_mask);
}

/// https://github.com/ziglang/zig/issues/12815
/// https://ziggit.dev/t/simd-is-there-an-equivalent-to-mm-shuffle-ep/2251/7
pub fn mm_shuffle_epi8(
    comptime len: comptime_int,
    x: @Vector(len, u8),
    mask: @Vector(len, u8),
) @Vector(len, u8) {
    return asm (
        \\vpshufb %[mask], %[x], %[out]
        : [out] "=x" (-> @Vector(len, u8)),
        : [x] "+x" (x),
          [mask] "x" (mask),
    );
}

fn checkContinuation(
    comptime len: comptime_int,
    lookback: @Vector(len, u8),
    chunk: @Vector(len, u8),
) @Vector(len, u8) {
    const Chunk = @Vector(len, u8);

    const shift2 = std.simd.mergeShift(lookback, chunk, len - 2);
    const mask2: Chunk = @splat(0xe0);

    const shift3 = std.simd.mergeShift(lookback, chunk, len - 3);
    const mask3: Chunk = @splat(0xf0);

    // std.debug.print("{x: >8}\n", .{shift2});
    // std.debug.print("{x: >8}\n", .{shift3});

    return @as(Chunk, @intFromBool(shift2 >= mask2)) | @as(Chunk, @intFromBool(shift3 >= mask3));
}

const Flags = @Vector(16, u8);

const Invalid2Byte = packed struct(u8) {
    too_short: bool = false,
    too_long: bool = false,
    overlong_three: bool = false,
    too_large: bool = false,
    surrogate: bool = false,
    overlong_two: bool = false,
    overlong_four: bool = false,
    continuation: bool = false,
};

const lookup_high: Flags = .{@as(u8, @bitCast(Invalid2Byte{ .too_long = true }))} ** 8 ++
    .{@as(u8, @bitCast(Invalid2Byte{ .continuation = true }))} ** 4 ++
    .{@as(u8, @bitCast(Invalid2Byte{ .too_short = true, .overlong_two = true }))} ++ // 1100
    .{@as(u8, @bitCast(Invalid2Byte{ .too_short = true }))} ++ // 1101
    .{@as(u8, @bitCast(Invalid2Byte{ .too_short = true, .surrogate = true, .overlong_three = true }))} ++ // 1110
    .{@as(u8, @bitCast(Invalid2Byte{ .too_short = true, .overlong_four = true, .too_large = true }))}; // 1111

const lookup_low: Flags = blk: {
    var t: [16]Invalid2Byte = .{Invalid2Byte{}} ** 16;

    for (0..16) |i| t[i].too_long = true;
    for (0..16) |i| t[i].too_short = true;
    for (0..2) |i| t[i].overlong_two = true;
    t[13].surrogate = true;
    t[0].overlong_three = true;
    t[0].overlong_four = true;
    for (5..16) |i| t[i].overlong_four = true;
    for (4..16) |i| t[i].too_large = true;
    for (0..16) |i| t[i].continuation = true;

    break :blk @bitCast(t);
};

const lookup_next: Flags = blk: {
    var t: [16]Invalid2Byte = .{Invalid2Byte{}} ** 16;

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
