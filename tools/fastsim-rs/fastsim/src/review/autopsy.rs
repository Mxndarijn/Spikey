//! Port of RL/Autopsy.cs: `rl review autopsy` (the death atlas plus, for every death,
//! what the planner's own copy expected against what happened), `fixtest`,
//! `exposure` and `bouncefair`. See the C# file for the columns.
use std::collections::VecDeque;
use std::io::Write;
use std::path::Path;
use std::sync::Mutex;
use std::time::Instant;

use rayon::prelude::*;
use sim::prelude::*;

use super::{configure, dbl, hz_name, pct, room_name, NL};
use crate::bots::{BlindPlanner, SurvivalSearch};
use crate::speed::Opts;
use crate::yardstick::fmt_num;

const BACK: i64 = 900;
const AFTER: i64 = 240;
const LEAD: i64 = 45;
const KEEP: i64 = 1100;
const RESCUES: i32 = 8;

#[derive(Clone)]
struct Look {
    tick: i64,
    seed0: i64,
    plan: Vec<bool>,
    kind: i32,
    agree: i32,
    anchor: i64,
}

fn l(opts: &Opts, k: &str, d: i64) -> i64 {
    opts.get(k).map(|v| v.parse().expect(k)).unwrap_or(d)
}

fn taps_file(dir: &str, seed: i64) -> std::path::PathBuf {
    Path::new(dir).join(format!("{seed}.taps"))
}

pub fn run(opts: &Opts, seeds: i32, cap: i64) -> i32 {
    let first = l(opts, "first", 0);
    let out_path = opts.get("out").cloned().unwrap_or_else(|| "autopsy.tsv".to_string());
    let taps_dir = opts.get("taps").cloned().unwrap_or_default();
    if !taps_dir.is_empty() {
        std::fs::create_dir_all(&taps_dir).expect("--taps");
    }
    let clock = Instant::now();
    let partial = format!("{out_path}.partial");
    std::fs::write(&partial, "").expect("partial");
    // C# `lock (gate)`: the done count and the partial file.
    let gate = Mutex::new(0usize);
    let outs: Vec<(String, Option<String>, i64, bool)> = (0..seeds as i64)
        .into_par_iter()
        .map(|i| {
            let seed = first + i + 1;
            let mut sim = GameSim::new(seed);
            let mut bot = BlindPlanner::new(seed);
            let cfg = configure(&mut bot, opts);
            let mut taps: Vec<bool> = Vec::new();
            let mut looks: VecDeque<Look> = VecDeque::new();
            let (mut bounce_tick, mut entry_tick, mut last_looks) = (0i64, 0i64, 0i64);
            while !sim.is_over() && (taps.len() as i64) < cap {
                let tick = taps.len() as i64;
                let tap = bot.decide(&sim);
                if bot.looks != last_looks {
                    last_looks = bot.looks;
                    looks.push_back(Look {
                        tick,
                        seed0: bot.last_seed0,
                        plan: bot.last_plan.clone(),
                        kind: bot.last_look,
                        agree: bot.last_agree,
                        anchor: bot.last_anchor,
                    });
                    while looks.front().unwrap().tick < tick - KEEP {
                        looks.pop_front();
                    }
                }
                taps.push(tap);
                let (vx, ri) = (sim.state.vx, sim.state.room_index);
                sim.step(tap);
                if sim.state.vx != vx {
                    bounce_tick = taps.len() as i64;
                }
                if sim.state.room_index != ri {
                    entry_tick = taps.len() as i64;
                }
            }
            if !taps_dir.is_empty() {
                let bytes: Vec<u8> = taps.iter().map(|&b| b as u8).collect();
                std::fs::write(taps_file(&taps_dir, seed), bytes).expect("taps file");
            }
            let row = if sim.is_over() {
                let lv: Vec<Look> = looks.into_iter().collect();
                Some(autopsy(seed, &sim, &taps, &lv, bounce_tick, entry_tick, opts))
            } else {
                None
            };
            {
                let mut done = gate.lock().unwrap();
                *done += 1;
                let text = row.clone().unwrap_or_else(|| format!("{seed}\t{}\t{}\talive", sim.state.score, taps.len()));
                let mut f = std::fs::OpenOptions::new().append(true).open(&partial).expect("partial");
                f.write_all(format!("{text}\n").as_bytes()).expect("partial");
                eprintln!(
                    "[{}/{seeds}] seed {seed}: {} {} ({} min)",
                    *done,
                    sim.state.score,
                    if sim.is_over() { "dead" } else { "alive" },
                    fmt_num(clock.elapsed().as_secs_f64() / 60.0, "F0")
                );
            }
            (cfg, row, sim.state.score, sim.is_over())
        })
        .collect();
    let setup = outs.first().map(|o| o.0.clone()).unwrap_or_default();
    let pts: i64 = outs.iter().map(|o| o.2).sum();
    let deaths = outs.iter().filter(|o| o.3).count();
    let points: Vec<i64> = outs.iter().map(|o| o.2).collect();
    let mut sb = String::new();
    sb.push_str(&format!(
        "# autopsy, blind planner [{setup}], seeds {}..{}, cap {cap}, gameplay {}{NL}",
        first + 1,
        first + seeds as i64,
        SimConfig::GAMEPLAY_VERSION
    ));
    sb.push_str(&format!(
        "# {deaths} deaths in {pts} points = {} per 100; {} of {seeds} alive at the cap; median {}; {} s{NL}",
        fmt_num(100.0 * deaths as f64 / pts.max(1) as f64, "F3"),
        outs.iter().filter(|o| !o.3).count(),
        dbl(pct(&points, 0.5)),
        fmt_num(clock.elapsed().as_secs_f64(), "F0")
    ));
    sb.push_str(HEADER);
    sb.push_str(NL);
    for o in &outs {
        if let Some(r) = &o.1 {
            sb.push_str(r);
            sb.push_str(NL);
        }
    }
    std::fs::write(&out_path, &sb).expect("--out");
    // C# string.Join("\n", text.Split('\n').Take(2)) + WriteLine.
    let head: Vec<&str> = sb.split('\n').take(2).collect();
    print!("{}{NL}", head.join("\n"));
    0
}

const HEADER: &str = concat!(
    "seed\tscore\ttick\troom\tboss\tfork\texit\tcause\tkiller\tchance\tsave60\trescued\tatlas_verdict",
    "\tx\ty\tvy\tsince_bounce\tsince_entry\tL_back\tL_kind\tL_agree\tL_len\tL_real\tL_copy\tL_div\tL_div_what",
    "\tE_back\tE_kind\tE_agree\tE_len\tE_real\tE_copy\tE_div\tE_div_what"
);

fn autopsy(
    seed: i64,
    dead: &GameSim,
    taps: &[bool],
    looks: &[Look],
    bounce_tick: i64,
    entry_tick: i64,
    opts: &Opts,
) -> String {
    let died = taps.len() as i64;
    // One snapshot KEEP ticks before the death; every other state is a copy stepped on from it.
    let base_t = 0.max(died - KEEP);
    let mut snap = GameSim::new(seed);
    for t in 0..base_t {
        snap.step(taps[t as usize]);
    }
    let at_tick = |tick: i64| -> GameSim {
        let mut c = snap.clone_deep();
        for t in base_t..tick {
            c.step(taps[t as usize]);
        }
        c
    };
    let at = |back: i64| at_tick(died - back);
    let savable = |back: i64| SurvivalSearch::new().run_quick(&at(back), back + AFTER);
    let max_back = BACK.min(died - 1);
    let mut chance = -1;
    if savable(max_back) {
        let (mut hi, mut lo) = (0i64, max_back);
        while lo - hi > 1 {
            let mid = (lo + hi) / 2;
            if savable(mid) {
                lo = mid;
            } else {
                hi = mid;
            }
        }
        chance = lo;
    }
    let save60 = died > 60 && savable(60);
    let mut rescued = 0;
    if chance >= 0 {
        let from = max_back.min(chance + LEAD);
        for r in 0..RESCUES {
            let mut c = at(from);
            let mut b2 = BlindPlanner::new(seed * 1000 + r as i64 + 7);
            configure(&mut b2, opts);
            let mut t = 0;
            while t < from + AFTER && !c.is_over() {
                let tap = b2.decide(&c);
                c.step(tap);
                t += 1;
            }
            if !c.is_over() {
                rescued += 1;
            }
        }
    }
    let verdict = if chance < 0 {
        "unfair"
    } else if rescued * 2 >= RESCUES {
        "mistake"
    } else {
        "hidden"
    };
    // The hazards that kill the bird where it died.
    let mut killers: Vec<&'static str> = Vec::new();
    for h in &dead.room.hazards {
        if h.alive() && h.kills(dead) {
            let n = hz_name(h);
            if !killers.contains(&n) {
                killers.push(n);
            }
        }
    }
    let st = &dead.state;
    let exit = if st.exit_open {
        "open"
    } else if st.exit_preview {
        "preview"
    } else {
        "none"
    };
    let fork = st.exit_b_kind != ExitKind::NORMAL;
    let mut row: Vec<String> = vec![
        seed.to_string(),
        st.score.to_string(),
        died.to_string(),
        room_name(dead),
        (if dead.room.def().boss { "1" } else { "0" }).to_string(),
        (if fork { "1" } else { "0" }).to_string(),
        exit.to_string(),
        DeathCause::NAMES[st.death_cause as usize].to_string(),
        if !killers.is_empty() { killers.join("+") } else { "-".to_string() },
        chance.to_string(),
        (if save60 { "1" } else { "0" }).to_string(),
        format!("{rescued}/{RESCUES}"),
        verdict.to_string(),
        (st.x / SimConfig::SUB).to_string(),
        (st.y / SimConfig::SUB).to_string(),
        (st.vy * 10 / SimConfig::SUB).to_string(),
        (died - bounce_tick).to_string(),
        (died - entry_tick).to_string(),
    ];
    // L: the last look at or before the last chance (or 60 ticks before an unfair death).
    let cut = died - if chance >= 0 { chance } else { 60.min(died - 1) };
    let lk = looks.iter().rev().find(|l| l.tick <= cut);
    let ek = looks.iter().rev().find(|l| l.tick < died && l.kind <= 1 && !l.plan.is_empty());
    // Looks in the last 60 ticks that found no line for their whole span (C# computes it, unused).
    let _lost = looks.iter().filter(|l| l.tick >= died - 60 && l.kind >= 2).count();
    for look in [lk, ek] {
        let look = match look {
            None => {
                row.extend(std::iter::repeat("-".to_string()).take(8));
                continue;
            }
            Some(x) => x,
        };
        let mut real = at_tick(look.tick);
        let mut copy = BlindPlanner::blind_copy(&real, SimRng::new(look.seed0), -1, 0, look.anchor, false, false);
        let (real_end, copy_end, div, what) = compare(&mut real, &mut copy, &look.plan);
        row.extend([
            (died - look.tick).to_string(),
            look.kind.to_string(),
            look.agree.to_string(),
            look.plan.len().to_string(),
            real_end,
            copy_end,
            div,
            what,
        ]);
    }
    row.join("\t")
}

/// Plays `plan` on the truth and on the copy side by side.
fn compare(real: &mut GameSim, copy: &mut GameSim, plan: &[bool]) -> (String, String, String, String) {
    let (mut real_end, mut copy_end, mut div, mut what) =
        ("live".to_string(), "live".to_string(), "-".to_string(), "-".to_string());
    for t in 0..plan.len() {
        if div == "-" {
            if let Some(d) = differs(real, copy) {
                div = t.to_string();
                what = d.to_string();
            }
        }
        if real_end == "live" {
            real.step(plan[t]);
        }
        if copy_end == "live" {
            copy.step(plan[t]);
        }
        if real_end == "live" && real.is_over() {
            real_end = format!("{}:{}{}", t + 1, DeathCause::NAMES[real.state.death_cause as usize], kill_name(real));
        }
        if copy_end == "live" && copy.is_over() {
            copy_end = format!("{}:{}{}", t + 1, DeathCause::NAMES[copy.state.death_cause as usize], kill_name(copy));
        }
        if real_end != "live" && copy_end != "live" {
            break;
        }
    }
    (real_end, copy_end, div, what)
}

fn kill_name(s: &GameSim) -> String {
    if s.state.death_cause != DeathCause::HAZARD {
        return String::new();
    }
    match s.room.hazards.iter().find(|h| h.alive() && h.kills(s)) {
        None => String::new(),
        Some(h) => format!(":{}", hz_name(h)),
    }
}

/// What differs on screen between two sims at the same tick, or None.
fn differs(a: &mut GameSim, b: &mut GameSim) -> Option<&'static str> {
    if a.is_over() || b.is_over() {
        return None;
    }
    {
        let (sa, sb) = (&a.state, &b.state);
        if sa.x != sb.x || sa.y != sb.y || sa.vy != sb.vy || sa.vx != sb.vx {
            return Some("bird");
        }
    }
    if a.wall_mask(0) != b.wall_mask(0) || a.wall_mask(1) != b.wall_mask(1) {
        return Some("wall");
    }
    {
        let (sa, sb) = (&a.state, &b.state);
        if sa.exit_open != sb.exit_open
            || sa.exit_preview != sb.exit_preview
            || (sa.exit_open || sa.exit_preview) && sa.exit_a_y != sb.exit_a_y
        {
            return Some("exit");
        }
    }
    if a.room.hazards.len() != b.room.hazards.len() {
        return Some("hazards");
    }
    let (x0, y0) = (a.state.x, a.state.y);
    let mut found: Option<&'static str> = None;
    let step = 12 * SimConfig::SUB;
    let n = a.room.hazards.len();
    let mut h = 0;
    while h < n && found.is_none() {
        if a.room.hazards[h].alive() != b.room.hazards[h].alive() {
            found = Some(hz_name(&a.room.hazards[h]));
            break;
        }
        if !a.room.hazards[h].alive() {
            h += 1;
            continue;
        }
        let mut x = a.room.wall_left();
        while x <= a.room.wall_right() && found.is_none() {
            let mut y = SimConfig::KILL_TOP;
            while y <= SimConfig::KILL_BOTTOM {
                a.state.x = x;
                b.state.x = x;
                a.state.y = y;
                b.state.y = y;
                if a.room.hazards[h].kills(a) != b.room.hazards[h].kills(b) {
                    found = Some(hz_name(&a.room.hazards[h]));
                    break;
                }
                y += step;
            }
            x += step;
        }
        h += 1;
    }
    a.state.x = x0;
    b.state.x = x0;
    a.state.y = y0;
    b.state.y = y0;
    found
}

/// `rl review fixtest --rows autopsy.tsv --taps dir --cfgs "base;aimanchor=1;n=4,lines=4" [--back 600] [--tries 4]`:
/// for every death in `rows`, `tries` planners of each setup (fresh own seeds) start
/// `back` ticks before the death (on the true run) and play to AFTER ticks past it.
pub fn fixtest(opts: &Opts) -> i32 {
    let rows_path = opts.get("rows").expect("--rows");
    let taps_dir = opts.get("taps").expect("--taps");
    let back: i64 = opts.get("back").map(|s| s.as_str()).unwrap_or("600").parse().expect("--back");
    let tries: i32 = opts.get("tries").map(|s| s.as_str()).unwrap_or("4").parse().expect("--tries");
    let cfgs: Vec<String> =
        opts.get("cfgs").map(|s| s.as_str()).unwrap_or("base").split(';').map(|s| s.to_string()).collect();
    let text = std::fs::read_to_string(rows_path).expect("--rows");
    // File.ReadAllLines: split on \n, \r\n or \r.
    let deaths: Vec<(i64, i64, String)> = text
        .split('\n')
        .flat_map(|l| l.split('\r'))
        .filter(|l| !l.is_empty() && l.chars().next().unwrap().is_ascii_digit() && !l.ends_with("alive"))
        .map(|l| {
            let f: Vec<&str> = l.split('\t').collect();
            (f[0].parse().expect("seed"), f[2].parse().expect("tick"), f[3].to_string())
        })
        .collect();
    let nd = deaths.len();
    let mut saved = vec![vec![0f64; nd]; cfgs.len()];
    // Snapshots once; setups one after another (configure sets static switches).
    let snaps: Vec<GameSim> = (0..nd)
        .into_par_iter()
        .map(|d| {
            let (seed, died, _) = &deaths[d];
            let taps = std::fs::read(taps_file(taps_dir, *seed)).expect("taps file");
            let from = 0.max(died - back);
            let mut snap = GameSim::new(*seed);
            for t in 0..from {
                snap.step(taps[t as usize] != 0);
            }
            snap
        })
        .collect();
    for c in 0..cfgs.len() {
        let mut o = Opts::new();
        for kv in cfgs[c].split(',').filter(|s| !s.is_empty()) {
            if kv.contains('=') {
                let parts: Vec<&str> = kv.split('=').collect();
                o.insert(parts[0].to_string(), parts[1].to_string());
            }
        }
        configure(&mut BlindPlanner::new(1), &o);
        let alive: Vec<bool> = (0..nd * tries as usize)
            .into_par_iter()
            .map(|j| {
                let (d, r) = (j / tries as usize, (j % tries as usize) as i64);
                let (seed, died, _) = &deaths[d];
                let from = 0.max(died - back);
                let mut sim = snaps[d].clone_deep();
                let mut bot = BlindPlanner::new(seed * 7919 + r * 31 + 3);
                configure(&mut bot, &o);
                let mut t = from;
                while t < died + AFTER && !sim.is_over() {
                    let tap = bot.decide(&sim);
                    sim.step(tap);
                    t += 1;
                }
                !sim.is_over()
            })
            .collect();
        for (j, &a) in alive.iter().enumerate() {
            if a {
                saved[c][j / tries as usize] += 1.0 / tries as f64;
            }
        }
        eprintln!("  done {}", cfgs[c]);
    }
    println!("fixtest: {nd} deaths, start {back} ticks before, {tries} tries each");
    for c in 0..cfgs.len() {
        let mut sum = 0.0;
        for d in 0..nd {
            sum += saved[c][d];
        }
        // GroupBy room (first-seen order), Sum, Count; stable OrderByDescending(sum); Take(12).
        let mut by: Vec<(String, f64, usize)> = Vec::new();
        for (d, x) in deaths.iter().enumerate() {
            match by.iter_mut().find(|g| g.0 == x.2) {
                Some(g) => {
                    g.1 += saved[c][d];
                    g.2 += 1;
                }
                None => by.push((x.2.clone(), saved[c][d], 1)),
            }
        }
        by.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
        let parts: Vec<String> =
            by.iter().take(12).map(|b| format!("{} {}/{}", b.0, fmt_num(b.1, "F1"), b.2)).collect();
        println!("  {:<40} saves {:>6}   {}", cfgs[c], fmt_num(sum, "F1"), parts.join(", "));
    }
    if let Some(outp) = opts.get("out") {
        let mut sb = format!("seed\troom\t{}\n", cfgs.join("\t"));
        for d in 0..nd {
            let cols: Vec<String> = (0..cfgs.len()).map(|c| fmt_num(saved[c][d], "F2")).collect();
            sb.push_str(&format!("{}\t{}\t{}{NL}", deaths[d].0, deaths[d].2, cols.join("\t")));
        }
        std::fs::write(outp, sb).expect("--out");
    }
    0
}

/// `rl review exposure --taps dir --seeds n [--out f.tsv]`: replays the tap files and counts,
/// per room/variant, the visits, the ticks spent and the points scored there, and the deaths.
/// (C# collects in a ConcurrentBag, so its order of ties varies; here seed order.)
pub fn exposure(opts: &Opts, seeds: i32) -> i32 {
    let taps_dir = opts.get("taps").expect("--taps");
    let per_seed: Vec<Vec<(String, [i64; 5])>> = (1..seeds as i64 + 1)
        .into_par_iter()
        .map(|s| {
            let f = taps_file(taps_dir, s);
            if !f.exists() {
                return Vec::new();
            }
            let taps = std::fs::read(&f).expect("taps file");
            let mut sim = GameSim::new(s);
            // C# Dictionary<string, long[]>: insertion order.
            let mut acc: Vec<(String, [i64; 5])> = Vec::new();
            fn get<'a>(acc: &'a mut Vec<(String, [i64; 5])>, k: &str) -> &'a mut [i64; 5] {
                let i = match acc.iter().position(|e| e.0 == k) {
                    Some(i) => i,
                    None => {
                        acc.push((k.to_string(), [0; 5]));
                        acc.len() - 1
                    }
                };
                &mut acc[i].1
            }
            let mut cur = room_name(&sim);
            get(&mut acc, &cur)[0] += 1;
            let mut score0 = sim.state.score;
            for &b in &taps {
                let ri = sim.state.room_index;
                sim.step(b != 0);
                get(&mut acc, &cur)[1] += 1;
                if sim.state.room_index != ri {
                    get(&mut acc, &cur)[2] += sim.state.score - score0;
                    score0 = sim.state.score;
                    cur = room_name(&sim);
                    get(&mut acc, &cur)[0] += 1;
                    if sim.state.exit_b_kind != ExitKind::NORMAL {
                        get(&mut acc, &cur)[4] += 1;
                    }
                }
                if sim.is_over() {
                    break;
                }
            }
            get(&mut acc, &cur)[2] += sim.state.score - score0;
            if sim.is_over() {
                get(&mut acc, &cur)[3] += 1;
            }
            acc
        })
        .collect();
    // GroupBy room (first-seen order), then stable OrderByDescending(deaths).ThenByDescending(visits).
    let mut groups: Vec<(String, [i64; 5])> = Vec::new();
    for acc in &per_seed {
        for (k, v) in acc {
            match groups.iter_mut().find(|g| &g.0 == k) {
                Some(g) => {
                    for q in 0..5 {
                        g.1[q] += v[q];
                    }
                }
                None => groups.push((k.clone(), *v)),
            }
        }
    }
    groups.sort_by(|a, b| b.1[3].cmp(&a.1[3]).then(b.1[0].cmp(&a.1[0])));
    let mut sb = String::from("room\tvisits\tticks\tpoints\tdeaths\tdeaths_per_100_visits\n");
    for (k, g) in &groups {
        let (v, dd) = (g[0], g[3]);
        sb.push_str(&format!(
            "{k}\t{v}\t{}\t{}\t{dd}\t{}{NL}",
            g[1],
            g[2],
            fmt_num(100.0 * dd as f64 / v.max(1) as f64, "F2")
        ));
    }
    let outp = opts.get("out").cloned().unwrap_or_default();
    if !outp.is_empty() {
        std::fs::write(&outp, &sb).expect("--out");
    } else {
        print!("{sb}");
    }
    0
}

/// `rl review bouncefair --taps dir --seeds n [--every 8] [--react 18]`: replays the tap
/// files; at every `every`-th bounce (every bounce in boss rooms) it asks a true-future
/// SurvivalSearch whether the bird lives to 40 ticks past the next bounce from the
/// bounce itself (`now`) and after `react` more ticks of the run's own taps (`late`).
/// (C# collects in a ConcurrentBag, so its order of ties varies; here seed order.)
pub fn bouncefair(opts: &Opts, seeds: i32) -> i32 {
    let taps_dir = opts.get("taps").expect("--taps");
    let every: i64 = opts.get("every").map(|s| s.as_str()).unwrap_or("8").parse().expect("--every");
    let react: i64 = opts.get("react").map(|s| s.as_str()).unwrap_or("18").parse().expect("--react");
    let per_seed: Vec<Vec<(String, bool, bool, bool)>> = (1..seeds as i64 + 1)
        .into_par_iter()
        .map(|s| {
            let mut all = Vec::new();
            let f = taps_file(taps_dir, s);
            if !f.exists() {
                return all;
            }
            let taps = std::fs::read(&f).expect("taps file");
            let mut sim = GameSim::new(s);
            let mut n: i64 = 0;
            let mut t = 0usize;
            while t < taps.len() && !sim.is_over() {
                let (vx, ri) = (sim.state.vx, sim.state.room_index);
                sim.step(taps[t] != 0);
                if sim.is_over() || sim.state.vx == vx || sim.state.room_index != ri || vx == 0 {
                    t += 1;
                    continue;
                }
                let boss = sim.room.def().boss;
                if !boss {
                    let k = n;
                    n += 1;
                    if k % every != 0 {
                        t += 1;
                        continue;
                    }
                }
                let look = sim.steps_to_wall(if sim.state.vx > 0 { 1 } else { 0 }) + 40;
                let now = SurvivalSearch::new().run_quick(&sim.clone_deep(), look);
                let mut late = false;
                if now {
                    let mut c = sim.clone_deep();
                    let mut k = 1i64;
                    while k <= react && t + (k as usize) < taps.len() && !c.is_over() {
                        c.step(taps[t + k as usize] != 0);
                        k += 1;
                    }
                    late = !c.is_over() && SurvivalSearch::new().run_quick(&c, look - react);
                }
                all.push((room_name(&sim), boss, now, late));
                t += 1;
            }
            all
        })
        .collect();
    let all: Vec<&(String, bool, bool, bool)> = per_seed.iter().flatten().collect();
    let mut sb = format!(
        "bouncefair: react {react}, every {every}th bounce (boss: all)\nroom\tbounces\tlost_at_bounce\tneeds_fast\tpct_lost\tpct_fast\n"
    );
    // GroupBy key (first-seen order), stable OrderByDescending(count of !late).
    let key = |x: &(String, bool, bool, bool)| -> String {
        if x.1 {
            x.0.clone()
        } else {
            let head = x.0.split('/').next().unwrap();
            format!("{}{}", head, if head == "boss" { "" } else { "*" })
        }
    };
    let mut groups: Vec<(String, Vec<&(String, bool, bool, bool)>)> = Vec::new();
    for x in &all {
        let k = key(x);
        match groups.iter_mut().find(|g| g.0 == k) {
            Some(g) => g.1.push(x),
            None => groups.push((k, vec![*x])),
        }
    }
    let not_late = |g: &Vec<&(String, bool, bool, bool)>| g.iter().filter(|x| !x.3).count();
    groups.sort_by(|a, b| not_late(&b.1).cmp(&not_late(&a.1)));
    for (k, g) in &groups {
        let b = g.len();
        let lost = g.iter().filter(|x| !x.2).count();
        let fast = g.iter().filter(|x| x.2 && !x.3).count();
        sb.push_str(&format!(
            "{k}\t{b}\t{lost}\t{fast}\t{}\t{}{NL}",
            fmt_num(100.0 * lost as f64 / b as f64, "F2"),
            fmt_num(100.0 * fast as f64 / b as f64, "F2")
        ));
    }
    for bs in [true, false] {
        let g: Vec<&&(String, bool, bool, bool)> = all.iter().filter(|x| x.1 == bs).collect();
        let lost = g.iter().filter(|x| !x.2).count();
        let fast = g.iter().filter(|x| x.2 && !x.3).count();
        let n = g.len().max(1) as f64;
        sb.push_str(&format!(
            "ALL {}\t{}\t{lost}\t{fast}\t{}\t{}{NL}",
            if bs { "boss" } else { "normal" },
            g.len(),
            fmt_num(100.0 * lost as f64 / n, "F2"),
            fmt_num(100.0 * fast as f64 / n, "F2")
        ));
    }
    let outp = opts.get("out").cloned().unwrap_or_default();
    if !outp.is_empty() {
        std::fs::write(&outp, &sb).expect("--out");
    }
    print!("{sb}");
    0
}
