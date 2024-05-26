const std = @import("std");
const B64Decoder = std.base64.standard.Decoder;
const utils = @import("./utils.zig");
const model = @import("./model.zig");
const Regex = @import("jstring").Regex;
const fs = std.fs;
const io = std.io;

const T = struct { usize, usize };

fn _less_than(_: void, lhs: T, rhs: T) bool {
    return lhs[1] < rhs[1];
}

pub const TokenRanker = struct {
    str_to_id: std.StringHashMap(usize),
    id_to_str: std.HashMap(usize, []const u8, std.hash_map.AutoContext(usize), std.hash_map.default_max_load_percentage),
    tokens: [100256][]const u8,
    allocator: std.mem.Allocator,
    regex: Regex,
    const Self = @This();
    pub fn free(self: *Self) void {
        self.regex.deinit();
        self.str_to_id.deinit();
        self.id_to_str.deinit();
        for (self.tokens) |token| {
            self.allocator.free(token);
        }
    }

    pub fn from_file(comptime file_path: []const u8, comptime model_type: []const u8, allocator: std.mem.Allocator) !Self {
        const current_dir = fs.cwd();
        const file = try current_dir.openFile(file_path, .{});
        defer file.close();
        var buffer_reader = io.bufferedReader(file.reader());
        const content = try buffer_reader.reader().readAllAlloc(allocator, 5 * 1024 * 1024);
        defer allocator.free(content);
        return Self.from_string(content, model_type, allocator);
    }

    pub fn from_string(content: []const u8, comptime model_type: []const u8, allocator: std.mem.Allocator) !Self {
        std.debug.print("{d}\n", .{123});
        const Model = model.get_model(model_type);
        var tokens: [Model.n_tokens][]const u8 = undefined;

        var str_to_id = std.StringHashMap(usize).init(allocator);
        try str_to_id.ensureTotalCapacity(Model.n_tokens);

        var splits = std.mem.splitScalar(u8, content, '\n');

        while (splits.next()) |line| {
            const index = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
            const decoded_len = try B64Decoder.calcSizeForSlice(line[0..index]);

            var destination = try std.ArrayList(u8).initCapacity(allocator, decoded_len);
            destination.expandToCapacity();
            try B64Decoder.decode(destination.items, line[0..index]);
            const rank = try std.fmt.parseInt(usize, line[index + 1 ..], 10);
            tokens[rank] = try destination.toOwnedSlice();
            try str_to_id.put(tokens[rank], rank);
        }
        const id_to_str = try utils.revStrHashMap(usize, str_to_id, allocator);

        //IMPROVE: Make it modular
        // const regex_exp = .{
        //     \\[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?|
        //     ,
        //     \\[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}\p{Lm}\p{Lo}\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?|
        //     ,
        //     \\\p{N}{1,3}|
        //     ,
        //     \\ ?[^\s\p{L}\p{N}]+[\r\n]*|
        //     ,
        //     \\\s*[\r\n]+|
        //     ,
        //     \\\s+(?!\S)|
        //     ,
        //     \\\s+
        // };
        // const re_string = try std.mem.concatWithSentinel(allocator, u8, &regex_exp, 0);
        // std.debug.print("{s}\n", .{re_string});
        const re = try Regex.init(allocator, Model.regex_pattern, 0x00080000);
        return Self{ .tokens = tokens, .allocator = allocator, .regex = re, .str_to_id = str_to_id, .id_to_str = id_to_str };
    }

    pub fn tokenize(self: *Self, data: []const u8, allocator: std.mem.Allocator) ![]const usize {
        try self.regex.matchAll(data, 0, 0);
        if (!self.regex.succeed()) {
            return error.RegexMatchFailed;
        }
        if (self.str_to_id.get(data)) |rank| {
            return &.{rank};
        }

        const results = self.regex.getResults().?;
        var splits = std.ArrayList([][]const u8).init(allocator);
        defer {
            for (splits.items) |split| {
                for (split) |sub_split| {
                    allocator.free(sub_split);
                }
                allocator.free(split);
            }
            splits.deinit();
        }
        for (results) |matched_result| {
            const matched_string: []const u8 = data[matched_result.start .. matched_result.start + matched_result.len];
            var collection = try allocator.alloc([]const u8, matched_result.len);
            for (matched_string, 0..) |each_byte, each_byte_index| {
                const byte_container = try allocator.alloc(u8, 1);
                byte_container[0] = each_byte;
                collection[each_byte_index] = byte_container;
            }
            try splits.append(collection);
        }

        for (self.tokens) |token| {
            for (splits.items) |*split| {
                var pointer: usize = 0;
                while (pointer < split.len - 1) {
                    const concat = try std.mem.concat(allocator, u8, &.{ split.*[pointer], split.*[pointer + 1] });
                    if (std.mem.eql(u8, concat, token)) {
                        var n_split = try allocator.alloc([]const u8, split.len - 1);
                        for (0..n_split.len) |index| {
                            if (index < pointer) {
                                n_split[index] = split.*[index];
                            } else if (index > pointer) {
                                n_split[index] = split.*[index + 1];
                            } else {
                                n_split[index] = concat;
                            }
                        }
                        allocator.free(split.*[pointer]);
                        allocator.free(split.*[pointer + 1]);
                        allocator.free(split.*);
                        split.* = n_split;
                    } else {
                        allocator.free(concat);
                    }
                    pointer += 1;
                }
            }
        }
        var token_ids = std.ArrayList(usize).init(allocator);
        for (splits.items) |split| {
            for (split) |i| {
                try token_ids.append(self.str_to_id.get(i).?);
            }
        }
        try self.regex.reset();
        return try token_ids.toOwnedSlice();
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
    try std.testing.expectEqual(tr.str_to_id.count(), 256);
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
    const tokens = try tr.tokenize("Ġmeousrtr", allocator);
    defer allocator.free(tokens);
    const actual: []const u32 = &.{ 502, 516, 82, 84, 82 };
    try std.testing.expect(std.mem.eql(u32, tokens, actual));
}

test "detokenize" {
    const allocator = std.testing.allocator;
    var tr = try TokenRanker.from_file("test/gpt2_tokens", allocator);
    defer tr.free();
    const text = try tr.detokenize(&.{ 502, 516, 82, 84, 82 }, allocator);
    defer allocator.free(text);
    try std.testing.expect(std.mem.eql(u8, text, "Ġmeousrtr"));
}

// This runs against larger GPT2 Token File
test "Skip" {
    const d = fs.cwd();
    _ = d.openFile("scratchpad/gpt2tokens", .{}) catch {
        return error.SkipZigTest;
    };
    const allocator = std.testing.allocator;
    var tr = try TokenRanker.from_file("scratchpad/gpt2tokens", allocator);
    defer tr.free();
    const text = try tr.detokenize(&.{ 502, 516, 82, 84, 82 }, allocator);
    defer allocator.free(text);
    try std.testing.expect(std.mem.eql(u8, text, "Ġmeousrtr"));
}

test {
    const splits = std.ArrayList([][]const u8).init(undefined);
    for (splits.items) |item| {
        _ = item;
    }
}
