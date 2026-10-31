//! Evaluator-owned controls for the prospective Ghost Math trial.
//!
//! Every policy receives only n, a work budget, and an evaluator seed, then
//! emits one valid addition chain.  These controls are deliberately separate
//! from the frozen candidate and never import its source.
const std = @import("std");

const MAX_VALUES: usize = 512;

const ValSet = struct {
    values: [MAX_VALUES]u64 = undefined,
    len: usize = 0,

    fn reset(self: *ValSet) void {
        self.len = 0;
    }

    fn has(self: *const ValSet, value: u64) bool {
        for (self.values[0..self.len]) |present| {
            if (present == value) return true;
        }
        return false;
    }

    fn add(self: *ValSet, value: u64) bool {
        if (self.has(value)) return true;
        if (self.len == MAX_VALUES) return false;
        self.values[self.len] = value;
        self.len += 1;
        return true;
    }

    fn sort(self: *ValSet) void {
        std.mem.sort(u64, self.values[0..self.len], {}, comptime std.sort.asc(u64));
    }

    fn chainLength(self: *const ValSet) usize {
        return self.len - 1;
    }
};

fn ilog2(value: u64) usize {
    var result: usize = 0;
    var remaining = value;
    while (remaining > 1) : (remaining >>= 1) result += 1;
    return result;
}

fn binarySet(target: u64, out: *ValSet) bool {
    out.reset();
    if (!out.add(1)) return false;
    if (target == 1) return true;
    var accumulator: u64 = 1;
    var bit = ilog2(target);
    while (bit > 0) {
        bit -= 1;
        accumulator += accumulator;
        if (!out.add(accumulator)) return false;
        if ((target >> @intCast(bit)) & 1 == 1) {
            accumulator += 1;
            if (!out.add(accumulator)) return false;
        }
    }
    return accumulator == target;
}

fn validate(set: *ValSet, target: u64) bool {
    if (set.len == 0) return false;
    set.sort();
    if (set.values[0] != 1 or set.values[set.len - 1] != target) return false;
    var index: usize = 1;
    while (index < set.len) : (index += 1) {
        if (set.values[index] <= set.values[index - 1]) return false;
        var witness = false;
        var left: usize = 0;
        outer: while (left < index) : (left += 1) {
            var right = left;
            while (right < index) : (right += 1) {
                if (set.values[left] + set.values[right] == set.values[index]) {
                    witness = true;
                    break :outer;
                }
            }
        }
        if (!witness) return false;
    }
    return true;
}

fn removable(set: *const ValSet, remove_idx: usize) bool {
    var index: usize = 1;
    while (index < set.len) : (index += 1) {
        if (index == remove_idx) continue;
        var witness = false;
        var left: usize = 0;
        outer: while (left < index) : (left += 1) {
            if (left == remove_idx) continue;
            var right = left;
            while (right < index) : (right += 1) {
                if (right == remove_idx) continue;
                if (set.values[left] + set.values[right] == set.values[index]) {
                    witness = true;
                    break :outer;
                }
            }
        }
        if (!witness) return false;
    }
    return true;
}

fn deletionRepair(set: *ValSet) void {
    set.sort();
    var changed = true;
    while (changed and set.len > 2) {
        changed = false;
        var index: usize = 1;
        while (index + 1 < set.len) : (index += 1) {
            if (!removable(set, index)) continue;
            var move = index;
            while (move + 1 < set.len) : (move += 1) {
                set.values[move] = set.values[move + 1];
            }
            set.len -= 1;
            changed = true;
            break;
        }
    }
}

fn unionBinary(target: u64, out: *ValSet) bool {
    var chain = ValSet{};
    if (!binarySet(target, &chain)) return false;
    for (chain.values[0..chain.len]) |value| {
        if (!out.add(value)) return false;
    }
    return true;
}

fn radixHorner(target: u64, base: u64, out: *ValSet) bool {
    if (target < 2 or base < 2 or base > target) return false;
    var digits: [64]u64 = undefined;
    var digit_count: usize = 0;
    var remaining = target;
    while (remaining > 0) : (remaining /= base) {
        if (digit_count == digits.len) return false;
        digits[digit_count] = remaining % base;
        digit_count += 1;
    }
    var base_chain = ValSet{};
    if (!binarySet(base, &base_chain)) return false;
    out.reset();
    if (!out.add(1)) return false;
    for (digits[0..digit_count]) |digit| {
        if (digit > 1 and !unionBinary(digit, out)) return false;
    }
    var position = digit_count - 1;
    var accumulator = digits[position];
    if (accumulator == 0 or !out.add(accumulator)) return false;
    while (position > 0) {
        position -= 1;
        for (base_chain.values[1..base_chain.len]) |base_value| {
            if (!out.add(accumulator * base_value)) return false;
        }
        accumulator *= base;
        if (digits[position] != 0) {
            accumulator += digits[position];
            if (!out.add(accumulator)) return false;
        }
    }
    return accumulator == target and validate(out, target);
}

fn randomBackward(target: u64, random: std.Random, out: *ValSet) bool {
    out.reset();
    if (!out.add(1)) return false;
    var pending: [MAX_VALUES]u64 = undefined;
    pending[0] = target;
    var pending_len: usize = 1;
    var guard: usize = 0;
    while (pending_len > 0) {
        guard += 1;
        if (guard > 2048) return false;
        var largest_idx: usize = 0;
        for (pending[0..pending_len], 0..) |value, idx| {
            if (value > pending[largest_idx]) largest_idx = idx;
        }
        const value = pending[largest_idx];
        pending[largest_idx] = pending[pending_len - 1];
        pending_len -= 1;
        if (out.has(value)) continue;
        if (!out.add(value) or out.len > 128) return false;
        if (value == 1) continue;
        var split = if (value == 2)
            @as(u64, 1)
        else
            random.intRangeAtMost(u64, 1, value - 1);
        if (value % 2 == 0 and random.boolean()) split = value / 2;
        const children = [2]u64{ split, value - split };
        for (children) |child| {
            if (out.has(child)) continue;
            var present = false;
            for (pending[0..pending_len]) |known| present = present or known == child;
            if (!present) {
                if (pending_len == pending.len) return false;
                pending[pending_len] = child;
                pending_len += 1;
            }
        }
    }
    return out.has(target);
}

var exact_chain: [MAX_VALUES]u64 = undefined;
var exact_nodes: usize = 0;
var exact_budget: usize = 0;
var exact_aborted = false;

fn exactDfs(index: usize, length: usize, target: u64) bool {
    exact_nodes += 1;
    if (exact_nodes > exact_budget) {
        exact_aborted = true;
        return false;
    }
    if (index == length) return exact_chain[index] == target;
    const remaining = length - index - 1;
    var left = index;
    while (true) : (left -= 1) {
        var right = left;
        while (true) : (right -= 1) {
            const next = exact_chain[left] + exact_chain[right];
            if (next > exact_chain[index] and next <= target and
                (@as(u128, next) << @intCast(remaining)) >= target)
            {
                exact_chain[index + 1] = next;
                if (exactDfs(index + 1, length, target)) return true;
                if (exact_aborted) return false;
            }
            if (right == 0) break;
        }
        if (left == 0) break;
    }
    return false;
}

fn bruteForce(target: u64, budget: usize, out: *ValSet) bool {
    exact_nodes = 0;
    exact_budget = budget;
    exact_aborted = false;
    exact_chain[0] = 1;
    var length = ilog2(target);
    if ((@as(u64, 1) << @intCast(length)) < target) length += 1;
    while (length < MAX_VALUES and !exact_aborted) : (length += 1) {
        if (!exactDfs(0, length, target)) continue;
        out.reset();
        for (exact_chain[0 .. length + 1]) |value| {
            if (!out.add(value)) return false;
        }
        return true;
    }
    return false;
}

const Policy = enum {
    fixed_simplification,
    equality_saturation,
    brute_force,
    random,
    replay,
};

fn parsePolicy(text: []const u8) !Policy {
    inline for (std.meta.fields(Policy)) |field| {
        if (std.mem.eql(u8, text, field.name)) return @enumFromInt(field.value);
    }
    return error.UnknownPolicy;
}

fn construct(policy: Policy, target: u64, budget: usize, seed: u64) !ValSet {
    var best = ValSet{};
    if (!binarySet(target, &best)) return error.BinaryFailed;
    switch (policy) {
        .fixed_simplification => {},
        .equality_saturation => {
            // A bounded e-graph proxy over the fixed radix-Horner rewrite
            // grammar.  Each extraction instantiates one complete equivalent
            // program; bases cycle so exactly `budget` programs are charged.
            var build: usize = 0;
            while (build < budget) : (build += 1) {
                const base = @as(u64, @intCast(2 + build % 255));
                if (base > target) continue;
                var candidate = ValSet{};
                if (!radixHorner(target, base, &candidate)) continue;
                if (validate(&candidate, target) and candidate.chainLength() < best.chainLength()) {
                    best = candidate;
                }
            }
            deletionRepair(&best);
        },
        .brute_force => {
            var candidate = ValSet{};
            if (bruteForce(target, budget, &candidate) and validate(&candidate, target) and
                candidate.chainLength() < best.chainLength())
            {
                best = candidate;
            }
        },
        .random => {
            var prng = std.Random.DefaultPrng.init(seed);
            const random = prng.random();
            var build: usize = 0;
            while (build < budget) : (build += 1) {
                var candidate = ValSet{};
                if (!randomBackward(target, random, &candidate)) continue;
                deletionRepair(&candidate);
                if (validate(&candidate, target) and candidate.chainLength() < best.chainLength()) {
                    best = candidate;
                }
            }
        },
        .replay => {
            var candidate = ValSet{};
            if (radixHorner(target, 64, &candidate)) {
                deletionRepair(&candidate);
                if (validate(&candidate, target) and candidate.chainLength() < best.chainLength()) {
                    best = candidate;
                }
            }
        },
    }
    if (!validate(&best, target)) return error.InvalidControlChain;
    return best;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len != 5) {
        std.debug.print("usage: ghost_math_controls_v1 <policy> <target> <budget> <seed_hex>\n", .{});
        std.process.exit(2);
    }
    const policy = try parsePolicy(args[1]);
    const target = try std.fmt.parseUnsigned(u64, args[2], 10);
    const budget = try std.fmt.parseUnsigned(usize, args[3], 10);
    const seed = try std.fmt.parseUnsigned(u64, std.mem.trimLeft(u8, args[4], "0x"), 16);
    if (target < 2 or budget == 0 or budget > 100_000) return error.BadInput;
    const result = try construct(policy, target, budget, seed);
    const actual_work: usize = switch (policy) {
        .fixed_simplification, .replay => 1,
        else => budget,
    };
    const out = std.io.getStdOut().writer();
    try out.print(
        "GHOST_MATH_CONTROL_V1 policy={s} n={d} work={d} unit={s} length={d} chain=",
        .{
            @tagName(policy),
            target,
            actual_work,
            if (policy == .brute_force) "node_expansions" else "program_constructions",
            result.chainLength(),
        },
    );
    for (result.values[0..result.len], 0..) |value, idx| {
        if (idx != 0) try out.writeByte(':');
        try out.print("{d}", .{value});
    }
    try out.writeByte('\n');
}
