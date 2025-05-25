const std = @import("std");
const enc = @import("encodings");

const qc_table = @import("quick_check_table");
const ccc_table = @import("combining_class_table");
const decomp_table = @import("decomposition_table");
const comp_table = @import("composition_table");

const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

pub const Form = packed struct(u2) {
    composed: bool,
    canonical: bool,

    pub const nfc: Form = .{ .composed = true, .canonical = true };
    pub const nfd: Form = .{ .composed = false, .canonical = true };
    pub const nfkc: Form = .{ .composed = true, .canonical = false };
    pub const nfkd: Form = .{ .composed = false, .canonical = false };
};

pub fn Normalizer(comptime form: Form) type {
    return struct {
        gpa: Allocator,
        source: enc.CodeIterator,
        codes: ArrayListUnmanaged(u21),
        classes: ArrayListUnmanaged(u8),
        /// Number of codes already sorted
        starter: usize = 0,
        /// Number of codes already returned
        returned: usize = 0,

        const Self = @This();

        const SortContext = struct {
            codes: []u21,
            classes: []u8,

            pub fn lessThan(ctx: SortContext, a: usize, b: usize) bool {
                return ctx.classes[a] < ctx.classes[b];
            }

            pub fn swap(ctx: SortContext, a: usize, b: usize) void {
                std.mem.swap(u21, &ctx.codes[a], &ctx.codes[b]);
                std.mem.swap(u8, &ctx.classes[a], &ctx.classes[b]);
            }
        };

        /// If you want to avoid heap allocations you can pass a
        /// `FixedBufferAllocator` of size 256 bytes which is enough
        /// "for all practical purposes". This assumes Stream-Safe Text Format
        /// and will return an `error.OutOfMemory` otherwise.
        ///
        /// UAX #15 section 13 Stream-Safe Text Format
        /// https://www.unicode.org/reports/tr15/#UAX15-D3
        pub fn init(gpa: Allocator, source: enc.CodeIterator) Allocator.Error!Self {
            return .{
                .gpa = gpa,
                .source = source,
                .codes = try .initCapacity(gpa, 32),
                .classes = try .initCapacity(gpa, 32),
            };
        }

        pub fn deinit(norm: *Self) void {
            norm.codes.deinit(norm.gpa);
            norm.classes.deinit(norm.gpa);
        }

        pub fn next(norm: *Self) !?u21 {
            if (norm.returned < norm.starter) {
                defer norm.returned += 1;
                return norm.codes.items[norm.returned];
            }

            norm.codes.replaceRangeAssumeCapacity(0, norm.starter, &.{});
            norm.classes.replaceRangeAssumeCapacity(0, norm.starter, &.{});

            while (true) {
                if (try norm.indexOfSecondStarter()) |index| {
                    norm.starter = index;
                } else if (norm.codes.items.len != 0) {
                    norm.starter = norm.codes.items.len;
                } else {
                    return null;
                }

                std.mem.sortContext(0, norm.starter, SortContext{
                    .codes = norm.codes.items,
                    .classes = norm.classes.items,
                });

                if (comptime form.composed) {
                    if (norm.composeSorted()) break;
                } else break;
            }

            norm.returned = 1;
            return norm.codes.items[0];
        }

        pub fn iterator(norm: *Self) enc.CodeIterator {
            return .{ .context = norm, .nextFn = typeErasedNext };
        }

        fn typeErasedNext(ptr: *anyopaque) !?u21 {
            const norm: *Self = @alignCast(@ptrCast(ptr));
            return norm.next();
        }

        fn indexOfSecondStarter(norm: *Self) !?usize {
            var index: ?usize = std.mem.indexOfScalarPos(u8, norm.classes.items, 1, 0);

            while (index == null) {
                if (try norm.source.next()) |code| {
                    const pos = norm.codes.items.len;
                    try norm.appendCodeDecomposition(code);
                    index = std.mem.indexOfScalarPos(u8, norm.classes.items, @max(1, pos), 0);
                } else {
                    return null;
                }
            }

            return index.?;
        }

        fn appendCodeDecomposition(norm: *Self, original: u21) !void {
            const len = blk: {
                if (comptime form.canonical) {
                    try norm.codes.ensureUnusedCapacity(norm.gpa, 4);
                    break :blk fullCanonicalDecomposition(original, norm.codes.unusedCapacitySlice());
                } else {
                    try norm.codes.ensureUnusedCapacity(norm.gpa, 18);
                    break :blk fullCompatibilityDecomposition(original, norm.codes.unusedCapacitySlice());
                }
            };

            try norm.classes.ensureUnusedCapacity(norm.gpa, len);
            for (
                norm.codes.unusedCapacitySlice()[0..len],
                norm.classes.unusedCapacitySlice()[0..len],
            ) |code, *class| {
                class.* = combiningClass(code);
            }

            norm.codes.items.len += len;
            norm.classes.items.len += len;
        }

        /// Compose the codepoints up to `norm.sorted`.
        /// Returns `true` if there is no further potential composition.
        fn composeSorted(norm: *Self) bool {
            if (norm.classes.items[0] == 0) {
                var max_class: u8 = 0;

                var i: usize = 1;
                while (i < norm.starter) {
                    std.debug.assert(norm.classes.items[i] >= max_class);
                    if (norm.classes.items[i] == max_class) {
                        i += 1;
                        continue;
                    }

                    const right = norm.codes.items[i];
                    if (composition(norm.codes.items[0], right)) |code| {
                        _ = norm.codes.orderedRemove(i);
                        _ = norm.classes.orderedRemove(i);

                        norm.codes.items[0] = code;
                        norm.starter -= 1;
                    } else {
                        max_class = norm.classes.items[i];
                        i += 1;
                    }
                }

                if (norm.starter == 1 and norm.codes.items.len > 1) {
                    if (composition(
                        norm.codes.items[0],
                        norm.codes.items[norm.starter],
                    )) |code| {
                        _ = norm.codes.orderedRemove(norm.starter);
                        _ = norm.classes.orderedRemove(norm.starter);

                        norm.codes.items[0] = code;
                        norm.starter -= 1;

                        return false;
                    }
                }
            }

            return true;
        }
    };
}

test "conformance" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const file = try std.fs.cwd().openFile("data/NormalizationTest.txt", .{});
    defer file.close();
    const reader = file.reader();

    while (try reader.readUntilDelimiterOrEofAlloc(arena, '\n', 4096)) |line| : (_ = arena_state.reset(.retain_capacity)) {
        const content = line[0 .. std.mem.indexOfAny(u8, line, "#@") orelse line.len];
        if (content.len == 0) continue;

        var string: std.ArrayListUnmanaged(u8) = .empty;
        var nfc: std.ArrayListUnmanaged(u8) = .empty;
        var nfd: std.ArrayListUnmanaged(u8) = .empty;
        var nfkc: std.ArrayListUnmanaged(u8) = .empty;
        var nfkd: std.ArrayListUnmanaged(u8) = .empty;

        var columns = std.mem.splitScalar(u8, content, ';');
        for ([_]*std.ArrayListUnmanaged(u8){ &string, &nfc, &nfd, &nfkc, &nfkd }) |list| {
            const trimmed = std.mem.trim(u8, columns.next().?, &std.ascii.whitespace);
            var codes = std.mem.splitScalar(u8, trimmed, ' ');

            while (codes.next()) |slice| {
                const code = try std.fmt.parseInt(u21, slice, 16);
                try list.ensureUnusedCapacity(arena, 4);
                list.items.len += try std.unicode.utf8Encode(code, list.unusedCapacitySlice());
            }
        }

        try expectEqualForms(string.items, nfc.items, nfd.items, nfkc.items, nfkd.items);
        try expectEqualForms(nfc.items, nfc.items, nfd.items, nfkc.items, nfkd.items);
        try expectEqualForms(nfd.items, nfc.items, nfd.items, nfkc.items, nfkd.items);
        try expectEqualForms(nfkc.items, nfkc.items, nfkd.items, nfkc.items, nfkd.items);
        try expectEqualForms(nfkd.items, nfkc.items, nfkd.items, nfkc.items, nfkd.items);
    }
}

fn expectEqualForms(
    original: []const u8,
    nfc: []const u8,
    nfd: []const u8,
    nfkc: []const u8,
    nfkd: []const u8,
) !void {
    try expectEqualForm(original, nfc, .nfc);
    try expectEqualForm(original, nfd, .nfd);
    try expectEqualForm(original, nfkc, .nfkc);
    try expectEqualForm(original, nfkd, .nfkd);
}

fn expectEqualForm(
    original: []const u8,
    expected: []const u8,
    comptime form: Form,
) !void {
    var buffer: [256]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buffer);

    var original_utf8: enc.Utf8Decoder = .{ .bytes = original };
    var norm: Normalizer(form) = try .init(
        fba.allocator(),
        original_utf8.codeIterator(),
    );

    var expected_utf8: enc.Utf8Decoder = .{ .bytes = expected };

    while (expected_utf8.nextCode()) |expected_code| {
        const actual_code = try norm.next();
        try std.testing.expectEqual(expected_code, actual_code.?);
    }
    try std.testing.expectEqual(null, try norm.next());
}

pub const CompatibilityTag = decomp_table.CompatibilityTag;

pub fn compatibilityTag(code: u21) CompatibilityTag {
    std.debug.assert(code < 0x110000);

    const high_bits = code / decomp_table.bs;
    const low_bits = code % decomp_table.bs;

    const idx: u32 = @as(u32, @intCast(decomp_table.s1[high_bits])) * decomp_table.bs + low_bits;
    return decomp_table.s2_tag[idx];
}

pub fn canonicalDecomposition(code: u21) ?[]const u21 {
    std.debug.assert(code < 0x110000);

    if (code >= s_base and code < s_base + s_count) {
        return hangulDecomposition(code);
    }

    const high_bits = code / decomp_table.bs;
    const low_bits = code % decomp_table.bs;

    const idx: u32 = @as(u32, @intCast(decomp_table.s1[high_bits])) * decomp_table.bs + low_bits;

    const len = decomp_table.s2_len[idx];
    if (len == 0) return null;

    const tag = decomp_table.s2_tag[idx];
    if (tag != .none) return null;

    const off = decomp_table.s2_off[idx];
    return decomp_table.codes[off..][0..len];
}

/// Ensure `dest.len >= 4` to fit every possible decomposition.
/// Change this value only if you know what you are doing.
pub fn fullCanonicalDecomposition(code: u21, dest: []u21) u3 {
    std.debug.assert(code < 0x110000);
    std.debug.assert(dest.len > 0);

    if (code >= s_base and code < s_base + s_count) {
        return fullHangulDecomposition(code, dest);
    }

    if (canonicalDecomposition(code)) |slice| {
        // NOTE: only the first codepoint can have further decomposition
        // as stated in UAX #44 section 5.7.3 Character Decomposition Mapping
        // https://www.unicode.org/reports/tr44/#Character_Decomposition_Mappings
        const len = fullCanonicalDecomposition(slice[0], dest);
        if (slice.len > 1) {
            dest[len] = slice[1];
            return len + 1;
        }

        return len;
    } else {
        dest[0] = code;
        return 1;
    }
}

pub fn compatibilityDecomposition(code: u21) ?[]const u21 {
    std.debug.assert(code < 0x110000);

    if (code >= s_base and code < s_base + s_count) {
        return hangulDecomposition(code);
    }

    const high_bits = code / decomp_table.bs;
    const low_bits = code % decomp_table.bs;

    const idx: u32 = @as(u32, @intCast(decomp_table.s1[high_bits])) * decomp_table.bs + low_bits;

    const len = decomp_table.s2_len[idx];
    if (len == 0) return null;

    const off = decomp_table.s2_off[idx];
    return decomp_table.codes[off..][0..len];
}

/// Ensure `dest.len >= 18` to fit every possible decomposition.
/// Change this value only if you know what you are doing.
pub fn fullCompatibilityDecomposition(code: u21, dest: []u21) u5 {
    std.debug.assert(code < 0x110000);
    std.debug.assert(dest.len > 0);

    if (code >= s_base and code < s_base + s_count) {
        return fullHangulDecomposition(code, dest);
    }

    if (compatibilityDecomposition(code)) |slice| {
        var len: u5 = 0;
        for (slice) |it| {
            len += fullCompatibilityDecomposition(it, dest[len..]);
        }
        return len;
    } else {
        dest[0] = code;
        return 1;
    }
}

// NOTE: The Unicode Standard, Version 16.0 – Core Specification
// 3.12.2 Hangul Syllable Decomposition
const s_base = 0xAC00;
const l_base = 0x1100;
const v_base = 0x1161;
const t_base = 0x11A7;
const l_count = 19;
const v_count = 21;
const t_count = 28;
const n_count = (v_count * t_count);
const s_count = (l_count * n_count);

threadlocal var hangul_buffer: [2]u21 = undefined;

fn hangulDecomposition(code: u21) []const u21 {
    std.debug.assert(code >= s_base and code < s_base + s_count);

    const s_index = code - s_base;

    const t_index = s_index % t_count;
    if (t_index == 0) {
        const l_index = s_index / n_count;
        const v_index = (s_index % n_count) / t_count;
        const l_part = l_base + l_index;
        const v_part = v_base + v_index;

        hangul_buffer = .{ l_part, v_part };
    } else {
        const lv_index = s_index - t_index; // (s_index / t_count) * t_count;
        const lv_part = s_base + lv_index;
        const t_part = t_base + t_index;

        hangul_buffer = .{ lv_part, t_part };
    }

    return &hangul_buffer;
}

fn fullHangulDecomposition(code: u21, dest: []u21) u2 {
    std.debug.assert(code >= s_base and code < s_base + s_count);
    std.debug.assert(dest.len >= 2);

    const s_index = code - s_base;

    const l_index = s_index / n_count;
    const v_index = (s_index % n_count) / t_count;
    const t_index = s_index % t_count;
    const l_part = l_base + l_index;
    const v_part = v_base + v_index;
    const t_part = t_base + t_index;

    var len: u2 = 2;
    len += @intFromBool(t_index > 0);
    @memcpy(
        dest[0..len],
        ([_]u21{ l_part, v_part, t_part })[0..len],
    );
    return len;
}

test "canonDecomp" {
    var dest: [4]u21 = undefined;

    for (0..0x110000) |i| {
        _ = fullCanonicalDecomposition(@intCast(i), &dest);
    }

    try std.testing.expectEqual(1, fullCanonicalDecomposition(0x340, &dest));
    try std.testing.expectEqualSlices(u21, &[_]u21{0x300}, dest[0..1]);

    try std.testing.expectEqual(2, fullCanonicalDecomposition(0xac00, &dest));
    try std.testing.expectEqualSlices(u21, &[_]u21{ 0x1100, 0x1161 }, dest[0..2]);
}

test "compatDecomp" {
    var dest: [18]u21 = undefined;

    for (0..0x110000) |i| {
        _ = fullCompatibilityDecomposition(@intCast(i), &dest);
    }
}

pub fn combiningClass(code: u21) u8 {
    std.debug.assert(code < 0x110000);

    return ccc_table.s2[
        @as(usize, @intCast(
            ccc_table.s1[code / ccc_table.bs],
        )) * ccc_table.bs + code % ccc_table.bs
    ];
}

test "combiningClass" {
    try std.testing.expectEqual(0, combiningClass('a'));
}

pub fn composition(left: u21, right: u21) ?u21 {
    std.debug.assert(left < 0x110000);
    std.debug.assert(right < 0x110000);

    if (left >= l_base and left < l_base + l_count) {
        if (right >= v_base and right < v_base + v_count) {
            return hangulLVComposition(left, right);
        }

        return null;
    }

    if (left >= s_base and (left - s_base) % t_count == 0) {
        if (right >= t_base and right < t_base + t_count) {
            return hangulLVTComposition(left, right);
        }

        return null;
    }

    const left_id = comp_table.ls2[
        @as(usize, @intCast(
            comp_table.ls1[left / comp_table.lbs],
        )) * comp_table.lbs + left % comp_table.lbs
    ];
    if (left_id == std.math.maxInt(u16)) return null;

    const right_id = comp_table.rs2[
        @as(usize, @intCast(
            comp_table.rs1[right / comp_table.rbs],
        )) * comp_table.rbs + right % comp_table.rbs
    ];
    if (right_id == std.math.maxInt(u8)) return null;

    const index = left_id * comp_table.width + right_id;
    const code = comp_table.cs2[
        @as(usize, @intCast(
            comp_table.cs1[index / comp_table.cbs],
        )) * comp_table.cbs + index % comp_table.cbs
    ];
    if (code == 0) return null;

    return code;
}

fn hangulLVComposition(l_part: u21, v_part: u21) ?u21 {
    std.debug.assert(l_part >= l_base and l_part < l_base + l_count);
    std.debug.assert(v_part >= v_base and v_part < v_base + v_count);

    const l_index = l_part - l_base;
    const v_index = v_part - v_base;
    const lv_index = l_index * n_count + v_index * t_count;
    return s_base + lv_index;
}

fn hangulLVTComposition(lv_part: u21, t_part: u21) ?u21 {
    std.debug.assert(lv_part >= s_base and (lv_part - s_base) % t_count == 0);
    std.debug.assert(t_part >= t_base and t_part < t_base + t_count);

    const t_index = t_part - t_base;
    return lv_part + t_index;
}

test "composition" {
    try std.testing.expectEqual(0xc1, composition(0x41, 0x301));
    try std.testing.expectEqual(0xac00, composition(0x1100, 0x1161));
    try std.testing.expectEqual(0xac01, composition(0xac00, 0x11a8));
}

pub const QuickCheck = qc_table.QuickCheck;
pub const Value = qc_table.Value;

pub fn quickCheck(code: u21) QuickCheck {
    std.debug.assert(code < 0x110000);

    return qc_table.s2[
        @as(usize, @intCast(
            qc_table.s1[code / qc_table.bs],
        )) * qc_table.bs + code % qc_table.bs
    ];
}

test {
    try std.testing.expectEqual(QuickCheck{
        .nfd = .yes,
        .nfc = .yes,
        .nfkd = .yes,
        .nfkc = .yes,
    }, quickCheck('a'));
}
