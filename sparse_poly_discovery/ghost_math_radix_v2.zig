//! Ghost Math outcome-learned radix constructor v2.
//!
//! Prospective v1 showed that eight power-of-two radices were too sparse: none
//! of 60 held-out artifacts selected them.  This answer-free successor spends
//! the released 255-build budget on every radix in [2,256], using exact small
//! addition chains for the radix itself and for all digits.  Each program is
//! crossed with the inherited 47,745-build chain: the union exposes alternative
//! witnesses, then deletion repair may remove structure neither chain could
//! remove alone.  The complete hybrid is charged 48,000 constructions; the
//! protocol's strong fixed control receives 96,000.  This component receives
//! only n and the visible inherited chain, emits one final chain, and has no
//! target table or evaluator feedback.
const std = @import("std");

const MAX_VALUES: usize = 512;
const MAX_RADIX: u64 = 256;
const EXACT_CAP: usize = 40;
const EXACT_NODE_BUDGET: u64 = 500_000_000;
const REPAIR_POOL: usize = 64;
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
    const calls = [_]std.os.linux.SYS{
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
    for (calls) |call| try deny(ctx, call);
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

fn deletionRepair(set: *ValSet, descending: bool) void {
    set.sort();
    var changed = true;
    while (changed and set.len > 2) {
        changed = false;
        if (descending) {
            var index = set.len - 1;
            while (index > 1) {
                index -= 1;
                if (!removable(set, index)) continue;
                var move = index;
                while (move + 1 < set.len) : (move += 1) {
                    set.values[move] = set.values[move + 1];
                }
                set.len -= 1;
                changed = true;
                break;
            }
        } else {
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
}

const SmallChain = struct {
    values: [EXACT_CAP + 1]u64 = undefined,
    len: usize = 0,
    ready: bool = false,
};
var cache: [MAX_RADIX + 1]SmallChain = [_]SmallChain{.{}} ** (MAX_RADIX + 1);
var work: [EXACT_CAP + 1]u64 = undefined;
var nodes: u64 = 0;
var aborted = false;

fn exactDfs(index: usize, length: usize, target: u64) bool {
    nodes += 1;
    if (nodes > EXACT_NODE_BUDGET) {
        aborted = true;
        return false;
    }
    if (index == length) return work[index] == target;
    const remaining = length - index - 1;
    var left = index;
    while (true) : (left -= 1) {
        var right = left;
        while (true) : (right -= 1) {
            const next = work[left] + work[right];
            if (next > work[index] and next <= target and
                (@as(u128, next) << @intCast(remaining)) >= target)
            {
                work[index + 1] = next;
                if (exactDfs(index + 1, length, target)) return true;
                if (aborted) return false;
            }
            if (right == 0) break;
        }
        if (left == 0) break;
    }
    return false;
}

fn exactSmall(target: u64, out: *ValSet) bool {
    if (target == 0 or target > MAX_RADIX) return false;
    const slot = &cache[@intCast(target)];
    if (!slot.ready) {
        nodes = 0;
        aborted = false;
        work[0] = 1;
        var length = ilog2(target);
        if ((@as(u64, 1) << @intCast(length)) < target) length += 1;
        var found = false;
        while (length <= EXACT_CAP and !aborted) : (length += 1) {
            if (exactDfs(0, length, target)) {
                slot.len = length + 1;
                for (0..slot.len) |idx| slot.values[idx] = work[idx];
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

fn unionExact(target: u64, out: *ValSet) bool {
    var chain = ValSet{};
    if (!exactSmall(target, &chain)) return false;
    for (chain.values[0..chain.len]) |value| {
        if (!out.add(value)) return false;
    }
    return true;
}

fn radixHorner(target: u64, radix: u64, out: *ValSet) bool {
    if (target < 2 or radix < 2 or radix > target or radix > MAX_RADIX) return false;
    var digits: [64]u64 = undefined;
    var digit_count: usize = 0;
    var remaining = target;
    while (remaining > 0) : (remaining /= radix) {
        if (digit_count == digits.len) return false;
        digits[digit_count] = remaining % radix;
        digit_count += 1;
    }
    var radix_chain = ValSet{};
    if (!exactSmall(radix, &radix_chain)) return false;
    out.reset();
    if (!out.add(1)) return false;
    for (digits[0..digit_count]) |digit| {
        if (digit > 1 and !unionExact(digit, out)) return false;
    }
    var position = digit_count - 1;
    var accumulator = digits[position];
    if (accumulator == 0 or !out.add(accumulator)) return false;
    while (position > 0) {
        position -= 1;
        for (radix_chain.values[1..radix_chain.len]) |radix_value| {
            if (!out.add(accumulator * radix_value)) return false;
        }
        accumulator *= radix;
        if (digits[position] != 0) {
            accumulator += digits[position];
            if (!out.add(accumulator)) return false;
        }
    }
    return accumulator == target and validate(out, target);
}

const Result = struct {
    chain: ValSet,
    radix: u64,
    builds: usize,
};

fn construct(target: u64, budget: usize, inherited: *const ValSet) !Result {
    if (budget != MAX_RADIX - 1) return error.BudgetMustBe255;
    var best = inherited.*;
    if (!validate(&best, target)) return error.InvalidInheritedChain;
    var best_radix: u64 = 0;
    const Entry = struct { chain: ValSet, radix: u64 };
    var pool: [REPAIR_POOL]Entry = undefined;
    var pool_len: usize = 0;
    var radix: u64 = 2;
    var builds: usize = 0;
    while (radix <= MAX_RADIX) : (radix += 1) {
        var raw = ValSet{};
        if (!radixHorner(target, radix, &raw)) return error.RadixConstructionFailed;
        builds += 1;
        var insert_at = pool_len;
        for (pool[0..pool_len], 0..) |entry, idx| {
            if (raw.chainLength() < entry.chain.chainLength()) {
                insert_at = idx;
                break;
            }
        }
        if (insert_at < REPAIR_POOL) {
            const next_len = @min(pool_len + 1, REPAIR_POOL);
            var move = next_len - 1;
            while (move > insert_at) : (move -= 1) pool[move] = pool[move - 1];
            pool[insert_at] = .{ .chain = raw, .radix = radix };
            pool_len = next_len;
        }
    }
    for (pool[0..pool_len]) |entry| {
        var merged = inherited.*;
        for (entry.chain.values[0..entry.chain.len]) |value| {
            if (!merged.add(value)) return error.UnionOverflow;
        }
        if (!validate(&merged, target)) return error.InvalidUnion;
        var ascending = merged;
        deletionRepair(&ascending, false);
        if (validate(&ascending, target) and ascending.chainLength() < best.chainLength()) {
            best = ascending;
            best_radix = entry.radix;
        }
        var descending = merged;
        deletionRepair(&descending, true);
        if (validate(&descending, target) and descending.chainLength() < best.chainLength()) {
            best = descending;
            best_radix = entry.radix;
        }
    }
    if (!validate(&best, target)) return error.InvalidFinalChain;
    return .{ .chain = best, .radix = best_radix, .builds = builds };
}

fn parseChain(text: []const u8, target: u64) !ValSet {
    var result = ValSet{};
    var values = std.mem.tokenizeScalar(u8, text, ':');
    while (values.next()) |value_text| {
        const value = try std.fmt.parseUnsigned(u64, value_text, 10);
        if (!result.add(value)) return error.ChainTooLong;
    }
    if (!validate(&result, target)) return error.InvalidInputChain;
    return result;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len != 4) {
        std.debug.print("usage: ghost_math_radix_v2 <target_n> <budget_255> <inherited_chain>\n", .{});
        std.process.exit(2);
    }
    const target = try std.fmt.parseUnsigned(u64, args[1], 10);
    const budget = try std.fmt.parseUnsigned(usize, args[2], 10);
    const inherited = try parseChain(args[3], target);
    try seal();
    const result = try construct(target, budget, &inherited);
    const out = std.io.getStdOut().writer();
    try out.print(
        "GHOST_MATH_RADIX_V2 n={d} grammar=CROSSOVER_EXACT_ALL_RADIX radix={d} builds={d} length={d} chain=",
        .{ target, result.radix, result.builds, result.chain.chainLength() },
    );
    for (result.chain.values[0..result.chain.len], 0..) |value, idx| {
        if (idx != 0) try out.writeByte(':');
        try out.print("{d}", .{value});
    }
    try out.writeByte('\n');
}
