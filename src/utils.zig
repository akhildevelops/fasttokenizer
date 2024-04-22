const std = @import("std");
pub const String = struct {
    str: []const u8,
    const Self = @This();
    pub fn skip_nlines(self: *const Self, n_lines: usize) Self {
        var skipped_lines: usize = 0;
        var start: usize = 0;
        while (skipped_lines < n_lines and start < self.str.len) {
            if (self.str[start] == '\n') {
                skipped_lines += 1;
            }
            start += 1;
        }

        return String{ .str = self.str[start % self.str.len ..] };
    }
};

pub fn isPrint(c: u21) error{ CodepointTooLarge, NotYetImplemented }!bool {
    _ = try std.unicode.utf8CodepointSequenceLength(c);
    return switch (c) {
        0x00...0x7f => std.ascii.isPrint(@intCast(c)), // Detect by Ascii
        0x80...0x9f => false, // All are controle chars
        0xa0...0x1ff => true,
        else => error.NotYetImplemented,
    };
}

test "string_skip_nlines" {
    var hello = String{ .str = "Hello/nWorld/nHello/nWorld" };
    var processed_str = hello.skip_nlines(2);
    try std.testing.expectEqualStrings(processed_str.str, hello.str);

    hello = String{ .str = "Hello\nWorld\nHello/nWorld" };
    processed_str = hello.skip_nlines(2);
    try std.testing.expectEqualStrings(processed_str.str, hello.str[12..]);
    try std.testing.expect(!std.mem.eql(u8, processed_str.str, hello.str[13..]));
}

test "unicode_valid_print" {
    try std.testing.expect(try isPrint(32)); // Space char
    try std.testing.expect(try isPrint(33)); // Exclaimation
    try std.testing.expect(try isPrint(0xa1)); // Inverted Exclaimation
    try std.testing.expect(try isPrint(0xa0)); // Non braking space: https://en.wikipedia.org/wiki/Non-breaking_space
}

test "unicode_invalid_print" {
    try std.testing.expect(!(try isPrint(0x7f))); // Control Char
    try std.testing.expect(!(try isPrint(0x9f))); // Control Char
}

test "unicode_not_implemented" {
    try std.testing.expectError(error.NotYetImplemented, isPrint(0x200)); // Control Char
}
