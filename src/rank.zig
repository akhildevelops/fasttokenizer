const std = @import("std");
const utils = @import("./utils.zig");
const fs = std.fs;
const io = std.io;

pub const TokenRanker = struct {
    str_to_id: std.StringHashMap(u32),
    id_to_str: std.HashMap(u32, []const u8, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,
    _inner_bucket: std.ArrayList(u8),
    const Self = @This();
    const B = struct { usize, usize, u32 };
    pub fn free(self: *Self) void {
        // Frees up bucket
        self.allocator.free(self._inner_bucket.items);
        self.str_to_id.clearAndFree();
        self.id_to_str.clearAndFree();
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
        const id_to_str = try utils.revStrHashMap(u32, hashmap, allocator);
        return Self{ .str_to_id = hashmap, .id_to_str = id_to_str, ._inner_bucket = bucket, .allocator = allocator };
    }
    fn _is_present(element: B, index: usize) bool {
        return element[0] == index;
    }
    fn _less_s(_: void, lhs: B, rhs: B) bool {
        return lhs[0] < rhs[0];
    }
    pub fn tokenize(self: Self, data: []const u8, allocator: std.mem.Allocator) ![]const u32 {
        // _ = self;
        // _ = data;
        var temp_arr = std.ArrayList(B).init(allocator);
        defer temp_arr.clearAndFree();
        const n_tokens = self.str_to_id.count();
        for (0..n_tokens) |index| {
            const kindex = n_tokens - @as(u32, @intCast(index)) - 1;
            const kv = self.id_to_str.getEntry(kindex).?;
            var multi_index_iter = utils.multiIndexOf(u8, data, kv.value_ptr.*);
            while (multi_index_iter.next()) |mindex| {
                // std.debug.print("{d}:{d}:{s}\n", .{ mindex, kindex, kv.value_ptr.* });
                var multi_iter = utils.multiIndexOfContext(B, temp_arr.items, mindex, _is_present);
                // _ = multi_iter;
                if (multi_iter.next()) |_| {
                    break;
                } else {
                    try temp_arr.append(.{ mindex, kv.value_ptr.*.len, kv.key_ptr.* });
                }
            }
        }
        std.mem.sort(B, temp_arr.items, {}, _less_s);
        var tokens = try std.ArrayList(u32).initCapacity(allocator, temp_arr.items.len);
        for (temp_arr.items) |iitem| {
            try tokens.append(iitem[2]);
        }
        return tokens.toOwnedSlice();
        // return error.hefwaefh;
    }
    pub fn detokenize(self: Self, tokens: []const u32, allocator: std.mem.Allocator) ![]const u8 {
        var text = std.ArrayList(u8).init(allocator);
        for (tokens) |token| {
            try text.appendSlice(self.id_to_str.get(token).?);
        }
        return text.toOwnedSlice();
    }
};

test "TokenRankerBasic" {
    var tr = try TokenRanker.from_string("", std.testing.allocator);
    defer tr.free();
    var iter = tr.str_to_id.iterator();
    while (iter.next()) |kv| {
        std.debug.print("{s}:{d}\n", .{ kv.key_ptr.*, kv.value_ptr.* });
    }
}

test "TokenRanker" {
    var tr = try TokenRanker.from_string("asdf", std.testing.allocator);
    defer tr.free();
    try std.testing.expectEqual(tr.str_to_id.get("A").?, 33);
    try std.testing.expectEqual(tr.str_to_id.count(), 256);
}

test "TokenRanker partial gpt2" {
    var tr = try TokenRanker.from_string(
        \\ĠLe ilan
        \\ent o
        \\R ocket
        \\Ġbr unch
    , std.testing.allocator);
    defer tr.free();
    try std.testing.expectEqual(tr.str_to_id.count(), 260);
    try std.testing.expectEqual(tr.str_to_id.get("Rocket").?, 258);
}

test "TokenRanker gpt2 from file with partial tokens" {
    var tr = try TokenRanker.from_file("test/gpt2_tokens", std.testing.allocator);
    defer tr.free();
    try std.testing.expectEqual(tr.str_to_id.count(), 262 + 256);
    try std.testing.expectEqual(tr.str_to_id.get("Ġme").?, 247 + 255);
}

test "tokenizes" {
    const allocator = std.testing.allocator;
    var tr = try TokenRanker.from_file("test/gpt2_tokens", allocator);
    defer tr.free();
    const tokens = try tr.tokenize("ousrtr", allocator);
    defer allocator.free(tokens);
    const actual: []const u32 = &.{ 516, 385, 83, 82, 84 };
    std.debug.print("{any}\n", .{tokens});
    try std.testing.expect(std.mem.eql(u32, tokens, actual));
}

test "detokenize" {
    const allocator = std.testing.allocator;
    var tr = try TokenRanker.from_file("test/gpt2_tokens", allocator);
    defer tr.free();
    const text = try tr.detokenize(&.{ 516, 385, 83, 82, 84 }, allocator);
    defer allocator.free(text);
    std.debug.print("{s}\n", .{text});
}
