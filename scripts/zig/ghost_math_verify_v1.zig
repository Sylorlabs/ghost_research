//! Independent verifier for GHOST_MATH_RESULT_V1.
//!
//! This file does not import candidate code.  It proves the emitted addition
//! chain structurally and cross-checks the resulting exponentiation program over
//! several modular rings.  It rejects extra lines/tokens and supports mutation
//! self-tests used by the evaluator.
const std = @import("std");

const MAX_VALUES: usize = 512;

const Parsed = struct {
    target: u64,
    grammar: []const u8,
    base: u64,
    builds: usize,
    claimed_length: usize,
    chain: [MAX_VALUES]u64,
    chain_len: usize,
};

fn fieldValue(token: []const u8, prefix: []const u8) ![]const u8 {
    if (!std.mem.startsWith(u8, token, prefix)) return error.BadField;
    return token[prefix.len..];
}

fn parse(line_raw: []const u8) !Parsed {
    const line = std.mem.trimRight(u8, line_raw, "\r\n");
    if (line.len == 0 or std.mem.indexOfScalar(u8, line, '\n') != null or
        std.mem.indexOfScalar(u8, line, '\r') != null)
    {
        return error.NotExactlyOneLine;
    }
    var tokens = std.mem.tokenizeScalar(u8, line, ' ');
    if (!std.mem.eql(u8, tokens.next() orelse return error.MissingHeader, "GHOST_MATH_RESULT_V1")) {
        return error.BadHeader;
    }
    const target = try std.fmt.parseUnsigned(
        u64,
        try fieldValue(tokens.next() orelse return error.MissingTarget, "n="),
        10,
    );
    const grammar = try fieldValue(tokens.next() orelse return error.MissingGrammar, "grammar=");
    const base = try std.fmt.parseUnsigned(
        u64,
        try fieldValue(tokens.next() orelse return error.MissingBase, "base="),
        10,
    );
    const builds = try std.fmt.parseUnsigned(
        usize,
        try fieldValue(tokens.next() orelse return error.MissingBuilds, "builds="),
        10,
    );
    const claimed_length = try std.fmt.parseUnsigned(
        usize,
        try fieldValue(tokens.next() orelse return error.MissingLength, "length="),
        10,
    );
    const chain_text = try fieldValue(tokens.next() orelse return error.MissingChain, "chain=");
    if (tokens.next() != null) return error.ExtraToken;

    var result = Parsed{
        .target = target,
        .grammar = grammar,
        .base = base,
        .builds = builds,
        .claimed_length = claimed_length,
        .chain = undefined,
        .chain_len = 0,
    };
    var values = std.mem.tokenizeScalar(u8, chain_text, ':');
    while (values.next()) |value_text| {
        if (result.chain_len == MAX_VALUES) return error.ChainTooLong;
        result.chain[result.chain_len] = try std.fmt.parseUnsigned(u64, value_text, 10);
        result.chain_len += 1;
    }
    if (result.chain_len == 0) return error.EmptyChain;
    return result;
}

fn mulMod(a: u64, b: u64, modulus: u64) u64 {
    return @intCast((@as(u128, a) * @as(u128, b)) % modulus);
}

fn powMod(base: u64, exponent: u64, modulus: u64) u64 {
    var result: u64 = 1 % modulus;
    var factor = base % modulus;
    var remaining = exponent;
    while (remaining > 0) : (remaining >>= 1) {
        if (remaining & 1 == 1) result = mulMod(result, factor, modulus);
        factor = mulMod(factor, factor, modulus);
    }
    return result;
}

fn verify(parsed: *const Parsed, expected_target: u64, expected_builds: ?usize) !void {
    if (parsed.target != expected_target) return error.TargetMismatch;
    if (expected_builds) |builds| {
        if (parsed.builds != builds) return error.BuildBudgetMismatch;
    }
    if (parsed.chain_len != parsed.claimed_length + 1) return error.LengthMismatch;
    if (parsed.chain[0] != 1) return error.ChainMustStartAtOne;
    if (parsed.chain[parsed.chain_len - 1] != parsed.target) return error.ChainMustEndAtTarget;
    if (parsed.grammar.len == 0) return error.EmptyGrammar;
    if (std.mem.eql(u8, parsed.grammar, "EXACT_DIGIT_RADIX_HORNER")) {
        const allowed = [_]u64{ 2, 4, 8, 16, 32, 64, 128, 256 };
        var found = false;
        for (allowed) |base| found = found or parsed.base == base;
        if (!found) return error.UnfrozenRadix;
    } else if (std.mem.eql(u8, parsed.grammar, "FIXED_PORTFOLIO")) {
        if (parsed.base != 0) return error.FixedPortfolioHasRadix;
    } else {
        return error.UnknownGrammar;
    }

    var index: usize = 1;
    while (index < parsed.chain_len) : (index += 1) {
        if (parsed.chain[index] <= parsed.chain[index - 1]) return error.NotStrictlyAscending;
        var witness = false;
        var left: usize = 0;
        outer: while (left < index) : (left += 1) {
            var right = left;
            while (right < index) : (right += 1) {
                if (parsed.chain[left] + parsed.chain[right] == parsed.chain[index]) {
                    witness = true;
                    break :outer;
                }
            }
        }
        if (!witness) return error.MissingAdditionWitness;
    }

    // Independent semantic cross-check: execute the chain as multiplications
    // and compare with binary modular exponentiation.  Structural verification
    // above is the proof; these cases detect parser/executor implementation bugs.
    const moduli = [_]u64{ 3, 5, 17, 257, 65537, 4_294_967_291 };
    const bases = [_]u64{ 0, 1, 2, 3, 7, 19, 255 };
    for (moduli) |modulus| {
        for (bases) |input| {
            var values: [MAX_VALUES]u64 = undefined;
            values[0] = input % modulus;
            var step: usize = 1;
            while (step < parsed.chain_len) : (step += 1) {
                var found = false;
                var left: usize = 0;
                outer: while (left < step) : (left += 1) {
                    var right = left;
                    while (right < step) : (right += 1) {
                        if (parsed.chain[left] + parsed.chain[right] == parsed.chain[step]) {
                            values[step] = mulMod(values[left], values[right], modulus);
                            found = true;
                            break :outer;
                        }
                    }
                }
                if (!found) return error.SemanticWitnessMissing;
            }
            if (values[parsed.chain_len - 1] != powMod(input, parsed.target, modulus)) {
                return error.SemanticMismatch;
            }
        }
    }
}

fn expectRejected(line: []const u8, target: u64) !void {
    const parsed = parse(line) catch return;
    verify(&parsed, target, null) catch return;
    return error.MutationAccepted;
}

fn selftest() !void {
    const good =
        "GHOST_MATH_RESULT_V1 n=15 grammar=EXACT_DIGIT_RADIX_HORNER base=4 builds=4000 length=5 chain=1:2:3:6:12:15\n";
    const parsed = try parse(good);
    try verify(&parsed, 15, 4000);
    try expectRejected(
        "GHOST_MATH_RESULT_V1 n=15 grammar=EXACT_DIGIT_RADIX_HORNER base=4 builds=4000 length=4 chain=1:2:4:7:15\n",
        15,
    );
    try expectRejected(
        "GHOST_MATH_RESULT_V1 n=16 grammar=FIXED_PORTFOLIO base=0 builds=4000 length=5 chain=1:2:3:6:12:15\n",
        16,
    );
    try expectRejected(
        "GHOST_MATH_RESULT_V1 n=15 grammar=UNFROZEN base=4 builds=4000 length=5 chain=1:2:3:6:12:15\n",
        15,
    );
    try expectRejected(
        "GHOST_MATH_RESULT_V1 n=15 grammar=EXACT_DIGIT_RADIX_HORNER base=4 builds=3999 length=5 chain=1:2:3:6:12:15 extra=1\n",
        15,
    );
    std.debug.print(
        "ghost_math_verify_v1 selftest PASS valid=1 mutations_rejected=4 structural=true modular_crosscheck=true\n",
        .{},
    );
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len == 2 and std.mem.eql(u8, args[1], "selftest")) return selftest();
    if (args.len < 2 or args.len > 3) {
        std.debug.print("usage: ghost_math_verify_v1 <expected_target> [expected_builds]\n", .{});
        std.process.exit(2);
    }
    const target = try std.fmt.parseUnsigned(u64, args[1], 10);
    const builds = if (args.len == 3)
        try std.fmt.parseUnsigned(usize, args[2], 10)
    else
        null;
    const input = try std.io.getStdIn().reader().readAllAlloc(allocator, 1 << 20);
    defer allocator.free(input);
    const parsed = try parse(input);
    try verify(&parsed, target, builds);
    std.debug.print(
        "VALID n={d} length={d} grammar={s} builds={d} structural=true modular_crosscheck=true\n",
        .{ parsed.target, parsed.claimed_length, parsed.grammar, parsed.builds },
    );
}
