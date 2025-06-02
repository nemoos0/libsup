const std = @import("std");
const unicode = std.unicode;

const assert = std.debug.assert;

pub const FatIterator = struct {
    context: *anyopaque,
    nextFn: *const fn (*anyopaque) anyerror!?Fat,

    pub fn next(iter: FatIterator) anyerror!?Fat {
        return iter.nextFn(iter.context);
    }
};

pub const Fat = struct {
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
