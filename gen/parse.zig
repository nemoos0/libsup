const std = @import("std");
const ascii = std.ascii;
const fmt = std.fmt;
const fs = std.fs;
const mem = std.mem;
const meta = std.meta;
const process = std.process;

const Allocator = mem.Allocator;

var buf: [1024]u8 = undefined;

const Range = struct { start: u21, end: u21 };

pub fn nextLine(file: fs.File) !?[]const u8 {
    if (try file.reader().readUntilDelimiterOrEof(&buf, '\n')) |line| {
        const comment = mem.indexOfAny(u8, line, "@#") orelse line.len;
        const content = line[0..comment];

        if (content.len == 0) {
            return nextLine(file);
        }

        return content;
    }

    return null;
}

pub fn column(line: []const u8, index: usize) ?[]const u8 {
    var iter = mem.splitScalar(u8, line, ';');
    for (0..index) |_| _ = iter.next();

    if (iter.next()) |it| {
        return mem.trim(u8, it, &ascii.whitespace);
    }

    return null;
}

pub fn columnAsRange(line: []const u8, index: usize) !?Range {
    var range: Range = undefined;
    const slice = column(line, index) orelse return null;

    if (mem.indexOf(u8, line, "..")) |dots| {
        range.start = try fmt.parseInt(u21, slice[0..dots], 16);
        range.end = try fmt.parseInt(u21, slice[dots + 2 ..], 16);
    } else {
        range.start = try fmt.parseInt(u21, slice, 16);
        range.end = range.start;
    }

    range.end += 1;
    return range;
}

pub fn columnAsEnum(comptime T: type, line: []const u8, index: usize) ?T {
    const slice = column(line, index) orelse return null;
    return meta.stringToEnum(T, slice);
}

pub fn twoStageTable(
    comptime Index: type,
    comptime T: type,
    comptime size: usize,
    gpa: Allocator,
    array: []const T,
) !struct { []const Index, []const T } {
    std.debug.assert(array.len % size == 0);

    const Block = [size]T;

    var indices: std.ArrayList(Index) = .init(gpa);
    var data: std.ArrayList(T) = .init(gpa);

    var map: std.AutoHashMap(Block, Index) = .init(gpa);
    defer map.deinit();

    for (0..@divExact(array.len, size)) |i| {
        const block: Block = array[i * size ..][0..size].*;
        const res = try map.getOrPut(block);
        if (!res.found_existing) {
            res.value_ptr.* = @intCast(@divExact(data.items.len, size));
            try data.appendSlice(&block);
        }
        try indices.append(res.value_ptr.*);
    }

    return .{ try indices.toOwnedSlice(), try data.toOwnedSlice() };
}
