const std = @import("std");
const codepoint = @import("codepoint");
const quick_check = @import("quick_check");
const combining_class = @import("combining_class");
const decomposition = @import("decomposition");
const composition = @import("composition");

const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;

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
        source: codepoint.Iterator,
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
        /// `FixedBufferAllocator` of size 128 + 32, to keep track of 32
        /// codepoint + combining class, which is enough "for all practical purposes".
        ///
        /// This assumes Stream-Safe Text Format and will return an
        /// `error.OutOfMemory` otherwise.
        ///
        /// UAX #15 section 13 Stream-Safe Text Format
        /// https://www.unicode.org/reports/tr15/#UAX15-D3
        pub fn init(gpa: Allocator, source: codepoint.Iterator) Allocator.Error!Self {
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

                std.mem.sortUnstableContext(0, norm.starter, SortContext{
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

        fn indexOfSecondStarter(norm: *Self) !?usize {
            var index: ?usize = std.mem.indexOfScalarPos(u8, norm.classes.items, 1, 0);

            while (index == null) {
                if (try norm.source.next()) |cp| {
                    const pos = norm.codes.items.len;
                    try norm.appendCodeDecomposition(cp.code);
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
                    break :blk decomposition.fullCanonical(original, norm.codes.unusedCapacitySlice());
                } else {
                    try norm.codes.ensureUnusedCapacity(norm.gpa, 18);
                    break :blk decomposition.fullCompatibility(original, norm.codes.unusedCapacitySlice());
                }
            };

            try norm.classes.ensureUnusedCapacity(norm.gpa, len);
            for (
                norm.codes.unusedCapacitySlice()[0..len],
                norm.classes.unusedCapacitySlice()[0..len],
            ) |code, *class| {
                class.* = combining_class.get(code);
            }

            norm.codes.items.len += len;
            norm.classes.items.len += len;
        }

        /// Compose the codepoints up to `norm.sorted`.
        /// Returns `true` if there is no further potential composition.
        fn composeSorted(norm: *Self) bool {
            if (norm.classes.items[0] == 0) {
                var i: usize = 1;
                while (i < norm.starter) {
                    const right = norm.codes.items[i];
                    if (composition.get(norm.codes.items[0], right)) |code| {
                        _ = norm.codes.orderedRemove(i);
                        _ = norm.classes.orderedRemove(i);

                        norm.codes.items[0] = code;
                        norm.starter -= 1;
                    } else {
                        i += 1;
                    }
                }

                if (norm.starter == 1 and norm.codes.items.len > 1) {
                    if (composition.get(
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

test {
    const gpa = std.testing.allocator;

    const input = "á";
    var utf8: codepoint.Utf8 = .{ .bytes = input };

    {
        var nfd: Normalizer(.nfd) = try .init(gpa, utf8.iterator());
        defer nfd.deinit();

        var i: usize = 0;
        while (try nfd.next()) |code| : (i += 1) {
            std.debug.print("{x}\n", .{code});
            if (i > 10) break;
        }
    }

    {
        utf8.pos = 0;
        var nfc: Normalizer(.nfc) = try .init(gpa, utf8.iterator());
        defer nfc.deinit();

        var i: usize = 0;
        while (try nfc.next()) |code| : (i += 1) {
            std.debug.print("{x}\n", .{code});
            if (i > 10) break;
        }
    }
}
