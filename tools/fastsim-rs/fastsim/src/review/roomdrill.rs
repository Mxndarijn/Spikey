//! `rl review roomdrill --tapsdir <dir> --room <id> --seedlist a,b|--first N --seeds M
//! [--tries 4] [--cfgs "k=v,..;k=v,.."] [--cap 6000] [--every 1]`: replays saved autopsy taps
//! (no bot) to each entry into a room whose name starts with `--room` (every `--every`th one),
//! then plays fresh BlindPlanners (`--tries` seeds each) from that entry until the bird leaves
//! the room, dies or `--cap` ticks pass. Per planner config: the entries, the deaths and their
//! causes. The same entries and planner seeds for every config, so an A/B is paired. Tool only.
use rayon::prelude::*;
use sim::prelude::*;

use super::{configure, room_name};
use crate::bots::{BlindPlanner, SurvivalSearch};
use crate::speed::Opts;

pub fn run(opts: &Opts, seeds: i32) -> i32 {
    let l = |k: &str, d: i64| -> i64 { opts.get(k).map(|v| v.parse().expect(k)).unwrap_or(d) };
    let dir = opts.get("tapsdir").cloned().expect("--tapsdir");
    let room = opts.get("room").cloned().expect("--room");
    let tries = l("tries", 4);
    let cap = l("cap", 6000);
    let every = l("every", 1).max(1);
    let list: Vec<i64> = match opts.get("seedlist") {
        Some(v) => v.split(',').filter(|x| !x.is_empty()).map(|x| x.trim().parse().expect("--seedlist")).collect(),
        None => (0..seeds as i64).map(|i| l("first", 0) + i + 1).collect(),
    };
    let cfgs: Vec<String> =
        opts.get("cfgs").map(|s| s.as_str()).unwrap_or("base").split(';').map(|s| s.to_string()).collect();
    // Entries (`--room` takes a,b,c): (seed, tick of entry, the sim at entry).
    let mut entries: Vec<(i64, i64, GameSim)> = list
        .into_par_iter()
        .filter_map(|seed| {
            let taps = std::fs::read(std::path::Path::new(&dir).join(format!("{seed}.taps"))).ok()?;
            let mut sim = GameSim::new(seed);
            let mut out = Vec::new();
            let mut ri = sim.state.room_index;
            let mut n = 0i64;
            for (t, &b) in taps.iter().enumerate() {
                sim.step(b != 0);
                if sim.is_over() {
                    break;
                }
                if sim.state.room_index != ri {
                    ri = sim.state.room_index;
                    let name = room_name(&sim);
                    if room.split(',').any(|r| name.starts_with(r)) {
                        if n % every == 0 {
                            out.push((seed, t as i64 + 1, sim.clone_deep()));
                        }
                        n += 1;
                    }
                }
            }
            Some(out)
        })
        .flatten()
        .collect();
    entries.sort_by_key(|e| (e.0, e.1));
    let ne = entries.len();
    println!("roomdrill {room}: {ne} entries, {tries} tries each, cap {cap} ticks");
    for cfg in &cfgs {
        let mut o = Opts::new();
        for kv in cfg.split(',').filter(|s| s.contains('=')) {
            let p: Vec<&str> = kv.splitn(2, '=').collect();
            o.insert(p[0].to_string(), p[1].to_string());
        }
        configure(&mut BlindPlanner::new(1), &o);
        // --show seed@at#try: that run's last `--last` ticks, the planner's look each tick.
        if let Some(show) = opts.get("show") {
            let p: Vec<i64> = show.split(|c| c == '@' || c == '#').map(|x| x.parse().expect("--show")).collect();
            let last = l("last", 200);
            if let Some(d) = entries.iter().position(|e| e.0 == p[0] && e.1 == p[1]) {
                let (seed, at, snap) = &entries[d];
                let mut sim = snap.clone_deep();
                let ri = sim.state.room_index;
                let mut bot = BlindPlanner::new(seed * 7919 + at * 13 + p[2] * 31 + 3);
                configure(&mut bot, &o);
                let mut rows: Vec<String> = Vec::new();
                let mut t = 0;
                while t < cap && !sim.is_over() && sim.state.room_index == ri {
                    let looks = bot.looks;
                    let tap = bot.decide(&sim);
                    if t == l("probe", -1) {
                        // The plan in hand played on the truth and on the look's blind copy.
                        let taps: Vec<bool> = std::iter::once(tap).chain(bot.plan().iter().copied()).collect();
                        let mut a = sim.clone_deep();
                        let mut b = BlindPlanner::blind_copy(
                            &sim,
                            SimRng::new(bot.last_seed0),
                            -1,
                            bot.reveal,
                            if bot.own_anchor { bot.anchor } else { -1 },
                            false,
                            false,
                        );
                        for (i, &k) in taps.iter().enumerate() {
                            a.step(k);
                            b.step(k);
                            if i % 4 == 0 || a.is_over() || b.is_over() {
                                println!(
                                    "probe +{i:3} {} true y {:3} L {:014b} R {:014b} {} | copy y {:3} L {:014b} R {:014b} {}",
                                    if k { "TAP" } else { "   " },
                                    a.state.y / SimConfig::SUB,
                                    a.wall_mask(0),
                                    a.wall_mask(1),
                                    if a.is_over() { DeathCause::NAMES[a.state.death_cause as usize] } else { "" },
                                    b.state.y / SimConfig::SUB,
                                    b.wall_mask(0),
                                    b.wall_mask(1),
                                    if b.is_over() { DeathCause::NAMES[b.state.death_cause as usize] } else { "" },
                                );
                            }
                            if a.is_over() || b.is_over() {
                                break;
                            }
                        }
                    }
                    let st = &sim.state;
                    let mut boss = String::new();
                    for h in &sim.room.hazards {
                        if let Hz::BossWatcher(w) = h {
                            boss = format!("ph {} lit {:07b} beam {} bt {}", w.boss.phase, w.lit, w.beam, w.beam_t);
                        }
                    }
                    let side = if st.vx > 0 { 1 } else { 0 };
                    let truth = if l("truth", 0) > 0 && t % l("truth", 0) == 0 {
                        let mut ss = SurvivalSearch::new();
                        if ss.run(&sim.clone_deep(), l("tail", 120)) { "T+" } else { "T-" }
                    } else {
                        "  "
                    };
                    rows.push(format!(
                        "{t:5} {truth} x {:3} y {:3} vy {:4} {} {} look {} plan {:3} wall {:014b} {boss}",
                        st.x / SimConfig::SUB,
                        st.y / SimConfig::SUB,
                        st.vy,
                        if tap { "TAP" } else { "   " },
                        if bot.looks != looks { "*" } else { " " },
                        bot.last_look,
                        bot.plan().len(),
                        sim.wall_mask(side),
                    ));
                    sim.step(tap);
                    t += 1;
                }
                let from = rows.len().saturating_sub(last as usize);
                for r in &rows[from..] {
                    println!("{r}");
                }
                println!(
                    "end: {}",
                    if sim.is_over() { DeathCause::NAMES[sim.state.death_cause as usize] } else { "alive" }
                );
            }
            continue;
        }
        // Per run: None = left the room; Some((cause, room tick)) = died; Some(("cap", ..)) = stuck.
        let outs: Vec<Option<(String, i64)>> = (0..ne * tries as usize)
            .into_par_iter()
            .map(|j| {
                let (d, r) = (j / tries as usize, (j % tries as usize) as i64);
                let (seed, at, snap) = &entries[d];
                let mut sim = snap.clone_deep();
                let ri = sim.state.room_index;
                let mut bot = BlindPlanner::new(seed * 7919 + at * 13 + r * 31 + 3);
                configure(&mut bot, &o);
                let mut t = 0;
                while t < cap && !sim.is_over() && sim.state.room_index == ri {
                    let tap = bot.decide(&sim);
                    sim.step(tap);
                    t += 1;
                }
                if sim.is_over() {
                    Some((DeathCause::NAMES[sim.state.death_cause as usize].to_string(), t))
                } else if sim.state.room_index == ri {
                    Some(("cap".to_string(), t))
                } else {
                    None
                }
            })
            .collect();
        let mut causes: std::collections::BTreeMap<String, i64> = std::collections::BTreeMap::new();
        let mut dead = 0;
        let mut lines: Vec<String> = Vec::new();
        for (j, out) in outs.iter().enumerate() {
            if let Some((c, t)) = out {
                dead += 1;
                *causes.entry(c.clone()).or_default() += 1;
                let (seed, at, _) = &entries[j / tries as usize];
                lines.push(format!("{seed}@{at}#{}:{c}@{t}", j % tries as usize));
            }
        }
        let runs = ne as i64 * tries;
        let cs: Vec<String> = causes.iter().map(|(k, v)| format!("{k} {v}")).collect();
        println!(
            "  {cfg:<50} deaths {dead}/{runs} ({:.2}%)  {}",
            100.0 * dead as f64 / runs.max(1) as f64,
            cs.join(", ")
        );
        if opts.get("list").is_some_and(|v| v == "1") {
            println!("    {}", lines.join(" "));
        }
    }
    0
}
