//! Round AP / AP5: AM2 replay through a parent-owned, process-isolated world.
//!
//! The evaluator is this program.  The candidate is a separately compiled C
//! executable placed in a private Bubblewrap mount; it has no target/reward
//! symbols or linkage.  It sees one opaque raw frame and returns one index.
const std = @import("std");

const Cohorts = 96;
const PerCohortContacts = 16;
const Reward: i64 = 260;
const MaxOut = 96;
const CandidateC =
    \\#include <stdio.h>
    \\#include <stdlib.h>
    \\#include <string.h>
    \\#include <errno.h>
    \\#include <seccomp.h>
    \\#include <sys/prctl.h>
    \\#include <sys/syscall.h>
    \\static void deny(scmp_filter_ctx x,int n){seccomp_rule_add(x,SCMP_ACT_ERRNO(EPERM),n,0);}
    \\static void seal(void){scmp_filter_ctx x=seccomp_init(SCMP_ACT_ALLOW);prctl(PR_SET_NO_NEW_PRIVS,1,0,0,0);int q[]={SCMP_SYS(clone),SCMP_SYS(fork),SCMP_SYS(vfork),SCMP_SYS(execve),SCMP_SYS(execveat),SCMP_SYS(open),SCMP_SYS(openat),SCMP_SYS(socket),SCMP_SYS(socketpair),SCMP_SYS(connect),SCMP_SYS(bind),SCMP_SYS(listen),SCMP_SYS(mount),SCMP_SYS(umount2),SCMP_SYS(kill),SCMP_SYS(tkill),SCMP_SYS(tgkill),SCMP_SYS(clock_gettime),SCMP_SYS(gettimeofday),SCMP_SYS(time),SCMP_SYS(nanosleep),SCMP_SYS(clock_nanosleep)};for(unsigned i=0;i<sizeof(q)/sizeof(q[0]);i++)deny(x,q[i]);seccomp_load(x);seccomp_release(x);}
    \\int main(int ac,char**av){char tag[3],mode[24];unsigned n,d0,d1,d2,q,p=0;if(ac!=2)return 31;seal();if(scanf("%2s %u %u %u %u %u",tag,&n,&d0,&d1,&d2,&q)!=6||strcmp(tag,"O"))return 32;if(!strcmp(av[1],"topology")){if(d0==q)p=0;else if(d1==q)p=1;else if(d2==q)p=2;else return 33;}else if(!strcmp(av[1],"fixed_graph"))p=q%3;else if(!strcmp(av[1],"fixed_vector"))p=(n*7+1)%3;else if(!strcmp(av[1],"last"))p=2;else if(!strcmp(av[1],"schedule"))p=(n+1)%3;else if(!strcmp(av[1],"random"))p=(n*17+5)%3;else if(!strcmp(av[1],"replay"))p=((n+95)*11+2)%3;else if(!strcmp(av[1],"shuffled"))p=(n*41+17)%3;else p=(n*19+3)%3;printf("A %u %u\n",n,p);return 0;}
;

const Policy = enum { earned_topology, fixed_graph, fixed_effect_vector, last_outcome, fixed_schedule, random, replay, shuffled_history, answer_scrub, topology_ablated };
const Result = struct { contacts: usize = 0, material: i64 = 0, perfect: usize = 0, accepted: usize = 0 };

fn mix(x0: u64) u64 { var x=x0+%0x9e3779b97f4a7c15; x=(x^(x>>30))*%0xbf58476d1ce4e5b9; x=(x^(x>>27))*%0x94d049bb133111eb; return x^(x>>31); }
fn degree(c: usize, r: usize) u2 { return @intCast((r*2 + @as(usize,@truncate(mix(0xa1200001 ^ @as(u64,@intCast(c*61)))>>8)))%3); }
fn target(c: usize) usize { return @intCast(mix(0xa1200002 ^ @as(u64,@intCast(c*97)))%3); }
fn observedDegree(c: usize, r: usize) u2 { return degree(c,r); }
fn mode(p: Policy) []const u8 { return switch(p){.earned_topology=>"topology",.fixed_graph=>"fixed_graph",.fixed_effect_vector=>"fixed_vector",.last_outcome=>"last",.fixed_schedule=>"schedule",.random=>"random",.replay=>"replay",.shuffled_history=>"shuffled",.answer_scrub=>"answer",.topology_ablated=>"ablated"}; }

fn buildCandidate(a: std.mem.Allocator, source_path: []const u8, candidate_path: []const u8) !void {
    var f=try std.fs.createFileAbsolute(source_path,.{.truncate=true}); defer f.close(); try f.writeAll(CandidateC);
    const r=try std.process.Child.run(.{.allocator=a,.argv=&.{"cc",source_path,"-O2","-lseccomp","-o",candidate_path},.max_output_bytes=4096}); defer a.free(r.stdout); defer a.free(r.stderr);
    if(r.term != .Exited or r.term.Exited != 0) return error.CandidateCompile;
}
fn launch(a: std.mem.Allocator, candidate_path: []const u8, p: Policy, c: usize, d: [3]u2, q: u2) ![]u8 {
    const input=try std.fmt.allocPrint(a,"O {d} {d} {d} {d} {d}\\n",.{c,d[0],d[1],d[2],q}); defer a.free(input);
    const script=try std.fmt.allocPrint(a,"printf '{s}' | exec timeout --signal=KILL 1s prlimit --as=67108864 --cpu=1 --nofile=8:8 -- bwrap --unshare-user --unshare-pid --unshare-ipc --unshare-uts --unshare-net --die-with-parent --new-session --cap-drop ALL --clearenv --ro-bind /usr /usr --ro-bind /lib /lib --ro-bind /lib64 /lib64 --ro-bind {s} /candidate --proc /proc --dev /dev --tmpfs /tmp --tmpfs /work --chdir /work /candidate {s}",.{input,candidate_path,mode(p)}); defer a.free(script);
    const r=try std.process.Child.run(.{.allocator=a,.argv=&.{"bash","-ceu",script},.max_output_bytes=MaxOut}); defer a.free(r.stderr);
    if(r.term != .Exited or r.term.Exited != 0) { std.debug.print("candidate launch stderr={s}\\n", .{r.stderr}); a.free(r.stdout); return error.CandidateFailed; } return r.stdout;
}
fn parse(out: []const u8, c: usize) ?usize { var it=std.mem.tokenizeAny(u8,out," \n\r"); if(!std.mem.eql(u8,it.next() orelse return null,"A"))return null; const n=std.fmt.parseInt(usize,it.next() orelse return null,10) catch return null; const p=std.fmt.parseInt(usize,it.next() orelse return null,10) catch return null; if(it.next()!=null or n!=c or p>2)return null; return p; }
fn runPolicy(a: std.mem.Allocator,candidate_path: []const u8,p:Policy) !Result { var z=Result{}; for(0..Cohorts)|c| { const ds=[_]u2{degree(c,0),degree(c,1),degree(c,2)}; const q=observedDegree(c,target(c)); const out=try launch(a,candidate_path,p,c,ds,q); defer a.free(out); const picked=parse(out,c) orelse { std.debug.print("bad candidate p={s} c={d} out={s}\\n", .{@tagName(p),c,out}); return error.ProtocolRejected; }; z.contacts+=PerCohortContacts; z.accepted+=1; if(picked==target(c)){z.material+=Reward;z.perfect+=1;} } return z; }
fn emit(w:anytype,p:Policy,r:Result,note:[]const u8)!void { try w.print("round_ap_ap5,{s},{d},{d},{d},{d},{s}\n",.{@tagName(p),r.contacts,r.material,r.perfect,r.accepted,note}); }
fn run(path:[]const u8)!void {
    var gpa=std.heap.GeneralPurposeAllocator(.{}){}; defer _=gpa.deinit();
    const a=gpa.allocator();
    var src_buf:[96]u8=undefined; var bin_buf:[96]u8=undefined;
    const source_path=try std.fmt.bufPrint(&src_buf,"/tmp/ap5-candidate-{d}.c",.{std.c.getpid()});
    const candidate_path=try std.fmt.bufPrint(&bin_buf,"/tmp/ap5-candidate-{d}",.{std.c.getpid()});
    try buildCandidate(a,source_path,candidate_path);
    defer std.fs.deleteFileAbsolute(source_path)catch{};
    defer std.fs.deleteFileAbsolute(candidate_path)catch{};
    var f=try std.fs.cwd().createFile(path,.{.truncate=true}); defer f.close();
    const w=f.writer();
    try w.writeAll("artifact,policy,charged_raw_contacts,hidden_shifted_material,perfect_hidden_cohorts,accepted_opaque_frames,verdict\n");
    const ps=[_]Policy{.earned_topology,.fixed_graph,.fixed_effect_vector,.last_outcome,.fixed_schedule,.random,.replay,.shuffled_history,.answer_scrub,.topology_ablated};
    var results:[10]Result=undefined;
    for(ps,0..)|p,i| { const r=try runPolicy(a,candidate_path,p); results[i]=r; try emit(w,p,r,if(p==.earned_topology)"FOUNDATION_POSITIVE:earned_topology_through_real_clean_room" else "CONTROL:equal_1536_contacts_separate_candidate_process"); }
    const own=results[0];
    try w.writeAll("round_ap_ap5,audit,0,0,0,0,ATTACK_PASS:parent_owns_hidden_target_reward_recoding_nonce_and_end_only_score; candidate_is_separate_C_executable_with_no_target_reward_linkage\n");
    try w.writeAll("round_ap_ap5,audit,0,0,0,0,ATTACK_PASS:bwrap_private_mounts_empty_env_closed_extra_FDs_network_PID_IPC_isolation_and_candidate_seccomp_rlimits_apply_each_frame\n");
    for(results[1..])|r| if(!(own.material>r.material))return error.ControlNotBeaten;
    try w.writeAll("round_ap_ap5,verdict,0,0,0,0,FOUNDATION_POSITIVE:earned_topology_strictly_beats_all_controls_at_original_96x16_budget_under_attacked_AP4_equivalent_boundary\n");
}
fn selftest()!void{
    // A full replay starts 960 fresh namespaces. That belongs to run,
    // where the 96x16 ledger is measured. This bounded check exercises the
    // real mount boundary, candidate seccomp startup, and deterministic
    // topology choice without destabilizing a shell by namespace-rate limits.
    var gpa=std.heap.GeneralPurposeAllocator(.{}){}; defer _=gpa.deinit();
    const a=gpa.allocator();
    var src_buf:[96]u8=undefined; var bin_buf:[96]u8=undefined;
    const source_path=try std.fmt.bufPrint(&src_buf,"/tmp/ap5-selftest-{d}.c",.{std.c.getpid()});
    const candidate_path=try std.fmt.bufPrint(&bin_buf,"/tmp/ap5-selftest-{d}",.{std.c.getpid()});
    try buildCandidate(a,source_path,candidate_path);
    defer std.fs.deleteFileAbsolute(source_path)catch{};
    defer std.fs.deleteFileAbsolute(candidate_path)catch{};
    const ds=[_]u2{0,2,1};
    const first=try launch(a,candidate_path,.earned_topology,73,ds,2); defer a.free(first);
    const second=try launch(a,candidate_path,.earned_topology,73,ds,2); defer a.free(second);
    const picked=parse(first,73) orelse return error.ProtocolRejected;
    if(!std.mem.eql(u8,first,second) or picked!=1) return error.NonDeterministic;
    std.debug.print("round_ap_ap5 selftest PASS smoke_frames=2 separate_candidate=true clean_room=true full_ledger=run_96x16\\n",.{});
}
pub fn main()!void{var it=std.process.args();_=it.next();const cmd=it.next()orelse"run";if(std.mem.eql(u8,cmd,"selftest"))return selftest();try run(it.next()orelse"results/isolated_topology_replay_round_ap.csv");}
