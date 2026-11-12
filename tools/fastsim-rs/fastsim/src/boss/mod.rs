//! Port of Bots/BossRuns.cs: `fastsim boss run|fair` (research/planner-review/07-bosses.md).
//! Each run starts in the portal into one boss room (score = 100 * tier) and ends when the bird
//! takes the boss exit (cleared) or dies.
//!   run:  --bots leaky,honest,expert-leaky,expert,beast,search --seeds 200 --tier 1 --jobs 4
//!   fair: the honest planner plays; at each new tell the bird keeps its old plan
//!         for R ticks (--react 0,20,40,60), then SurvivalSearch looks for a way
//!         through the told attack (up to 59 ticks past the next tell).
//! C# collects the results in a ConcurrentBag (any order); here they come back in work order
//! (rayon, global pool: --jobs), which only shows in the order of equal-count death causes.
use std::cmp::Ordering;
use std::time::Instant;

use rayon::prelude::*;
use sim::hazards::boss_crusher::Crate;
use sim::hazards::boss_watcher::Beam as WBeam;
use sim::hazards::boss_watcher::Dart as WDart;
use sim::prelude::*;

use crate::bots::boss_blind::BossBlind;
use crate::bots::{BlindPlanner, SurvivalSearch};
use crate::human::fmt_f;
use crate::human::motor_player::{MotorPlayer, MotorTiers};
use crate::speed::Opts;

pub mod check;

pub const BOSSES: [&str; 3] = ["boss_watcher", "boss_crusher", "boss_saw"];
const CAP: i64 = 3200;

type Decide = Box<dyn FnMut(&GameSim) -> bool>;

fn nl() -> &'static str {
    if cfg!(windows) {
        "\r\n"
    } else {
        "\n"
    }
}

/// C# `File.WriteAllLines` (Environment.NewLine after every line).
pub(crate) fn write_all_lines(path: &str, lines: &[String]) {
    let mut s = String::new();
    for l in lines {
        s.push_str(l);
        s.push_str(nl());
    }
    std::fs::write(path, s).unwrap_or_else(|e| panic!("{}: {}", path, e));
}

/// C# `s.Split(new[] { ',', ' ' }, StringSplitOptions.RemoveEmptyEntries)`.
fn split_list(s: &str) -> Vec<String> {
    s.split([',', ' ']).filter(|x| !x.is_empty()).map(|x| x.to_string()).collect()
}

pub fn arrive(boss: &str, seed: i64, tier: i64) -> GameSim {
    let mut sim = GameSim::new(seed);
    sim.step(true);
    sim.state.score = SimConfig::BOSS_EVERY * tier;
    let want = RoomCatalog::boss_bit(RoomCatalog::index_of(boss));
    sim.state.bosses_met = 7 & !want;
    let mut r = SimRng::new(seed * 31 + 7);
    sim._go_through(1, ExitKind::NORMAL, (200 + r.next_below(261)) * SimConfig::SUB);
    if sim.room.def().id != boss {
        panic!("wanted {}, got {}", boss, sim.room.def().id);
    }
    sim
}

/// C# `s.room.hazards.OfType<Boss>().FirstOrDefault()` (the hazard itself, so tell_key can
/// read the boss kind).
pub fn boss_of(s: &GameSim) -> Option<&Hz> {
    s.room.hazards.iter().find(|h| h.as_boss().is_some())
}

fn boss_b(s: &GameSim) -> Option<&Boss> {
    boss_of(s).and_then(|h| h.as_boss())
}

fn make(bot: &str, seed: i64) -> Decide {
    let honest = |blind: bool| -> BlindPlanner {
        let mut bp = BlindPlanner::new(seed);
        bp.horizon = 200;
        bp.past = 110;
        bp.margin = 10;
        bp.boss_leak = !blind;
        bp
    };
    let human = |tier: &str, blind: bool| -> MotorPlayer {
        let mut mp = MotorPlayer::new(MotorTiers::of(tier), seed, None);
        mp.planner.boss_leak = !blind;
        mp
    };
    fn bp(mut b: BlindPlanner) -> Decide {
        Box::new(move |s: &GameSim| b.decide(s))
    }
    fn mp(mut m: MotorPlayer) -> Decide {
        Box::new(move |s: &GameSim| m.decide(s))
    }
    match bot {
        "leaky" => bp(honest(false)),
        "honest" => bp(honest(true)),
        "expert-leaky" => mp(human("expert", false)),
        "expert" => mp(human("expert", true)),
        "beast-leaky" => mp(human("beast", false)),
        "beast" => mp(human("beast", true)),
        "good" => mp(human("good", true)),
        _ => panic!("unknown bot {}", bot),
    }
}

/// What killed the bird (state after the death step).
pub fn cause(s: &GameSim) -> &'static str {
    let dc = s.state.death_cause;
    if dc != DeathCause::HAZARD {
        return if dc == DeathCause::CEILING || dc == DeathCause::FLOOR { "edge" } else { "spikes" };
    }
    match boss_of(s) {
        Some(Hz::BossWatcher(w)) => {
            if w.dart == WDart::FLY {
                let back = if w.dart_side == 1 { w.dart_x + BossWatcher::DART_LEN } else { w.dart_x - BossWatcher::DART_LEN };
                if s.bird_touches_rect(
                    w.dart_x,
                    w.dart_lane - BossWatcher::DART_HALF,
                    back,
                    w.dart_lane + BossWatcher::DART_HALF,
                ) {
                    return "dart";
                }
            }
            "beam"
        }
        Some(Hz::BossCrusher(c)) => {
            if s.state.y - SimConfig::BIRD_RADIUS <= c.press_y + BossCrusher::BITE {
                return if c.boss.phase == 1 { "slam" } else { "press" };
            }
            if s.state.y + SimConfig::BIRD_RADIUS >= c.plate_y - BossCrusher::BITE {
                return "plate";
            }
            "crate"
        }
        Some(Hz::BossSaw(sw)) => {
            if s.bird_touches_circle(BossSaw::KING_X, sw.king_y, BossSaw::KING_R) {
                "king"
            } else {
                "blades"
            }
        }
        _ => "hazard",
    }
}

#[derive(Clone, Debug)]
pub struct Result {
    pub bot: String,
    pub boss: String,
    pub seed: i64,
    pub cleared: bool,
    pub points: i64,
    pub phase: i64,
    pub cause: String,
    pub tick: i64,
}

fn res(bot: &str, boss: &str, seed: i64, cleared: bool, points: i64, phase: i64, cause: &str, tick: i64) -> Result {
    Result {
        bot: bot.to_string(),
        boss: boss.to_string(),
        seed,
        cleared,
        points,
        phase,
        cause: cause.to_string(),
        tick,
    }
}

pub fn play(bot: &str, boss: &str, seed: i64, tier: i64) -> Result {
    let mut sim = arrive(boss, seed, tier);
    let room = sim.state.room_index;
    let start = sim.state.score;
    if bot == "search" {
        let mut ss = SurvivalSearch::new();
        // The room is beaten once the boss is down (the exit opens on the wall ahead).
        let ok = ss.run(&sim, 2100);
        let e = ss.best.as_ref();
        let cl = match e {
            Some(e) => e.state.room_index > room || boss_b(e).map(|b| b.down_at).unwrap_or(-1) >= 0,
            None => false,
        };
        let points = if cl { SimConfig::BOSS_POINTS } else { e.map(|e| e.room.points).unwrap_or(0) };
        let phase = if cl { 0 } else { e.and_then(boss_b).map(|b| b.phase).unwrap_or(0) };
        let why = if cl {
            ""
        } else if ok {
            "cap"
        } else {
            "search"
        };
        return res(bot, boss, seed, cl, points, phase, why, ss.ticks_survived);
    }
    let mut d = make(bot, seed);
    for t in 0..CAP {
        let phase = boss_b(&sim).expect("a boss").phase;
        let tap = d(&sim);
        sim.step(tap);
        if sim.state.room_index > room {
            return res(bot, boss, seed, true, SimConfig::BOSS_POINTS, 0, "", t);
        }
        if sim.is_over() {
            return res(bot, boss, seed, false, sim.state.score - start, phase, cause(&sim), t);
        }
    }
    let phase = boss_b(&sim).expect("a boss").phase;
    res(bot, boss, seed, false, sim.state.score - start, phase, "cap", CAP)
}

pub fn run(pos: &[String], opts: &Opts) -> i32 {
    let pos = if pos.first().map(|s| s.as_str()) == Some("boss") { &pos[1..] } else { pos };
    let what = pos.first().map(|s| s.as_str()).unwrap_or("run");
    let o_ = |k: &str, d: &str| -> String { opts.get(k).cloned().unwrap_or_else(|| d.to_string()) };
    let seeds: i32 = o_("seeds", "100").parse().expect("--seeds");
    let first: i64 = o_("first", "1").parse().expect("--first");
    let tier: i64 = o_("tier", "1").parse().expect("--tier");
    let bosses: Vec<String> = if o_("boss", "all") == "all" {
        BOSSES.iter().map(|s| s.to_string()).collect()
    } else {
        split_list(&opts["boss"])
    };
    if what == "fair" {
        return fair(&bosses, seeds, first, tier, opts);
    }
    let bots = split_list(&o_("bots", "leaky,honest,expert-leaky,expert"));
    let mut work: Vec<(String, String, i64)> = Vec::new();
    for b in &bots {
        for bo in &bosses {
            for s in 0..seeds as i64 {
                work.push((b.clone(), bo.clone(), first + s));
            }
        }
    }
    let clock = Instant::now();
    let res: Vec<Result> = work.par_iter().map(|w| play(&w.0, &w.1, w.2, tier)).collect();
    println!(
        "boss run: tier {}, seeds {}..{}, {} s",
        tier,
        first,
        first + seeds as i64 - 1,
        fmt_f(clock.elapsed().as_secs_f64(), 0)
    );
    println!(
        "{:<13} {:<13} {:>6} {:>7} {:>7} {:>7} {:>5}  causes",
        "bot", "boss", "clear", "p1 die", "p2 die", "p3 die", "pts"
    );
    for b in &bots {
        for bo in &bosses {
            let rs: Vec<&Result> = res.iter().filter(|r| &r.bot == b && &r.boss == bo).collect();
            let n = rs.len();
            let pct = |k: usize| format!("{:>5}%", fmt_f(100.0 * k as f64 / n as f64, 1));
            let dead: Vec<&Result> = rs.iter().copied().filter(|r| !r.cleared).collect();
            // Death rate per phase among birds that reached it.
            let ph = |p: i64| -> String {
                let reach = rs.iter().filter(|r| r.cleared || r.phase >= p).count();
                let died = dead.iter().filter(|r| r.phase == p).count();
                if reach == 0 {
                    "   -".to_string()
                } else {
                    format!("{:>6}%", fmt_f(100.0 * died as f64 / reach as f64, 1))
                }
            };
            let causes: Vec<String> = crate::human::group_count(dead.iter().map(|r| r.cause.clone()))
                .into_iter()
                .map(|(k, c)| format!("{}:{}", k, c))
                .collect();
            // Enumerable.Average over longs: a long sum, then one division.
            let sum: i64 = rs.iter().map(|r| r.points).sum();
            let avg = sum as f64 / n as f64;
            println!(
                "{:<13} {:<13} {} {} {} {} {:>5}  {}",
                b,
                bo,
                pct(rs.iter().filter(|r| r.cleared).count()),
                ph(1),
                ph(2),
                ph(3),
                fmt_f(avg, 1),
                causes.join(" ")
            );
        }
    }
    if let Some(path) = opts.get("out") {
        let mut sorted: Vec<&Result> = res.iter().collect();
        sorted.sort_by(|a, b| {
            a.bot.cmp(&b.bot).then_with(|| a.boss.cmp(&b.boss)).then(a.seed.cmp(&b.seed))
        });
        let lines: Vec<String> = sorted
            .iter()
            .map(|r| {
                format!(
                    "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
                    r.bot,
                    r.boss,
                    r.seed,
                    if r.cleared { 1 } else { 0 },
                    r.points,
                    r.phase,
                    r.cause,
                    r.tick
                )
            })
            .collect();
        write_all_lines(path, &lines);
    }
    0
}

struct Tell {
    tick: i64,
    phase: i64,
    kind: &'static str,
    sim: GameSim,
    plan: Vec<u8>,
}

#[derive(Clone, Debug)]
pub struct FairRow {
    pub boss: String,
    pub seed: i64,
    pub tick: i64,
    pub phase: i64,
    pub kind: &'static str,
    pub react: i64,
    pub verdict: i32,
    pub y: i64,
}

fn tell_kind(hz: &Hz) -> &'static str {
    match hz {
        Hz::BossWatcher(w) => {
            if w.dart == WDart::MARK {
                "dart"
            } else if w.beam == WBeam::WARN {
                "rows"
            } else {
                "other"
            }
        }
        Hz::BossCrusher(c) => {
            if c.crate_.iter().any(|&x| x == Crate::MARK) {
                "crate"
            } else if c.telling {
                if c.boss.phase == 1 {
                    "slam"
                } else {
                    "jaw"
                }
            } else {
                "other"
            }
        }
        Hz::BossSaw(s) => {
            if s.telling {
                if s.boss.phase == 2 {
                    "ring"
                } else {
                    "hop"
                }
            } else {
                "other"
            }
        }
        _ => "other",
    }
}

/// One boss room on one seed: a row per (tell, reaction) with its verdict
/// (1 = a way through, 0 = no way after the reaction, -1/-2 = the old plan
/// dies within the reaction, by the boss / by the edge or spikes).
pub fn fair_rows(boss: &str, seed: i64, tier: i64, reacts: &[i64]) -> Vec<FairRow> {
    let mut rows = Vec::new();
    let mut sim = arrive(boss, seed, tier);
    let room = sim.state.room_index;
    let mut bp = BlindPlanner::new(seed);
    bp.horizon = 200;
    bp.past = 110;
    bp.margin = 10;
    let mut tells: Vec<Tell> = Vec::new();
    let mut key = BossBlind::tell_key(boss_of(&sim).expect("a boss"));
    let mut t = 0;
    while t < CAP && !sim.is_over() && sim.state.room_index == room {
        let tap = bp.decide(&sim);
        sim.step(tap);
        if sim.is_over() || sim.state.room_index != room {
            break;
        }
        let hz = boss_of(&sim).expect("a boss");
        let b = hz.as_boss().expect("a boss");
        let k = BossBlind::tell_key(hz);
        if k != key && b.down_at < 0 {
            let kind = tell_kind(hz);
            if kind != "other" {
                let phase = b.phase;
                let plan: Vec<u8> = bp.plan().iter().map(|&x| if x { 1 } else { 0 }).collect();
                tells.push(Tell { tick: sim.state.tick, phase, kind, sim: sim.clone_deep(), plan });
            }
        }
        key = k;
        t += 1;
    }
    for i in 0..tells.len() {
        let tl = &tells[i];
        let next = if i + 1 < tells.len() { tells[i + 1].tick } else { tl.tick + 240 };
        for &r in reacts {
            let mut c = tl.sim.clone_deep();
            let mut verdict = 1;
            let mut u = 0;
            while u < r && verdict == 1 {
                c.step((u as usize) < tl.plan.len() && tl.plan[u as usize] != 0);
                if c.is_over() {
                    verdict = if c.state.death_cause == DeathCause::HAZARD { -1 } else { -2 };
                }
                u += 1;
            }
            if verdict == 1 {
                let h = G::maxi(30, next + 59 - (tl.tick + r));
                let mut ss = SurvivalSearch::new();
                if !ss.run(&c, h) {
                    verdict = 0;
                }
            }
            rows.push(FairRow {
                boss: boss.to_string(),
                seed,
                tick: tl.tick,
                phase: tl.phase,
                kind: tl.kind,
                react: r,
                verdict,
                y: tl.sim.state.y / SimConfig::SUB,
            });
        }
    }
    rows
}

fn fair(bosses: &[String], seeds: i32, first: i64, tier: i64, opts: &Opts) -> i32 {
    let reacts: Vec<i64> = split_list(opts.get("react").map(|s| s.as_str()).unwrap_or("0,20,40,60"))
        .iter()
        .map(|x| x.parse().expect("--react"))
        .collect();
    let mut work: Vec<(String, i64)> = Vec::new();
    for bo in bosses {
        for s in 0..seeds as i64 {
            work.push((bo.clone(), first + s));
        }
    }
    let clock = Instant::now();
    let rows: Vec<FairRow> = work.par_iter().map(|w| fair_rows(&w.0, w.1, tier, &reacts)).collect::<Vec<_>>().concat();
    println!(
        "boss fair: tier {}, seeds {}..{}, {} s",
        tier,
        first,
        first + seeds as i64 - 1,
        fmt_f(clock.elapsed().as_secs_f64(), 0)
    );
    println!("verdict per tell: no way = SurvivalSearch finds no line after the reaction; dead in react = the old plan hits the boss within the reaction");
    let heads: Vec<String> = reacts.iter().map(|r| format!("R={:<2} noway/deadR", r)).collect();
    println!("{:<13} {:<6} {:>3} {:>5}  {}", "boss", "tell", "ph", "n", heads.join("  "));
    // GroupBy (boss, kind, phase), ordered by boss, phase, kind.
    let mut keys: Vec<(String, &'static str, i64)> = Vec::new();
    for x in &rows {
        let k = (x.boss.clone(), x.kind, x.phase);
        if !keys.contains(&k) {
            keys.push(k);
        }
    }
    keys.sort_by(|a, b| -> Ordering { a.0.cmp(&b.0).then(a.2.cmp(&b.2)).then_with(|| a.1.cmp(b.1)) });
    for k in &keys {
        let g: Vec<&FairRow> = rows.iter().filter(|x| x.boss == k.0 && x.kind == k.1 && x.phase == k.2).collect();
        let n = g.iter().filter(|x| x.react == reacts[0]).count();
        let cells: Vec<String> = reacts
            .iter()
            .map(|&r| {
                let rr: Vec<&&FairRow> = g.iter().filter(|x| x.react == r).collect();
                let noway = rr.iter().filter(|x| x.verdict == 0).count();
                let dead = rr.iter().filter(|x| x.verdict < 0).count();
                format!(
                    "{:>5}%/{:>4}%",
                    fmt_f(100.0 * noway as f64 / n as f64, 1),
                    fmt_f(100.0 * dead as f64 / n as f64, 1)
                )
            })
            .collect();
        println!("{:<13} {:<6} {:>3} {:>5}  {}", k.0, k.1, k.2, n, cells.join("  "));
    }
    if let Some(path) = opts.get("out") {
        let mut sorted: Vec<&FairRow> = rows.iter().collect();
        sorted.sort_by(|a, b| {
            a.boss.cmp(&b.boss).then(a.seed.cmp(&b.seed)).then(a.tick.cmp(&b.tick)).then(a.react.cmp(&b.react))
        });
        let lines: Vec<String> = sorted
            .iter()
            .map(|r| {
                format!("{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}", r.boss, r.seed, r.tick, r.phase, r.kind, r.react, r.verdict, r.y)
            })
            .collect();
        write_all_lines(path, &lines);
    }
    0
}
