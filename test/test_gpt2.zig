const std = @import("std");
const t = @import("fasttokenizer");

// test "sample" {
//     const allocator = std.testing.allocator;
//     var tr = try t.TokenRanker.from_file("scratchpad/gpt2tokens", allocator);
//     defer tr.free();
//     const text = try tr.detokenize(&.{ 8269, 10535, 830 }, allocator);
//     std.debug.print("{s}\n", .{text});
//     defer allocator.free(text);
//     try std.testing.expect(std.mem.eql(u8, text, "00000000000000000"));
// }

test "sample" {
    const allocator = std.testing.allocator;
    var tr = try t.TokenRanker.from_file(allocator);
    defer tr.free();
    const slice = try tr.tokenize("Operations on vectors shorter than the target machine's native SIMD size will typically compile to single ", allocator);
    defer std.testing.allocator.free(slice);
    std.debug.print("{any}\n", .{slice});
    // defer allocator.free(tokens);
    // try std.testing.expect(std.mem.eql(u8, text, "fbf erfgarsg"));
}

// test "sdf" {
//     const items: []struct { usize, usize } = undefined;
//     for (items) |item| {
//         _ = item[0];
//     }
// }
