const std = @import("std");
const Rank = @import("./rank.zig");

pub export fn token_ranker() *anyopaque {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const rank = Rank.TokenRanker.from_file("scratchpad/gpt2tokens", "c100k_base", allocator) catch @panic("Cannot initialize TokenRanker");
    return @constCast(&rank);
}

const Calc = struct {
    a: i32,
    b: i32,
    const Self = @This();
    fn perform(_: *Self, comptime x: i32) !i32 {
        return Self._add(13, 23, x);
    }
    fn _add(a: i32, b: i32, comptime x: i32) !i32 {
        _ = a;
        _ = b;
        _ = x;
        return error.nj;
    }
};

pub export fn add() *anyopaque {
    var c: Calc = .{ .a = 5, .b = 10 };
    const value = c.perform(11);
    return @constCast(&value);
}
