const std = @import("std");
const Rank = @import("./rank.zig");

pub export fn token_ranker() *anyopaque {
    const allocator = std.heap.c_allocator;
    const rank = Rank.TokenRanker.from_file("scratchpad/gpt2tokens", "c100k_base", allocator) catch @panic("Cannot initialize TokenRanker");
    return @constCast(&rank);
}

pub export fn encode(text: [*:0]c_char, token_length: *c_uint, ranker: *anyopaque) [*]c_uint {
    const allocator = std.heap.c_allocator;
    const data: []const u8 = @ptrCast(text[0..std.mem.len(text)]);
    var rranker: *Rank.TokenRanker = @ptrCast(@alignCast(ranker));
    const tokens = rranker.tokenize(data, allocator) catch @panic("Cannot tokenize");
    defer allocator.free(tokens);
    var c_int_array = std.ArrayList(c_uint).initCapacity(allocator, tokens.len) catch @panic("Cannot assign a new array");
    for (0..tokens.len) |index| {
        c_int_array.items[index] = std.math.cast(c_uint, tokens[index]).?;
    }
    token_length.* = std.math.cast(c_uint, tokens.len).?;
    return (c_int_array.toOwnedSlice() catch @panic("Cannot convert to array_slice")).ptr;
}
