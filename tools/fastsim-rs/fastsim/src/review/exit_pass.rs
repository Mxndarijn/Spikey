//! Port of RL/ExitPass.cs: three tools, `rl review exitpass`, `rl review bosstell`
//! and `rl review entrytrace` (C# classes ExitPass, BossTell and EntryTrace).
use rayon::prelude::*;
use sim::prelude::*;

use super::{crate_drop, culture_cmp};
use crate::boss::{arrive, boss_of};
use crate::bots::{BlindPlanner, SurvivalSearch};
use crate::difficulty::Cases;
use crate::dotnet_random::DotnetRandom;
use crate::setups::Setups;
use crate::speed::Opts;

fn o(opts: &Opts, k: &str, d: &str) -> String {
    opts.get(k).cloned().unwrap_or_else(|| d.to_string())
}

/// C# `Convert.ToString(x, 2).PadLeft(13, '0')`.
fn bits13(x: i64) -> String {
    format!("{:013b}", x)
}

/// C# `DeathCause.NAMES[c.state.death_cause]` after " DEAD ", or nothing.
fn dead(c: &GameSim) -> String {
    if c.is_over() {
        format!(" DEAD {}", DeathCause::NAMES[c.state.death_cause as usize])
    } else {
        String::new()
    }
}

/// `rl review exitpass --room stalac`: is a room's exit placed where a bird can
/// take it on the first pass? Tool only. For each variant, seed and random
/// surviving line (as the `reach` check plays them), from the step the exit's
/// ghost shows: can SurvivalSearch go through the exit on the bird's first
/// arrival at the exit's wall (no extra crossing)? Also with the two spare
/// crossings the `reach` check allows.
pub fn run(opts: &Opts, seeds: i32) -> i32 {
    let id = o(opts, "room", "stalac");
    let lines: i32 = o(opts, "lines", "3").parse().expect("--lines");
    let def = &RoomCatalog::all()[RoomCatalog::index_of(&id) as usize];
    let variants: Vec<String> = if def.variants.is_empty() {
        vec!["classic".to_string()]
    } else {
        def.variants.iter().map(|v| v.id.to_string()).collect()
    };
    let mut jobs: Vec<(usize, i32, i32)> = Vec::new();
    for v in 0..variants.len() {
        for s in 0..seeds {
            for l in 0..lines {
                jobs.push((v, s, l));
            }
        }
    }
    // Per job: None = no ghost shown; Some((first pass, with 2 spare, miss line)).
    let outs: Vec<Option<(bool, bool, Option<String>)>> = jobs
        .par_iter()
        .map(|&(vi, s, l)| {
            let v = &variants[vi];
            let seed = 1000 + s as i64 * 61;
            let mut sim = Setups::practice(&id, seed, v);
            let mut rnd = Some(DotnetRandom::new((seed as i32).wrapping_mul(7).wrapping_add(l)));
            let mut done: i64 = 0;
            while !sim.state.exit_preview && !sim.is_over() && done < 1500 {
                let mut ss = SurvivalSearch::new();
                ss.pick = rnd.take();
                let ok = ss.run(&sim, 360);
                rnd = ss.pick.take();
                if !ok {
                    return None;
                }
                let n = 120.min(ss.best_inputs.len());
                let mut i = 0;
                while i < n && !sim.state.exit_preview {
                    sim.step(ss.best_inputs[i] == 1);
                    done += 1;
                    i += 1;
                }
            }
            if !sim.state.exit_preview {
                return None;
            }
            let room = sim.state.room_index;
            let crossing = (sim.room.wall_right() - sim.room.wall_left()) / SimConfig::SPEED_X;
            let to_exit = sim.steps_to_exit(sim.state.exit_side);
            let mut a = SurvivalSearch::new();
            a.run(&sim.clone_deep(), to_exit + 10);
            let ok1 = a.best.as_ref().is_some_and(|b| b.state.room_index != room);
            let mut b = SurvivalSearch::new();
            b.run(&sim.clone_deep(), to_exit + 2 * crossing + 10);
            let ok2 = b.best.as_ref().is_some_and(|b| b.state.room_index != room);
            let miss = if !ok1 {
                Some(format!(
                    "{} seed {} line {}: exit {} px, bird {} px{}",
                    v,
                    seed,
                    l,
                    sim.state.exit_a_y / SimConfig::SUB,
                    sim.state.y / SimConfig::SUB,
                    if ok2 { "" } else { " (not even with 2 spare crossings)" }
                ))
            } else {
                None
            };
            Some((ok1, ok2, miss))
        })
        .collect();
    let mut shown = vec![0i32; variants.len()];
    let mut first = vec![0i32; variants.len()];
    let mut spare = vec![0i32; variants.len()];
    let mut bad: Vec<String> = Vec::new();
    for (k, out_) in outs.into_iter().enumerate() {
        let vi = jobs[k].0;
        if let Some((ok1, ok2, miss)) = out_ {
            shown[vi] += 1;
            if ok1 {
                first[vi] += 1;
            }
            if ok2 {
                spare[vi] += 1;
            }
            if let Some(m) = miss {
                bad.push(m);
            }
        }
    }
    println!(
        "exit on the first pass from the ghost, room {}, {} seeds x {} lines, gameplay {}",
        id,
        seeds,
        lines,
        SimConfig::GAMEPLAY_VERSION
    );
    println!("variant\tghosts\tfirst pass\twith 2 spare");
    for (vi, v) in variants.iter().enumerate() {
        println!("{}\t{}\t{}\t{}", v, shown[vi], first[vi], spare[vi]);
    }
    bad.sort_by(|a, b| culture_cmp(a, b));
    for x in &bad {
        println!("miss\t{}", x);
    }
    0
}

/// C# `bb._safe_span(y, at)` on the boss hazard `h` (a BossWatcher, BossCrusher or BossSaw).
fn safe_span(h: &Hz, y: i64, at: i64) -> bool {
    match h {
        Hz::BossWatcher(w) => Boss::_safe_span(w, y, at),
        Hz::BossCrusher(k) => Boss::_safe_span(k, y, at),
        Hz::BossSaw(s) => Boss::_safe_span(s, y, at),
        _ => unreachable!("not a boss"),
    }
}

/// `rl review bosstell --boss boss_watcher --tier 3 --seed 3 --tick 1694`: replays
/// the bossfair gate's tell at `tick` (the planner's old plan for 60 steps) and
/// prints the bird, the boss and the death, step by step. Tool only.
pub fn boss_tell(opts: &Opts) -> i32 {
    let boss = o(opts, "boss", "boss_watcher");
    let tier: i64 = o(opts, "tier", "3").parse().expect("--tier");
    let seed: i64 = o(opts, "seed", "3").parse().expect("--seed");
    let at: i64 = o(opts, "tick", "0").parse().expect("--tick");
    let react: i64 = o(opts, "react", "60").parse().expect("--react");
    let mut sim = arrive(&boss, seed, tier);
    let mut bp = BlindPlanner::new(seed);
    bp.horizon = 200;
    bp.past = 110;
    bp.margin = 10;
    let mut plan: Option<Vec<bool>> = None;
    while !sim.is_over() && sim.state.tick < at {
        let tap = bp.decide(&sim);
        sim.step(tap);
        if sim.state.tick == at {
            plan = Some(bp.plan().iter().copied().collect());
        }
    }
    let plan = match plan {
        Some(p) => p,
        None => {
            println!("tick not reached");
            return 1;
        }
    };
    println!(
        "tell at {}: plan {} steps, bird y {} x {} vx {}",
        at,
        plan.len(),
        sim.state.y / SimConfig::SUB,
        sim.state.x / SimConfig::SUB,
        sim.state.vx
    );
    let mut c = sim.clone_deep();
    let mut u: i64 = 0;
    while u < react + 40 && !c.is_over() {
        let tap = (u as usize) < plan.len() && plan[u as usize];
        let vx0 = c.state.vx;
        c.step(tap);
        if c.state.vx != vx0 {
            if let Some(bb) = boss_of(&c) {
                let side = if c.state.vx > 0 { 1 } else { 0 };
                let at2 = c.steps_to_wall(side);
                let mut safe: i64 = 0;
                for sl in 0..SimConfig::SLOT_COUNT {
                    if safe_span(bb, SimConfig::slot_center_y(sl), at2) {
                        safe |= 1i64 << sl;
                    }
                }
                println!(
                    "    bounce at {}: wall {} drawn {} safe {} at {}",
                    u,
                    side,
                    bits13(c.wall_mask(side)),
                    bits13(safe),
                    at2
                );
            }
        }
        let info = match boss_of(&c) {
            Some(Hz::BossWatcher(w)) => format!(
                "beam {} lit {:b} dart {} lane {} dx {} clock {}",
                w.beam,
                w.lit,
                w.dart,
                w.dart_lane / SimConfig::SUB,
                w.dart_x / SimConfig::SUB,
                w.boss.clock()
            ),
            Some(Hz::BossCrusher(k)) => format!(
                "press {} plate {} lane {}->{} clock {}",
                k.press_y / SimConfig::SUB,
                k.plate_y / SimConfig::SUB,
                k.lane_from / SimConfig::SUB,
                k.lane_to / SimConfig::SUB,
                k.boss.clock()
            ),
            Some(Hz::BossSaw(s)) => format!(
                "king {} {}->{} ring {} clock {}",
                s.king_y / SimConfig::SUB,
                s.from_y / SimConfig::SUB,
                s.to_y / SimConfig::SUB,
                s.ring / SimConfig::SUB,
                s.boss.clock()
            ),
            _ => String::new(),
        };
        if u % 5 == 0 || c.is_over() {
            println!(
                "{:>3} {} y {} x {} vy {} L {} R {} {}{}",
                u,
                if tap { "T" } else { "." },
                c.state.y / SimConfig::SUB,
                c.state.x / SimConfig::SUB,
                c.state.vy,
                bits13(c.wall_mask(0)),
                bits13(c.wall_mask(1)),
                info,
                dead(&c)
            );
        }
        u += 1;
    }
    0
}

/// `rl review entrytrace --rooms bramble/split --first 23`: plays SurvivalSearch's
/// longest line from one difficulty entry (Diff.Cases.arrive) and prints the bird,
/// the walls and the balls every few steps. Tool only.
pub fn entry_trace(opts: &Opts) -> i32 {
    let first: i64 = o(opts, "first", "0").parse().expect("--first");
    let every: i64 = o(opts, "every", "10").parse().expect("--every");
    let from: i64 = o(opts, "from", "0").parse().expect("--from");
    // --practice room/variant --first seed: a practice start (the passable check's) instead.
    let sim: GameSim;
    let cap: i64;
    if let Some(pv) = opts.get("practice") {
        let parts: Vec<&str> = pv.split('/').collect();
        sim = Setups::practice(parts[0], first, if parts.len() > 1 { parts[1] } else { "classic" });
        cap = o(opts, "cap", "1500").parse().expect("--cap");
    } else {
        let rooms = opts.get("rooms").expect("--rooms");
        let t = Cases::all(rooms).into_iter().next().expect("no target for --rooms");
        sim = Cases::arrive(&t, first).unwrap_or_else(|e| panic!("{}", e));
        cap = t.cap;
    }
    let mut ss = SurvivalSearch::new();
    let lived = ss.run(&sim.clone_deep(), cap);
    println!(
        "lived {}, {} steps, survived {}",
        if lived { "True" } else { "False" },
        ss.best_inputs.len(),
        ss.ticks_survived
    );
    if !lived {
        // The longest line: a search that only has to live one step short of where all died.
        let upto = ss.ticks_survived - 1;
        ss = SurvivalSearch::new();
        ss.run(&sim.clone_deep(), upto);
    }
    let mut c = sim.clone_deep();
    let mut u: i64 = 0;
    while u < ss.best_inputs.len() as i64 + 40 && !c.is_over() {
        let vx0 = c.state.vx;
        c.step((u as usize) < ss.best_inputs.len() && ss.best_inputs[u as usize] == 1);
        let bounce = c.state.vx != vx0;
        if (u >= from && u % every == 0) || bounce || c.is_over() {
            let mut bs: Vec<&Bouncer> = Vec::new();
            for h in &c.room.hazards {
                if let Some(b) = h.as_bouncer() {
                    bs.push(b);
                    if let Hz::SplittingBouncer(sb) = h {
                        if let Some(other) = &sb.other {
                            bs.push(other);
                        }
                    }
                }
            }
            let mut balls = bs
                .iter()
                .map(|b| format!("({},{} r{})", b.x / SimConfig::SUB, b.y / SimConfig::SUB, b.radius / SimConfig::SUB))
                .collect::<Vec<_>>()
                .join(" ");
            for h in &c.room.hazards {
                if let Hz::Stalactite(st) = h {
                    balls += &format!(
                        " col{}:{}->{}",
                        st.x / SimConfig::SUB,
                        st.gap_y / SimConfig::SUB,
                        st.target_y / SimConfig::SUB
                    );
                }
            }
            if c.state.exit_open || c.state.exit_preview {
                balls += &format!(
                    " exit {} {}",
                    if c.state.exit_open { "open" } else { "ghost" },
                    c.state.exit_a_y / SimConfig::SUB
                );
            }
            if let Some(cd) = crate_drop(&c) {
                balls += &format!(
                    " crates h[{}] col {} y {} warn {}",
                    cd.heights.iter().map(|h| h.to_string()).collect::<Vec<_>>().join(","),
                    cd.col,
                    cd.y / SimConfig::SUB,
                    cd.warn_left
                );
            }
            println!(
                "{:>4}{} y {} x {} score {} anchor {} L {} R {} {}{}",
                u,
                if bounce { "B" } else { " " },
                c.state.y / SimConfig::SUB,
                c.state.x / SimConfig::SUB,
                c.state.score,
                c.state.anchor_y / SimConfig::SUB,
                bits13(c.wall_mask(0)),
                bits13(c.wall_mask(1)),
                balls,
                dead(&c)
            );
        }
        u += 1;
    }
    0
}

/// `rl review arrivalwait --rooms crates,gifts --seeds 400`: how often a portal
/// arrival (the difficulty tool's entries, Cases::arrive) has no layout fair at
/// every height (GameSim._arrival_unfit; there is no wait out of a portal). Tool only.
pub fn arrival_wait(opts: &Opts, seeds: i32) -> i32 {
    let filter = opts.get("rooms").cloned().unwrap_or_else(|| "crates,gifts".to_string());
    println!("portal arrivals with no layout fair at every height, {} entries per variant", seeds);
    for t in Cases::all(&filter) {
        let (waits, n): (i64, i64) = (0..seeds as i64)
            .into_par_iter()
            .map(|i| match Cases::arrive(&t, i) {
                Ok(sim) => (sim._arrival_unfit as i64, 1),
                Err(_) => (0, 0),
            })
            .reduce(|| (0, 0), |a, b| (a.0 + b.0, a.1 + b.1));
        println!("{}\t{}\t{}\t{:.1}%", t.label, waits, n, 100.0 * waits as f64 / n.max(1) as f64);
    }
    0
}
