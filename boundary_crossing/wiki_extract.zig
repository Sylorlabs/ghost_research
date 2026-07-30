//! wiki_extract.zig — STREAM a MediaWiki pages-articles XML on stdin, emit one cleaned lead/definition
//! sentence per article on stdout. No hoarding: reads the decompressed XML as a stream, keeps only a small
//! per-page buffer, writes compact definitions. Pipeline:
//!   curl -s <dump>.bz2 | bzip2 -d | wiki_extract > defs.txt
//! Cleaning is deliberately light (strip templates {{}}, links [[]], refs/tags, bold/italic, parentheticals)
//! — just enough to preserve "X is a Y" definitional structure for downstream DISCOVERY (no taxonomy handed in).
const std = @import("std");
var A: std.mem.Allocator = undefined;
var out: std.io.BufferedWriter(4096, std.fs.File.Writer) = undefined;

const CAP = 4000; // max bytes of lead captured per page
var in_text = false;
var skip_ns = false;
var cap: std.ArrayList(u8) = undefined;
var emitted: usize = 0;
var seen: usize = 0;

fn lc(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}
fn istart(h: []const u8, n: []const u8) bool {
    return h.len >= n.len and std.ascii.eqlIgnoreCase(h[0..n.len], n);
}
fn appendCapped(s: []const u8) void {
    if (cap.items.len >= CAP) return;
    const room = CAP - cap.items.len;
    cap.appendSlice(s[0..@min(room, s.len)]) catch {};
}
fn reset() void {
    in_text = false;
    skip_ns = false;
    cap.clearRetainingCapacity();
}

// crude wikitext → text. returns cleaned bytes in `o`.
fn clean(raw: []const u8, o: *std.ArrayList(u8)) void {
    var i: usize = 0;
    while (i < raw.len) {
        const rest = raw[i..];
        if (std.mem.startsWith(u8, rest, "{{")) { // template — skip nested
            var depth: usize = 1;
            i += 2;
            while (i < raw.len and depth > 0) {
                if (std.mem.startsWith(u8, raw[i..], "{{")) {
                    depth += 1;
                    i += 2;
                } else if (std.mem.startsWith(u8, raw[i..], "}}")) {
                    depth -= 1;
                    i += 2;
                } else i += 1;
            }
            o.append(' ') catch {};
            continue;
        }
        if (std.mem.startsWith(u8, rest, "[[")) { // link
            const close = std.mem.indexOf(u8, raw[i + 2 ..], "]]") orelse {
                i += 2;
                continue;
            };
            var inner = raw[i + 2 .. i + 2 + close];
            i = i + 2 + close + 2;
            if (istart(inner, "file:") or istart(inner, "image:") or istart(inner, "category:")) {
                o.append(' ') catch {};
                continue;
            }
            if (std.mem.lastIndexOfScalar(u8, inner, '|')) |bar| inner = inner[bar + 1 ..];
            o.appendSlice(inner) catch {};
            continue;
        }
        if (std.mem.startsWith(u8, rest, "<!--")) {
            const e = std.mem.indexOf(u8, raw[i..], "-->") orelse raw.len - i;
            i += e + @min(@as(usize, 3), raw.len - (i + e));
            continue;
        }
        if (istart(rest, "<ref")) {
            if (std.mem.indexOf(u8, raw[i..], "</ref>")) |e| {
                i += e + 6;
            } else if (std.mem.indexOfScalar(u8, raw[i..], '>')) |e| {
                i += e + 1;
            } else i = raw.len;
            o.append(' ') catch {};
            continue;
        }
        if (raw[i] == '<') { // any other tag
            const e = std.mem.indexOfScalar(u8, raw[i..], '>') orelse {
                i = raw.len;
                continue;
            };
            i += e + 1;
            continue;
        }
        if (std.mem.startsWith(u8, rest, "'''")) {
            i += 3;
            continue;
        }
        if (std.mem.startsWith(u8, rest, "''")) {
            i += 2;
            continue;
        }
        if (raw[i] == '(') { // drop parenthetical (pronunciation/etymology) so "Dog (..) is a Y" → "Dog is a Y"
            const e = std.mem.indexOfScalar(u8, raw[i..], ')') orelse {
                o.append(' ') catch {};
                i += 1;
                continue;
            };
            i += e + 1;
            o.append(' ') catch {};
            continue;
        }
        if (raw[i] == '&') { // entity
            if (std.mem.indexOfScalar(u8, raw[i .. @min(i + 10, raw.len)], ';')) |semi| {
                const ent = raw[i + 1 .. i + semi];
                const ch: ?u8 = if (std.mem.eql(u8, ent, "amp")) '&' else if (std.mem.eql(u8, ent, "lt")) '<' else if (std.mem.eql(u8, ent, "gt")) '>' else if (std.mem.eql(u8, ent, "quot")) '"' else if (std.mem.eql(u8, ent, "nbsp")) ' ' else null;
                if (ch) |c| {
                    o.append(c) catch {};
                    i += semi + 1;
                    continue;
                }
            }
        }
        if (raw[i] == '\'' or raw[i] == '[' or raw[i] == ']' or raw[i] == '{' or raw[i] == '}') {
            i += 1;
            continue;
        }
        o.append(raw[i]) catch {};
        i += 1;
    }
}

fn finishPage() void {
    defer reset();
    if (cap.items.len == 0) return;
    // lead = up to first blank line or section header
    var lead = cap.items;
    if (std.mem.indexOf(u8, lead, "\n\n")) |p| lead = lead[0..p];
    if (std.mem.indexOf(u8, lead, "\n=")) |p| lead = lead[0..p];
    const t = std.mem.trim(u8, lead, " \n\r\t");
    if (t.len == 0 or t[0] == '#') return; // redirect / empty
    seen += 1;
    var cleaned = std.ArrayList(u8).init(A);
    defer cleaned.deinit();
    clean(t, &cleaned);
    // collapse whitespace
    var sq = std.ArrayList(u8).init(A);
    defer sq.deinit();
    var sp = false;
    for (cleaned.items) |c| {
        if (c == ' ' or c == '\n' or c == '\t' or c == '\r') {
            if (!sp) sq.append(' ') catch {};
            sp = true;
        } else {
            sq.append(c) catch {};
            sp = false;
        }
    }
    var s = std.mem.trim(u8, sq.items, " ");
    // first sentence: first ". " after some content, capped
    if (s.len > 20) {
        var j: usize = 15;
        while (j < s.len and j < 300) : (j += 1) {
            if (s[j] == '.' and (j + 1 >= s.len or s[j + 1] == ' ')) {
                s = s[0 .. j + 1];
                break;
            }
        }
        if (s.len > 320) s = s[0..320];
    }
    if (s.len < 12 or std.mem.indexOfScalar(u8, s, ' ') == null) return;
    out.writer().writeAll(s) catch {};
    out.writer().writeByte('\n') catch {};
    emitted += 1;
}

fn processLine(line: []const u8) void {
    if (!in_text) {
        if (std.mem.indexOf(u8, line, "<page>") != null) reset();
        if (std.mem.indexOf(u8, line, "<title>")) |tp| {
            const s = tp + 7;
            if (std.mem.indexOf(u8, line[s..], "</title>")) |e| {
                const title = line[s .. s + e];
                if (std.mem.indexOfScalar(u8, title, ':') != null) skip_ns = true;
            }
        }
        if (std.mem.indexOf(u8, line, "<redirect ") != null) skip_ns = true;
        if (std.mem.indexOf(u8, line, "<text")) |tp| {
            if (skip_ns) return;
            const gt = std.mem.indexOfScalarPos(u8, line, tp, '>') orelse return;
            const content = line[gt + 1 ..];
            if (std.mem.indexOf(u8, content, "</text>")) |e| {
                appendCapped(content[0..e]);
                finishPage();
            } else {
                in_text = true;
                appendCapped(content);
            }
        }
    } else {
        if (std.mem.indexOf(u8, line, "</text>")) |e| {
            appendCapped(line[0..e]);
            finishPage();
        } else appendCapped(line);
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    A = arena.allocator();
    cap = std.ArrayList(u8).init(A);
    out = std.io.bufferedWriter(std.io.getStdOut().writer());

    var br = std.io.bufferedReaderSize(1 << 20, std.io.getStdIn().reader());
    const r = br.reader();
    var line = std.ArrayList(u8).init(A);
    defer line.deinit();
    while (true) {
        line.clearRetainingCapacity();
        r.streamUntilDelimiter(line.writer(), '\n', null) catch |e| {
            if (e == error.EndOfStream) {
                if (line.items.len > 0) processLine(line.items);
                break;
            }
            return e;
        };
        processLine(line.items);
    }
    try out.flush();
    std.debug.print("[wiki_extract] pages={d} emitted={d}\n", .{ seen, emitted });
}
