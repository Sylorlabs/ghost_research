//! wikt_edges.zig — turn "<headword> is <gloss>" lines (one-shot definitions, where the funnel's frequency
//! floor can't apply) into high-recall candidate IS-A edges by applying the ALREADY-DISCOVERED copula pattern:
//! subject = headword; candidates = the first few content words of the gloss after the copula (the genus plus
//! its adjectives). Noisy on purpose — cross-source GROUNDING supplies the precision. Function words skipped are
//! the high-frequency connectors the funnel itself discovers, used here as mechanism, not injected ontology.
//! Build: zig build-exe wikt_edges.zig -O ReleaseFast -femit-bin=/tmp/we && /tmp/we < defs.txt > src_wikt.tsv
const std = @import("std");
var A: std.mem.Allocator = undefined;

fn lc(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}
fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}
fn isStop(w: []const u8) bool { // function-word connectors (discoverable as top-frequency; mechanism only)
    inline for (.{ "a", "an", "the", "is", "are", "was", "were", "be", "of", "to", "in", "on", "as", "by", "for", "with", "and", "or", "any", "one", "that", "which", "who", "whose", "used", "from", "at", "into", "it", "its", "this", "their", "such", "other", "esp", "usually", "often", "typically", "generally" }) |s|
        if (std.mem.eql(u8, w, s)) return true;
    return false;
}
fn isBoundary(w: []const u8) bool { // ends the genus noun-phrase
    inline for (.{ "of", "that", "which", "who", "whose", "used", "with", "in", "on", "from", "for", "to", "as", "by", "and", "or", "having", "consisting", "especially" }) |s|
        if (std.mem.eql(u8, w, s)) return true;
    return false;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    A = arena.allocator();
    var out = std.io.bufferedWriter(std.io.getStdOut().writer());
    var br = std.io.bufferedReaderSize(1 << 20, std.io.getStdIn().reader());
    const r = br.reader();
    var line = std.ArrayList(u8).init(A);
    defer line.deinit();
    var nedges: usize = 0;
    while (true) {
        line.clearRetainingCapacity();
        r.streamUntilDelimiter(line.writer(), '\n', null) catch |e| {
            if (e == error.EndOfStream) {
                if (line.items.len == 0) break;
            } else return e;
        };
        // tokenize line into lowercase alpha words
        var toks = std.ArrayList([]const u8).init(A);
        var cur = std.ArrayList(u8).init(A);
        for (line.items) |ch| {
            if (isAlpha(ch)) {
                cur.append(lc(ch)) catch {};
            } else {
                if (cur.items.len >= 1) toks.append(A.dupe(u8, cur.items) catch "") catch {};
                cur.clearRetainingCapacity();
            }
        }
        if (cur.items.len >= 1) toks.append(A.dupe(u8, cur.items) catch "") catch {};
        if (toks.items.len < 3) continue;
        const subj = toks.items[0];
        if (subj.len < 2) continue;
        // find the copula
        var k: usize = 1;
        while (k < toks.items.len and !(std.mem.eql(u8, toks.items[k], "is") or std.mem.eql(u8, toks.items[k], "are") or std.mem.eql(u8, toks.items[k], "was"))) : (k += 1) {}
        if (k >= toks.items.len) continue;
        // collect up to 4 content words of the genus NP, stopping at a clause boundary
        var taken: usize = 0;
        var j = k + 1;
        while (j < toks.items.len and taken < 4) : (j += 1) {
            const w = toks.items[j];
            if (isBoundary(w)) break;
            if (isStop(w) or w.len < 3) continue;
            if (std.mem.eql(u8, w, subj)) continue;
            out.writer().print("{s}\t{s}\n", .{ subj, w }) catch {};
            nedges += 1;
            taken += 1;
        }
    }
    try out.flush();
    std.debug.print("[wikt_edges] {d} candidate edges\n", .{nedges});
}
