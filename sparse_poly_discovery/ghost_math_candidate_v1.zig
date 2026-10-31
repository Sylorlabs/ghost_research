//! Ghost Scientist prospective math candidate v1.
//!
//! Given one visible exponent n, construct exactly one reusable multiplication
//! program for x^n.  The program is an addition chain: starting from exponent 1,
//! every later exponent is the sum of two earlier exponents.  The candidate has
//! no evaluator, baseline, score, answer, clock, filesystem, network, or process
//! access after `seal()`; it emits one self-describing result on stdout.
//!
//! Grammar v1 is deliberately domain-generic rather than target-enumerated.  It
//! spends one fixed construction budget between:
//!   - the inherited binary/factor/window/stochastic portfolio; and
//!   - eight development-learned EXACT_DIGIT_RADIX_HORNER programs with bases
//!     {2,4,8,16,32,64,128,256}.
//! In learned mode 3992/4000 builds go to the inherited search and eight to the
//! exact-digit radix grammar.  Fixed mode spends all 4000 on inherited search.
//! The constructor retains one best chain.  A radix is an internal program
//! parameter, not a second emitted tool: only the final chain is exposed to the
//! evaluator and reusable for arbitrary x.
//!
//! Build:
//!   zig build-exe sparse_poly_discovery/ghost_math_candidate_v1.zig \
//!     -O ReleaseFast -lc -lseccomp
//! Run:
//!   ./ghost_math_candidate_v1 <target_n> <max_builds> <seed_hex> <learned|fixed>
const std = @import("std");

const MAX_VALUES: usize = 512;
const MAX_BASE: u64 = 256;
const REPAIR_POOL: usize = 8;
const SMALL_MAX: u64 = 1024;
const EXACT_CAP: usize = 40;
const EXACT_NODE_BUDGET: u64 = 500_000_000;
const SCMP_ACT_ALLOW: u32 = 0x7fff0000;
const SCMP_ACT_ERRNO_EPERM: u32 = 0x00050001;
const Filter = ?*anyopaque;

extern fn seccomp_init(default_action: u32) Filter;
extern fn seccomp_release(ctx: Filter) void;
extern fn seccomp_rule_add_array(
    ctx: Filter,
    action: u32,
    syscall_num: c_int,
    arg_cnt: c_uint,
    args: ?*const anyopaque,
) c_int;
extern fn seccomp_load(ctx: Filter) c_int;

fn deny(ctx: Filter, call: std.os.linux.SYS) !void {
    if (seccomp_rule_add_array(
        ctx,
        SCMP_ACT_ERRNO_EPERM,
        @intCast(@intFromEnum(call)),
        0,
        null,
    ) != 0) return error.SeccompRuleAdd;
}

fn seal() !void {
    const ctx = seccomp_init(SCMP_ACT_ALLOW) orelse return error.SeccompInit;
    defer seccomp_release(ctx);
    const denied = [_]std.os.linux.SYS{
        .clone,   .clone3,            .fork,            .vfork,
        .execve,  .execveat,          .open,            .openat,
        .openat2, .creat,             .socket,          .socketpair,
        .connect, .bind,              .listen,          .accept,
        .accept4, .unshare,           .setns,           .mount,
        .umount2, .move_mount,        .open_tree,       .fsopen,
        .fsmount, .mount_setattr,     .kill,            .tkill,
        .tgkill,  .pidfd_send_signal, .clock_gettime,   .gettimeofday,
        .time,    .nanosleep,         .clock_nanosleep,
    };
    for (denied) |call| try deny(ctx, call);
    if (seccomp_load(ctx) != 0) return error.SeccompLoad;
}

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
    var n = value;
    var result: usize = 0;
    while (n > 1) : (n >>= 1) result += 1;
    return result;
}

fn binarySet(target: u64, out: *ValSet) bool {
    out.reset();
    if (!out.add(1)) return false;
    if (target == 1) return true;
    const top = ilog2(target);
    var acc: u64 = 1;
    var bit = top;
    while (bit > 0) {
        bit -= 1;
        acc += acc;
        if (!out.add(acc)) return false;
        if ((target >> @intCast(bit)) & 1 == 1) {
            acc += 1;
            if (!out.add(acc)) return false;
        }
    }
    return acc == target;
}

const SmallChain = struct {
    values: [EXACT_CAP + 1]u64 = undefined,
    len: usize = 0,
    ready: bool = false,
};
var small_cache: [SMALL_MAX + 1]SmallChain = [_]SmallChain{.{}} ** (SMALL_MAX + 1);
var exact_work: [EXACT_CAP + 1]u64 = undefined;
var exact_nodes: u64 = 0;
var exact_aborted = false;

fn exactDfs(index: usize, length: usize, target: u64) bool {
    exact_nodes += 1;
    if (exact_nodes > EXACT_NODE_BUDGET) {
        exact_aborted = true;
        return false;
    }
    if (index == length) return exact_work[index] == target;
    const remaining = length - index - 1;
    var a = index;
    while (true) : (a -= 1) {
        var b = a;
        while (true) : (b -= 1) {
            const next = exact_work[a] + exact_work[b];
            if (next > exact_work[index] and next <= target and
                (@as(u128, next) << @intCast(remaining)) >= target)
            {
                exact_work[index + 1] = next;
                if (exactDfs(index + 1, length, target)) return true;
                if (exact_aborted) return false;
            }
            if (b == 0) break;
        }
        if (a == 0) break;
    }
    return false;
}

fn exactSmall(target: u64, out: *ValSet) bool {
    if (target == 0 or target > SMALL_MAX) return false;
    const slot = &small_cache[@intCast(target)];
    if (!slot.ready) {
        exact_work[0] = 1;
        exact_nodes = 0;
        exact_aborted = false;
        var length = ilog2(target);
        if ((@as(u64, 1) << @intCast(length)) < target) length += 1;
        var found = false;
        while (length <= EXACT_CAP and !exact_aborted) : (length += 1) {
            if (exactDfs(0, length, target)) {
                slot.len = length + 1;
                for (0..slot.len) |idx| slot.values[idx] = exact_work[idx];
                found = true;
                break;
            }
        }
        if (!found) {
            var fallback = ValSet{};
            if (!binarySet(target, &fallback)) return false;
            slot.len = fallback.len;
            for (fallback.values[0..fallback.len], 0..) |value, idx| slot.values[idx] = value;
        }
        slot.ready = true;
    }
    out.reset();
    for (slot.values[0..slot.len]) |value| {
        if (!out.add(value)) return false;
    }
    return true;
}

fn smallestFactor(target: u64) u64 {
    if (target % 2 == 0) return 2;
    var divisor: u64 = 3;
    while (divisor * divisor <= target) : (divisor += 2) {
        if (target % divisor == 0) return divisor;
    }
    return target;
}

fn factorRec(target: u64, out: *ValSet, depth: usize) bool {
    if (target == 0 or depth > 128) return false;
    if (target == 1) return out.add(1);
    if (target <= SMALL_MAX) {
        var exact = ValSet{};
        if (!exactSmall(target, &exact)) return false;
        for (exact.values[0..exact.len]) |value| {
            if (!out.add(value)) return false;
        }
        return true;
    }
    const factor = smallestFactor(target);
    if (factor == target) {
        if (!factorRec(target - 1, out, depth + 1)) return false;
        return out.add(target);
    }
    const quotient = target / factor;
    if (!factorRec(factor, out, depth + 1)) return false;
    var quotient_set = ValSet{};
    if (!factorRec(quotient, &quotient_set, depth + 1)) return false;
    for (quotient_set.values[0..quotient_set.len]) |value| {
        if (!out.add(factor * value)) return false;
    }
    return true;
}

fn windowCore(target: u64, max_width: usize, random: ?std.Random, out: *ValSet) bool {
    out.reset();
    if (target < 2 or !out.add(1)) return false;
    var digits: [64]u64 = undefined;
    var exponents: [64]usize = undefined;
    var count: usize = 0;
    var bit: i64 = @intCast(ilog2(target));
    while (bit >= 0) {
        if ((target >> @intCast(bit)) & 1 == 0) {
            bit -= 1;
            continue;
        }
        const width = if (random) |rnd|
            rnd.intRangeAtMost(usize, 1, max_width)
        else
            max_width;
        var low = bit - @as(i64, @intCast(width)) + 1;
        if (low < 0) low = 0;
        while ((target >> @intCast(low)) & 1 == 0) low += 1;
        const actual_width: usize = @intCast(bit - low + 1);
        const digit = (target >> @intCast(low)) &
            ((@as(u64, 1) << @intCast(actual_width)) - 1);
        if (count == digits.len) return false;
        digits[count] = digit;
        exponents[count] = @intCast(low);
        count += 1;
        bit = low - 1;
    }
    if (count == 0) return false;
    var max_digit: u64 = 0;
    for (digits[0..count]) |digit| max_digit = @max(max_digit, digit);
    if (max_digit >= 3) {
        if (!out.add(2)) return false;
        var value: u64 = 3;
        while (value <= max_digit) : (value += 2) {
            if (!out.add(value)) return false;
        }
    }
    var accumulator = digits[0];
    if (!out.add(accumulator)) return false;
    var window: usize = 1;
    while (window <= count) : (window += 1) {
        const next_exponent = if (window < count) exponents[window] else 0;
        var shifts = exponents[window - 1] - next_exponent;
        while (shifts > 0) : (shifts -= 1) {
            accumulator += accumulator;
            if (!out.add(accumulator)) return false;
        }
        if (window < count) {
            accumulator += digits[window];
            if (!out.add(accumulator)) return false;
        }
    }
    return accumulator == target;
}

fn stochasticBackward(target: u64, random: std.Random, out: *ValSet) bool {
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
        if (!out.add(value) or out.len > 96) return false;
        if (value == 1) continue;

        var a: u64 = undefined;
        var b: u64 = undefined;
        if (value == 2) {
            a = 1;
            b = 1;
        } else {
            const roll = random.intRangeLessThan(u32, 0, 100);
            if (value % 2 == 0 and roll < 55) {
                a = value / 2;
                b = value / 2;
            } else {
                var reuse: u64 = 1;
                const strategy = random.intRangeLessThan(u32, 0, 100);
                if (strategy < 45) {
                    for (out.values[0..out.len]) |known| {
                        if (known < value and known > reuse) reuse = known;
                    }
                    for (pending[0..pending_len]) |known| {
                        if (known < value and known > reuse) reuse = known;
                    }
                } else if (strategy < 75) {
                    const half = value / 2;
                    var best_distance: u64 = std.math.maxInt(u64);
                    for (out.values[0..out.len]) |known| {
                        if (known >= value) continue;
                        const distance = if (known > half) known - half else half - known;
                        if (distance < best_distance) {
                            best_distance = distance;
                            reuse = known;
                        }
                    }
                    for (pending[0..pending_len]) |known| {
                        if (known >= value) continue;
                        const distance = if (known > half) known - half else half - known;
                        if (distance < best_distance) {
                            best_distance = distance;
                            reuse = known;
                        }
                    }
                } else {
                    var choices: [2 * MAX_VALUES]u64 = undefined;
                    var choice_count: usize = 0;
                    for (out.values[0..out.len]) |known| {
                        if (known < value) {
                            choices[choice_count] = known;
                            choice_count += 1;
                        }
                    }
                    for (pending[0..pending_len]) |known| {
                        if (known < value) {
                            choices[choice_count] = known;
                            choice_count += 1;
                        }
                    }
                    if (choice_count > 0) {
                        reuse = choices[random.intRangeLessThan(usize, 0, choice_count)];
                    }
                }
                a = value - reuse;
                b = reuse;
            }
        }
        if (a < b) std.mem.swap(u64, &a, &b);
        for ([2]u64{ a, b }) |child| {
            if (child == 0) return false;
            if (out.has(child)) continue;
            var already_pending = false;
            for (pending[0..pending_len]) |known| {
                if (known == child) {
                    already_pending = true;
                    break;
                }
            }
            if (!already_pending) {
                if (pending_len == pending.len) return false;
                pending[pending_len] = child;
                pending_len += 1;
            }
        }
    }
    return out.has(target);
}

fn validate(set: *ValSet, target: u64) bool {
    if (set.len == 0) return false;
    set.sort();
    if (set.values[0] != 1 or set.values[set.len - 1] != target) return false;
    var i: usize = 1;
    while (i < set.len) : (i += 1) {
        if (set.values[i - 1] >= set.values[i]) return false;
        var witnessed = false;
        var a: usize = 0;
        outer: while (a < i) : (a += 1) {
            var b = a;
            while (b < i) : (b += 1) {
                if (set.values[a] + set.values[b] == set.values[i]) {
                    witnessed = true;
                    break :outer;
                }
            }
        }
        if (!witnessed) return false;
    }
    return true;
}

fn removable(set: *const ValSet, remove_idx: usize) bool {
    var i: usize = 1;
    while (i < set.len) : (i += 1) {
        if (i == remove_idx) continue;
        var witnessed = false;
        var a: usize = 0;
        outer: while (a < i) : (a += 1) {
            if (a == remove_idx) continue;
            var b = a;
            while (b < i) : (b += 1) {
                if (b == remove_idx) continue;
                if (set.values[a] + set.values[b] == set.values[i]) {
                    witnessed = true;
                    break :outer;
                }
            }
        }
        if (!witnessed) return false;
    }
    return true;
}

fn deletionRepair(set: *ValSet, descending: bool) void {
    set.sort();
    var changed = true;
    while (changed and set.len > 2) {
        changed = false;
        if (descending) {
            var idx = set.len - 1;
            while (idx > 1) {
                idx -= 1;
                if (removable(set, idx)) {
                    var j = idx;
                    while (j + 1 < set.len) : (j += 1) {
                        set.values[j] = set.values[j + 1];
                    }
                    set.len -= 1;
                    changed = true;
                    break;
                }
            }
        } else {
            var idx: usize = 1;
            while (idx + 1 < set.len) : (idx += 1) {
                if (removable(set, idx)) {
                    var j = idx;
                    while (j + 1 < set.len) : (j += 1) {
                        set.values[j] = set.values[j + 1];
                    }
                    set.len -= 1;
                    changed = true;
                    break;
                }
            }
        }
    }
}

fn deletionRepairRandom(set: *ValSet, random: std.Random) void {
    set.sort();
    var changed = true;
    while (changed and set.len > 2) {
        changed = false;
        var order: [MAX_VALUES]usize = undefined;
        const count = set.len - 2;
        for (0..count) |idx| order[idx] = idx + 1;
        random.shuffle(usize, order[0..count]);
        for (order[0..count]) |remove_idx| {
            if (!removable(set, remove_idx)) continue;
            var idx = remove_idx;
            while (idx + 1 < set.len) : (idx += 1) {
                set.values[idx] = set.values[idx + 1];
            }
            set.len -= 1;
            changed = true;
            break;
        }
    }
}

fn unionSmall(target: u64, out: *ValSet) bool {
    var digit_chain = ValSet{};
    if (!exactSmall(target, &digit_chain)) return false;
    for (digit_chain.values[0..digit_chain.len]) |value| {
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
        if (digit > 1 and !unionSmall(digit, out)) return false;
    }

    var pos = digit_count - 1;
    var acc = digits[pos];
    if (acc == 0 or !out.add(acc)) return false;
    while (pos > 0) {
        pos -= 1;
        // Scale the base chain by the current accumulator.  If u=a+b in
        // base_chain, then acc*u = acc*a + acc*b, so every inserted exponent
        // has a witness already in the union.
        for (base_chain.values[1..base_chain.len]) |base_value| {
            if (!out.add(acc * base_value)) return false;
        }
        acc *= base;
        const digit = digits[pos];
        if (digit != 0) {
            acc += digit;
            if (!out.add(acc)) return false;
        }
    }
    return acc == target and validate(out, target);
}

const SearchResult = struct {
    chain: ValSet,
    base: u64,
    builds: usize,
    grammar: []const u8,
};

fn construct(target: u64, max_builds: usize, seed: u64, learned: bool) !SearchResult {
    if (target < 2) return error.TargetOutOfRange;
    var best = ValSet{};
    if (!binarySet(target, &best) or !validate(&best, target)) {
        return error.BinaryConstruction;
    }
    var best_base: u64 = 0;
    var best_grammar: []const u8 = "FIXED_PORTFOLIO";
    var builds: usize = 0;

    var factor = ValSet{};
    if (factorRec(target, &factor, 0) and validate(&factor, target) and
        factor.chainLength() < best.chainLength())
    {
        best = factor;
    }
    var width: usize = 1;
    while (width <= 6) : (width += 1) {
        var window = ValSet{};
        if (windowCore(target, width, null, &window) and validate(&window, target) and
            window.chainLength() < best.chainLength())
        {
            best = window;
        }
    }

    const radix_budget: usize = if (learned) @min(REPAIR_POOL, max_builds) else 0;
    const stochastic_budget = max_builds - radix_budget;
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    var stochastic = ValSet{};
    var restart: usize = 0;
    while (restart < stochastic_budget) : (restart += 1) {
        var attempt = ValSet{};
        const constructed = if (restart % 2 == 0)
            stochasticBackward(target, random, &attempt)
        else
            windowCore(target, 6, random, &attempt);
        builds += 1;
        if (!constructed) continue;
        const current = if (stochastic.len == 0) std.math.maxInt(usize) else stochastic.chainLength();
        if (restart % 2 == 1 and attempt.chainLength() <= current +| 8) {
            deletionRepairRandom(&attempt, random);
        }
        if (attempt.chainLength() < current and validate(&attempt, target)) {
            stochastic = attempt;
        }
    }
    const supplied = [_]*const ValSet{ &best, &stochastic };
    for (supplied) |source| {
        if (source.len < 2) continue;
        var repaired = source.*;
        deletionRepairRandom(&repaired, random);
        if (validate(&repaired, target) and repaired.chainLength() < best.chainLength()) {
            best = repaired;
        }
    }

    const PoolEntry = struct {
        chain: ValSet,
        base: u64,
    };
    var pool: [REPAIR_POOL]PoolEntry = undefined;
    var pool_len: usize = 0;
    const learned_bases = [_]u64{ 2, 4, 8, 16, 32, 64, 128, 256 };
    for (learned_bases[0..radix_budget]) |base| {
        if (base > target) break;
        var raw = ValSet{};
        if (!radixHorner(target, base, &raw)) continue;
        builds += 1;
        // Repair is cubic-to-quartic in chain size.  Charge every constructed
        // radix program, but reserve expensive repair for the best raw programs
        // instead of silently spending an unbounded amount on every base.
        var insert_at = pool_len;
        for (pool[0..pool_len], 0..) |entry, idx| {
            if (raw.chainLength() < entry.chain.chainLength()) {
                insert_at = idx;
                break;
            }
        }
        if (insert_at < REPAIR_POOL) {
            const new_len = @min(pool_len + 1, REPAIR_POOL);
            var move = new_len - 1;
            while (move > insert_at) : (move -= 1) pool[move] = pool[move - 1];
            pool[insert_at] = .{ .chain = raw, .base = base };
            pool_len = new_len;
        }
    }
    for (pool[0..pool_len]) |entry| {
        var ascending = entry.chain;
        deletionRepair(&ascending, false);
        if (validate(&ascending, target) and ascending.chainLength() < best.chainLength()) {
            best = ascending;
            best_base = entry.base;
            best_grammar = "EXACT_DIGIT_RADIX_HORNER";
        }

        var descending = entry.chain;
        deletionRepair(&descending, true);
        if (validate(&descending, target) and descending.chainLength() < best.chainLength()) {
            best = descending;
            best_base = entry.base;
            best_grammar = "EXACT_DIGIT_RADIX_HORNER";
        }
    }
    if (!validate(&best, target)) return error.InvalidFinalChain;
    return .{
        .chain = best,
        .base = best_base,
        .builds = builds,
        .grammar = best_grammar,
    };
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len != 5) {
        std.debug.print(
            "usage: ghost_math_candidate_v1 <target_n> <max_builds> <seed_hex> <learned|fixed>\n",
            .{},
        );
        std.process.exit(2);
    }
    const target = try std.fmt.parseUnsigned(u64, args[1], 10);
    const max_builds = try std.fmt.parseUnsigned(usize, args[2], 10);
    const seed = try std.fmt.parseUnsigned(u64, std.mem.trimLeft(u8, args[3], "0x"), 16);
    const learned = if (std.mem.eql(u8, args[4], "learned"))
        true
    else if (std.mem.eql(u8, args[4], "fixed"))
        false
    else
        return error.UnknownMode;
    if (max_builds < REPAIR_POOL or max_builds > 100_000) return error.BuildBudgetOutOfRange;

    // Arguments are copied by the trusted runtime before the final candidate
    // filter.  No observation, construction, or output occurs before sealing.
    try seal();
    const result = try construct(target, max_builds, seed, learned);
    const out = std.io.getStdOut().writer();
    try out.print(
        "GHOST_MATH_RESULT_V1 n={d} grammar={s} base={d} builds={d} length={d} chain=",
        .{ target, result.grammar, result.base, result.builds, result.chain.chainLength() },
    );
    for (result.chain.values[0..result.chain.len], 0..) |value, idx| {
        if (idx != 0) try out.writeByte(':');
        try out.print("{d}", .{value});
    }
    try out.writeByte('\n');
}
