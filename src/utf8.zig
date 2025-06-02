const std = @import("std");
const builtin = @import("builtin");

const assert = std.debug.assert;

const VLEN = std.simd.suggestVectorLength(u8) orelse 1;
const Chunk = @Vector(VLEN, u8);

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
