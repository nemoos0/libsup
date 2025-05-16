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

pub fn asCodepoint(slice: []const u8) !u21 {
    return try fmt.parseInt(u21, slice, 16);
}

pub fn asRange(slice: []const u8) !Range {
    var range: Range = undefined;

    if (mem.indexOf(u8, slice, "..")) |dots| {
        range.start = try fmt.parseInt(u21, slice[0..dots], 16);
        range.end = try fmt.parseInt(u21, slice[dots + 2 ..], 16);
    } else {
        range.start = try fmt.parseInt(u21, slice, 16);
        range.end = range.start;
    }

    range.end += 1;
    return range;
}

pub fn printConst(ident: []const u8, value: anytype, writer: anytype) !void {
    try writer.print("pub const {s} = ", .{ident});
    try printValue(value, writer);
    try writer.writeByte(';');
}

pub fn printValue(value: anytype, writer: anytype) !void {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    switch (info) {
        .int, .comptime_int => try writer.print("{d}", .{value}),
        .float, .comptime_float => try writer.print("{f}", .{value}), // BUG: don't know if {f} is valid format // BUG: don't know if {f} is valid format
        .bool => try writer.print("{}", .{value}),
        .pointer => switch (info.pointer.size) {
            .slice => {
                try writer.print("[{d}]{s}{{", .{
                    value.len,
                    typeSuffix(info.pointer.child),
                });
                for (value, 0..) |it, i| {
                    if (i > 0) try writer.writeByte(',');
                    try printValue(it, writer);
                }
                try writer.writeAll("}");
            },
            else => unreachable,
        },
        .array => try printValue(&value, writer),
        .@"enum" => try writer.print(".{s}", .{@tagName(value)}),
        .@"struct" => {
            try writer.writeAll(".{");
            inline for (comptime std.meta.fieldNames(T), 0..) |name, i| {
                if (i > 0) try writer.writeByte(',');
                try writer.print(".{s} = ", .{name});
                try printValue(@field(value, name), writer);
            }
            try writer.writeAll("}");
        },
        .type => try printType(value, writer),
        else => unreachable,
    }
}

fn printType(T: type, writer: anytype) !void {
    const info = @typeInfo(T);

    switch (info) {
        .int, .float, .bool => try writer.print("{s}", .{@typeName(T)}),
        .@"enum" => {
            try writer.writeAll("enum(");
            try printType(info.@"enum".tag_type, writer);
            try writer.writeAll(") {");
            inline for (comptime std.meta.fieldNames(T), 0..) |name, i| {
                if (i > 0) try writer.writeByte(',');
                try writer.print("{s}", .{name});
            }
            if (!info.@"enum".is_exhaustive) {
                if (info.@"enum".fields.len > 0) try writer.writeByte(',');
                try writer.writeByte('_');
            }
            try writer.writeAll("}");
        },
        .@"struct" => {
            switch (info.@"struct".layout) {
                .auto => {},
                .@"extern" => try writer.writeAll("extern "),
                .@"packed" => try writer.writeAll("packed "),
            }

            try writer.writeAll("struct");
            if (info.@"struct".backing_integer) |I| {
                try writer.writeByte('(');
                try printType(I, writer);
                try writer.writeByte(')');
            }

            try writer.writeAll(" {");
            inline for (comptime std.meta.fields(T), 0..) |field, i| {
                if (i > 0) try writer.writeByte(',');
                try writer.print("{s}: {s}", .{ field.name, typeSuffix(field.type) });
            }
            try writer.writeAll("}");
        },
        else => unreachable,
    }
}

fn typeSuffix(T: type) []const u8 {
    var iter = std.mem.splitBackwardsScalar(u8, @typeName(T), '.');
    return iter.first();
}

pub fn twoStageTable(
    comptime Index: type,
    comptime T: type,
    comptime size: usize,
    arena: Allocator,
    array: []const T,
) !struct { []const Index, []const T } {
    std.debug.assert(array.len % size == 0);

    const Block = [size]T;

    var indices: std.ArrayList(Index) = .init(arena);
    var data: std.ArrayList(T) = .init(arena);

    var map: std.AutoHashMap(Block, Index) = .init(arena);
    defer map.deinit();

    for (0..@divExact(array.len, size)) |i| {
        const block: Block = array[i * size ..][0..size].*;
        const res = map.getOrPut(block) catch unreachable;
        if (!res.found_existing) {
            res.value_ptr.* = @intCast(@divExact(data.items.len, size));
            data.appendSlice(&block) catch unreachable;
        }
        indices.append(res.value_ptr.*) catch unreachable;
    }

    return .{
        indices.toOwnedSlice() catch unreachable,
        data.toOwnedSlice() catch unreachable,
    };
}
