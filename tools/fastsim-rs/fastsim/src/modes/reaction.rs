//! Reaction.cs: the modes reaction, odds and scan, and their report lines. (`arrival` is in
//! setups.rs, `play`, `forced` and the thresholds in checks/arrival.rs.)
//!   reaction: tests/support/arrival_bench.gd, the same arrivals per room.
//!   odds: real PlannerBot runs; every portal arrival on the way is replayed at each delay.
use rayon::prelude::*;
use serde_json::{json, Map, Value};
use sim::prelude::*;

use super::{pad_left, per_room, Targets};
use crate::bots::PlannerBot;
use crate::setups::Reaction;
use crate::yardstick::fmt_num;

impl Reaction {
    pub const ODDS_RUN_TICKS: i64 = 7000;

    pub fn delays(arg: &str) -> Vec<i64> {
        if arg == "" {
            return vec![0, Self::EARLY_DELAY, SimConfig::ARRIVAL_BLIND];
        }
        arg.split(',').map(|s| s.parse().expect("delays")).collect()
    }

    /// Every entry height (both sides, a few scores and layout seeds): the heights where an
    /// arrival leaves no way to live after holding `delay`.
    pub fn scan(targets: &Targets, id: &str, delay: i64, seeds: i64) -> i32 {
        let index = RoomCatalog::index_of(id);
        let def = &RoomCatalog::all()[index as usize];
        let forced_v = def.variants.iter().find(|v| v.id == targets.variant);
        let mut ys = Vec::new();
        let mut y = SimConfig::KILL_TOP / SimConfig::SUB + SimConfig::ARRIVAL_EDGE / SimConfig::SUB;
        while y <= (SimConfig::KILL_BOTTOM - SimConfig::ARRIVAL_EDGE) / SimConfig::SUB {
            if def.fits_arrival(y * SimConfig::SUB) && forced_v.is_none_or(|f| f.fits_arrival(y * SimConfig::SUB)) {
                ys.push(y);
            }
            y += 4;
        }
        // Every (y, side, k) on the pool, in the C# loop order.
        let per = 2 * seeds.max(0);
        let hit: Vec<bool> = (0..ys.len() as i64 * per)
            .into_par_iter()
            .map(|c| {
                let y = ys[(c / per) as usize];
                let side = c % per / seeds;
                let k = c % seeds;
                let mut sim = GameSim::new(9100 + k * 37 + y);
                sim.forced_variant = sim::game_sim::intern(forced_v.map(|v| v.id).unwrap_or(""));
                sim.step(true);
                sim.state.score = G::maxi(def.from_score, 10) + (k % 3) * 10;
                sim.state.y = y * SimConfig::SUB;
                sim.state.anchor_y = sim.state.y;
                let skip = sim._arrival_retries(side, index);
                for _ in 0..skip {
                    sim._rng.next_u32();
                }
                sim._arrive_in(side, index);
                Self::forced(&sim, delay, delay + Self::AFTER)
            })
            .collect();
        let mut bad = 0;
        let mut total = 0;
        let mut lines = Vec::new();
        for (yi, &y) in ys.iter().enumerate() {
            let mut hits = Vec::new();
            for side in 0..2 {
                for k in 0..seeds {
                    total += 1;
                    if hit[(yi as i64 * per + side * seeds + k) as usize] {
                        bad += 1;
                        hits.push(format!("s{}k{}", side, k));
                    }
                }
            }
            if !hits.is_empty() {
                lines.push(format!("  y {}: {}", y, hits.join(" ")));
            }
        }
        for l in &lines {
            println!("{}", l);
        }
        println!("{}: {} of {} arrivals with no way to live after {} ticks", id, bad, total, delay);
        if bad > 0 {
            1
        } else {
            0
        }
    }

    pub fn rooms(targets: &Targets, count: i64, filter: &str, delay_arg: &str, first: i64) -> Value {
        let ds = Self::delays(delay_arg);
        let picked = targets.pick(filter, true);
        let all = per_room(&picked, count, |(index, _, v, _), s| {
            let i = first + s;
            let mut ticks = Vec::new();
            let mut causes = Vec::new();
            let mut no_way = Vec::new();
            let at = Reaction::arrival(*index, i, v);
            for &d in &ds {
                let mut bot = PlannerBot::new(i + 1, PlannerBot::HORIZON, PlannerBot::ROLLOUTS);
                let (tick, cause) = Self::play(at.clone_deep(), d, &mut bot, d + Self::AFTER);
                ticks.push(json!(tick));
                causes.push(json!(cause));
                no_way.push(json!(tick >= 0 && Self::forced(&at, d, d + Self::AFTER)));
            }
            json!({ "seed": i, "died": ticks, "cause": causes, "forced": no_way })
        });
        let mut rooms = Vec::new();
        for ((_, _, v, label), runs) in picked.iter().zip(all) {
            let mut ro = Map::new();
            ro.insert("id".into(), json!(label));
            if *v != "" {
                ro.insert("variant".into(), json!(v));
            }
            ro.insert("runs".into(), Value::Array(runs));
            rooms.push(Value::Object(ro));
        }
        json!({ "mode": "reaction", "delays": ds, "rooms": rooms })
    }

    pub fn odds(seeds: i64, delay_arg: &str, first: i64) -> Value {
        let ds = if delay_arg == "" { vec![0, 15, 30, 45, 60, 75, 90] } else { Self::delays(delay_arg) };
        let runs: Vec<Value> = (0..seeds.max(0))
            .into_par_iter()
            .map(|s| {
                let seed_value = 7000 + (first + s) * 131;
                let mut sim = GameSim::new(seed_value);
                let mut bot = PlannerBot::new(seed_value, PlannerBot::HORIZON, PlannerBot::ROLLOUTS);
                let mut rooms = 0i64;
                let mut arrivals = Vec::new();
                while !sim.is_over() && sim.state.tick < Self::ODDS_RUN_TICKS {
                    let tap = bot.decide(&sim);
                    sim.step(tap);
                    if !sim.events.contains(&Event::ROOM_CHANGE) {
                        continue;
                    }
                    rooms += 1;
                    let mut row = Map::new();
                    row.insert("room".into(), json!(RoomCatalog::all()[sim.state.room_kind as usize].id));
                    row.insert("y".into(), json!(sim.state.y / SimConfig::SUB));
                    row.insert("anchor".into(), json!(sim.state.anchor_y / SimConfig::SUB));
                    row.insert("variant".into(), json!(sim.room.variant_id()));
                    row.insert("hold".into(), json!(sim.state.arrival_hold));
                    row.insert("score".into(), json!(sim.state.score));
                    for &d in &ds {
                        let cap = d + Self::AFTER + sim.state.arrival_hold;
                        let mut b = PlannerBot::new(seed_value + sim.state.tick, PlannerBot::HORIZON, PlannerBot::ROLLOUTS);
                        let (tick, cause) = Self::play(sim.clone_deep(), d, &mut b, cap);
                        row.insert(d.to_string(), json!(tick < 0));
                        if tick >= 0 {
                            row.insert(format!("why{}", d), json!(format!("{}@{}", cause, tick)));
                            row.insert(format!("forced{}", d), json!(Self::forced(&sim, d, cap)));
                        }
                    }
                    arrivals.push(Value::Object(row));
                }
                json!({
                    "seed": seed_value, "ticks": sim.state.tick, "score": sim.state.score,
                    "rooms": rooms, "alive": !sim.is_over(),
                    "room": RoomCatalog::all()[sim.state.room_kind as usize].id, "arrivals": arrivals,
                })
            })
            .collect();
        json!({ "mode": "odds", "delays": ds, "runs": runs })
    }

    /// reaction: per room, deaths at each delay and the benchmark (last delay against the
    /// first); returns 1 when a room is over it. odds: deaths per delay over every arrival.
    pub fn print(targets: &Targets, report: &Value) -> i32 {
        let ds: Vec<i64> = report["delays"].as_array().unwrap().iter().map(|x| x.as_i64().unwrap()).collect();
        if report["mode"].as_str() == Some("odds") {
            let runs = report["runs"].as_array().unwrap();
            let mut total = 0i64;
            let mut dead = vec![0i64; ds.len()];
            for r in runs {
                for a in r["arrivals"].as_array().unwrap() {
                    total += 1;
                    for k in 0..ds.len() {
                        if !a[ds[k].to_string()].as_bool().unwrap() {
                            dead[k] += 1;
                        }
                    }
                }
            }
            let alive = runs.iter().filter(|r| r["alive"].as_bool().unwrap()).count();
            println!("{} runs, {} alive at {} ticks, {} portal arrivals", runs.len(), alive, Self::ODDS_RUN_TICKS, total);
            let mut forced_n = vec![0i64; ds.len()];
            for r in runs {
                for a in r["arrivals"].as_array().unwrap() {
                    for k in 0..ds.len() {
                        if let Some(f) = a.get(format!("forced{}", ds[k])) {
                            if f.as_bool().unwrap() {
                                forced_n[k] += 1;
                            }
                        }
                    }
                }
            }
            for k in 0..ds.len() {
                println!(
                    "  reaction {} ticks: {} died ({}%), {} with no way to live ({}%)",
                    pad_left(&ds[k].to_string(), 3),
                    pad_left(&dead[k].to_string(), 4),
                    fmt_num(100.0 * dead[k] as f64 / 1.max(total) as f64, "F1"),
                    pad_left(&forced_n[k].to_string(), 4),
                    fmt_num(100.0 * forced_n[k] as f64 / 1.max(total) as f64, "F2")
                );
            }
            return 0;
        }
        let mut over = 0;
        let mut sum_extra = 0i64;
        let mut sum_n = 0i64;
        let mut sum_forced_early = 0i64;
        for room in report["rooms"].as_array().unwrap() {
            let runs = room["runs"].as_array().unwrap();
            let mut dead = vec![0i64; ds.len()];
            let mut no_way = vec![0i64; ds.len()];
            // C# Dictionary: first-seen order.
            let mut causes: Vec<(String, i64)> = Vec::new();
            for r in runs {
                let died = r["died"].as_array().unwrap();
                for k in 0..ds.len() {
                    if died[k].as_i64().unwrap() >= 0 {
                        dead[k] += 1;
                    }
                    if r["forced"].as_array().unwrap()[k].as_bool().unwrap() {
                        no_way[k] += 1;
                    }
                }
                let c = r["cause"].as_array().unwrap()[ds.len() - 1].as_str().unwrap();
                if c != "" {
                    match causes.iter_mut().find(|(k, _)| k == c) {
                        Some(e) => e.1 += 1,
                        None => causes.push((c.to_string(), 1)),
                    }
                }
            }
            let n = runs.len() as i64;
            let extra = dead[ds.len() - 1] - dead[0];
            let early = ds.iter().position(|&d| d == Self::EARLY_DELAY);
            let ok = no_way[ds.len() - 1] * 100 <= Self::MAX_EXTRA_PCT * n && early.is_none_or(|e| no_way[e] == 0);
            sum_forced_early += early.map(|e| no_way[e]).unwrap_or(0);
            if !ok {
                over += 1;
            }
            sum_extra += 0.max(extra);
            sum_n += n;
            let per: Vec<String> = ds
                .iter()
                .enumerate()
                .map(|(k, d)| {
                    format!("{}:{}", d, dead[k]) + &if no_way[k] > 0 { format!("({} no way)", no_way[k]) } else { String::new() }
                })
                .collect();
            let why: Vec<String> = causes.iter().map(|(k, v)| format!("{} {}", k, v)).collect();
            println!(
                "{:<w$} extra {} of {}  ({})  {}  {}",
                room["id"].as_str().unwrap(),
                pad_left(&extra.to_string(), 3),
                n,
                per.join(" "),
                if ok { "ok" } else { "FAIL" },
                why.join(", "),
                w = targets.width()
            );
        }
        println!(
            "all rooms: extra deaths at {} ticks {} of {} ({}%, limit {}%); no way to live at {} ticks: {} (limit 0); {} rooms fail",
            ds[ds.len() - 1],
            sum_extra,
            sum_n,
            fmt_num(100.0 * sum_extra as f64 / 1.max(sum_n) as f64, "F2"),
            Self::MAX_EXTRA_PCT,
            Self::EARLY_DELAY,
            sum_forced_early,
            over
        );
        let total_ok = sum_extra * 100 <= Self::MAX_EXTRA_PCT * sum_n;
        if over > 0 || !total_ok {
            1
        } else {
            0
        }
    }
}
