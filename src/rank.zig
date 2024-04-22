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
        var buffer_reader = io.bufferedReader(file.reader());
        const content = try buffer_reader.reader().readAllAlloc(allocator, 5 * 1024 * 1024);
        var contentString = utils.String{ .str = content };
        contentString = contentString.skip_nlines(1);
        defer allocator.free(content);
        return Self.from_string(contentString.str, allocator);
    }
    fn _char_vocab(bucket: *std.ArrayList(u8), hashmap: *std.StringHashMap(u32)) !usize {
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
        return bucket_pointer;
    }
    pub fn from_string(content: []const u8, allocator: std.mem.Allocator) !Self {
        var hashmap = std.StringHashMap(u32).init(allocator);
        var bucket = try std.ArrayList(u8).initCapacity(allocator, 50000);
        bucket.expandToCapacity();
        var bucket_pointer = try Self._char_vocab(&bucket, &hashmap);
        var splits = std.mem.splitScalar(u8, content, '\n');
        while (splits.next()) |line| {
            const index = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
            @memcpy(bucket.items[bucket_pointer .. bucket_pointer + index], line[0..index]);
            const second_string = line.len - (index + 1);
            @memcpy(bucket.items[bucket_pointer + index .. bucket_pointer + index + second_string], line[index + 1 .. line.len]);
            try hashmap.put(bucket.items[bucket_pointer .. bucket_pointer + line.len - 1], hashmap.count());
            bucket_pointer += line.len - 1;
        }
        return Self{ .inner = hashmap, ._inner_bucket = bucket, .allocator = allocator };
    }
};

test "TokenRanker" {
    var tr = try TokenRanker.from_string("asdf", std.testing.allocator);
    defer tr.free();
    try std.testing.expectEqual(tr.inner.get("A").?, 33);
    try std.testing.expectEqual(tr.inner.count(), 256);
}

test "TokenRanker partial gpt2" {
    var tr = try TokenRanker.from_string(
        \\ĠLe ilan
        \\ent o
        \\R ocket
        \\Ġbr unch
    , std.testing.allocator);
    defer tr.free();
    try std.testing.expectEqual(tr.inner.count(), 260);
    try std.testing.expectEqual(tr.inner.get("Rocket").?, 258);
}

test "TokenRanker gpt2 from file with partial tokens" {
    var tr = try TokenRanker.from_file("test/gpt2_tokens", std.testing.allocator);
    defer tr.free();
    try std.testing.expectEqual(tr.inner.count(), 262 + 256);
    try std.testing.expectEqual(tr.inner.get("Ġme").?, 247 + 255);
}
