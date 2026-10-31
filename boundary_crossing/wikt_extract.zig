//! wikt_extract.zig — STREAM enwiktionary pages-articles XML on stdin; for each entry emit a synthesized
//! definitional sentence "<headword> is <first English-noun gloss>" on stdout. Wiktionary glosses live as
//! "# A mammal ..." lines under ==English== / ===Noun===; prepending "<headword> is " turns them into the same
//! copula form the funnel pipeline already discovers — so Wiktionary becomes a third INDEPENDENT witness with
//! the identical extraction method. No hoarding. Pipeline: curl <wikt>.bz2 | bzip2 -d | wikt_extract > defs.txt
const std = @import("std");
var A: std.mem.Allocator = undefined;
var out: std.io.BufferedWriter(4096, std.fs.File.Writer) = undefined;

var title: []const u8 = "";
var skip_ns = false;
var english = false;
var noun = false;
var emitted = false;
var gcount: usize = 0;
var seen: usize = 0;
var nemit: usize = 0;

fn lc(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}
fn istart(h: []const u8, n: []const u8) bool {
    return h.len >= n.len and std.ascii.eqlIgnoreCase(h[0..n.len], n);
}

// crude wikitext → text (same spirit as wiki_extract): strip templates/links/refs/markup/parentheticals
fn clean(raw: []const u8, o: *std.ArrayList(u8)) void {
    var i: usize = 0;
    while (i < raw.len) {
        const rest = raw[i..];
        if (std.mem.startsWith(u8, rest, "{{")) {
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
        if (std.mem.startsWith(u8, rest, "[[")) {
            const close = std.mem.indexOf(u8, raw[i + 2 ..], "]]") orelse {
                i += 2;
                continue;
            };
            var inner = raw[i + 2 .. i + 2 + close];
            i = i + 2 + close + 2;
            if (istart(inner, "file:") or istart(inner, "image:") or istart(inner, "category:") or istart(inner, "w:")) {
                o.append(' ') catch {};
                continue;
            }
            if (std.mem.lastIndexOfScalar(u8, inner, '|')) |bar| inner = inner[bar + 1 ..];
            o.appendSlice(inner) catch {};
            continue;
        }
        if (raw[i] == '<') {
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
        if (raw[i] == '(') {
            const e = std.mem.indexOfScalar(u8, raw[i..], ')') orelse {
                o.append(' ') catch {};
                i += 1;
                continue;
            };
            i += e + 1;
            o.append(' ') catch {};
            continue;
        }
        if (raw[i] == '&') {
            if (std.mem.indexOfScalar(u8, raw[i .. @min(i + 10, raw.len)], ';')) |semi| {
                const ent = raw[i + 1 .. i + semi];
                const ch: ?u8 = if (std.mem.eql(u8, ent, "amp")) '&' else if (std.mem.eql(u8, ent, "lt")) '<' else if (std.mem.eql(u8, ent, "gt")) '>' else if (std.mem.eql(u8, ent, "quot")) '"' else if (std.mem.eql(u8, ent, "nbsp")) ' ' else null;
                if (ch) |cc| {
                    o.append(cc) catch {};
                    i += semi + 1;
                    continue;
                }
            }
        }
        if (raw[i] == '\'' or raw[i] == '[' or raw[i] == ']' or raw[i] == '{' or raw[i] == '}' or raw[i] == '#' or raw[i] == '*') {
            i += 1;
            continue;
        }
        o.append(raw[i]) catch {};
        i += 1;
    }
}

fn emitGloss(gloss_raw: []const u8) void {
    if (title.len == 0) return;
    var cleaned = std.ArrayList(u8).init(A);
    defer cleaned.deinit();
    clean(gloss_raw, &cleaned);
    // collapse whitespace
    var sq = std.ArrayList(u8).init(A);
    defer sq.deinit();
    var sp = true;
    for (cleaned.items) |c| {
        if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
            if (!sp) sq.append(' ') catch {};
            sp = true;
        } else {
            sq.append(c) catch {};
            sp = false;
        }
    }
    var s = std.mem.trim(u8, sq.items, " ");
    // first sentence, capped
    if (s.len > 12) {
        var j: usize = 6;
        while (j < s.len and j < 220) : (j += 1) if (s[j] == '.' and (j + 1 >= s.len or s[j + 1] == ' ')) {
            s = s[0 .. j + 1];
            break;
        };
        if (s.len > 240) s = s[0..240];
    }
    if (s.len < 4 or std.mem.indexOfScalar(u8, s, ' ') == null) return;
    out.writer().print("{s} is {s}\n", .{ title, s }) catch {};
    nemit += 1;
    emitted = true; gcount += 1;
}

fn processLine(line: []const u8) void {
    if (std.mem.indexOf(u8, line, "<page>") != null) {
        skip_ns = false;
        english = false;
        noun = false;
        emitted = false;
        gcount = 0;
        title = "";
    }
    if (std.mem.indexOf(u8, line, "<title>")) |tp| {
        const s = tp + 7;
        if (std.mem.indexOf(u8, line[s..], "</title>")) |e| {
            const tt = line[s .. s + e];
            skip_ns = std.mem.indexOfScalar(u8, tt, ':') != null;
            title = A.dupe(u8, tt) catch "";
            if (!skip_ns) seen += 1;
        }
    }
    if (skip_ns or gcount >= 6) return;
    // strip a leading "<text ...>" tag so headers glued to it (Wiktionary does "<text ...>==English==") are seen
    var work = line;
    if (std.mem.indexOf(u8, line, "<text")) |tp| {
        if (std.mem.indexOfScalarPos(u8, line, tp, '>')) |gt| work = line[gt + 1 ..];
    }
    const t = std.mem.trim(u8, work, " \r");
    // language / POS headers
    if (std.mem.startsWith(u8, t, "===")) { // level-3+ POS header
        noun = std.mem.indexOf(u8, t, "Noun") != null;
        return;
    }
    if (std.mem.startsWith(u8, t, "==")) { // level-2 language header
        english = std.mem.indexOf(u8, t, "English") != null;
        noun = false;
        return;
    }
    // a gloss line: "# ..." but not "#:" (example) / "#*" (quote) / "##" (subsense)
    if (english and noun and t.len >= 3 and t[0] == '#' and t[1] != ':' and t[1] != '*' and t[1] != '#') {
        emitGloss(t[1..]);
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    A = arena.allocator();
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
    std.debug.print("[wikt_extract] english entries={d} emitted={d}\n", .{ seen, nemit });
}
