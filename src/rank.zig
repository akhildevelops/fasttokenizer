const std = @import("std");
const utils = @import("./utils.zig");
const fs = std.fs;
const io = std.io;

pub const TokenRanker = struct {
    inner: std.StringHashMap(u32),
    allocator: std.mem.Allocator,
    _inner_bucket: std.ArrayList(u8),
    const Self = @This();

    pub fn free(self: *Self) void {
        // Frees up bucket
        self.allocator.free(self._inner_bucket.items);
        self.inner.clearAndFree();
    }

    pub fn from_file(file_path: []const u8, allocator: std.mem.Allocator) !Self {
        const current_dir = fs.cwd();
        const file = try current_dir.openFile(file_path, .{});
        defer file.close();
        const content = try io.bufferedReader(file.reader()).reader().readAllAlloc(allocator, 5 * 1024 * 1024);
        var contentString = utils.String{ .str = content };
        contentString = contentString.skip_nlines(1);
        return Self.from_string(contentString.str);
    }
    fn _char_vocab(bucket: *std.ArrayList(u8), hashmap: *std.StringHashMap(u32)) !void {
        var counter: u21 = 0;
        var bucket_pointer: usize = 0;
        for (0..std.math.maxInt(u21)) |i| {
            if (counter > 255) {
                break;
            }
            const codepoint: u21 = @intCast(i);
            if (try utils.isPrint(@intCast(i))) {
                const byte_length = try std.unicode.utf8CodepointSequenceLength(codepoint);
                _ = try std.unicode.utf8Encode(codepoint, bucket.items[bucket_pointer .. bucket_pointer + byte_length]);
                try hashmap.put(bucket.items[bucket_pointer .. bucket_pointer + byte_length], counter);
                bucket_pointer += byte_length;
                counter += 1;
            }
        }
    }
    pub fn from_string(content: []const u8, allocator: std.mem.Allocator) !Self {
        var hashmap = std.StringHashMap(u32).init(allocator);
        var bucket = try std.ArrayList(u8).initCapacity(allocator, 500);
        bucket.expandToCapacity();
        try Self._char_vocab(&bucket, &hashmap);

        _ = content;

        return Self{ .inner = hashmap, ._inner_bucket = bucket, .allocator = allocator };
    }
};

test "TokenRanker" {
    var tr = try TokenRanker.from_string("asdf", std.testing.allocator);
    defer tr.free();
    std.log.warn("{any}", .{tr.inner.get("A")});
    try std.testing.expectEqual(tr.inner.count(), 256);
}
