//! Port of RL/Review.cs `trace`: `rl review trace --seed n [--last 150] [--every 10]`, the
//! planner's last ticks before its death on one seed: the bird each tick, the wall ahead and every
//! hazard's fields every `every` ticks. For reading one death.
//!
//! C# lists a hazard's public long, bool and List<long> fields by reflection; here they come
//! from measure/fields.rs (the same fields in `Type.GetFields` order).
use std::path::Path;

use sim::prelude::*;

use super::{configure, room_name};
use crate::bots::BlindPlanner;
use crate::measure::fields::{class_fields, hz_class, hz_get, Ty, V};
use crate::speed::Opts;

fn l(opts: &Opts, k: &str, d: i64) -> i64 {
    opts.get(k).map(|v| v.parse().expect(k)).unwrap_or(d)
}

/// C# `bool.ToString()`.
fn cs_bool(b: bool) -> &'static str {
    if b {
        "True"
    } else {
        "False"
    }
}

/// `hz`'s public long, bool and List<long> fields as C# trace prints them.
fn hazard_fields(hz: &Hz) -> String {
    let mut parts: Vec<String> = Vec::new();
    for (i, f) in class_fields(hz_class(hz)).iter().enumerate() {
        match (f.ty, hz_get(hz, i)) {
            (Ty::Long, V::I(l)) => parts.push(format!(
                "{} {}",
                f.name,
                if l.abs() >= 4 * SimConfig::SUB && l % SimConfig::SUB == 0 {
                    format!("{}px", l / SimConfig::SUB)
                } else {
                    l.to_string()
                }
            )),
            (Ty::Bool, V::B(b)) => parts.push(format!("{} {}", f.name, if b { 1 } else { 0 })),
            (Ty::ListLong, V::L(ls)) => parts.push(format!(
                "{} [{}]",
                f.name,
                ls.iter().map(|x| x.to_string()).collect::<Vec<_>>().join(",")
            )),
            _ => {}
        }
    }
    parts.join(" ")
}

pub fn trace(opts: &Opts, cap: i64) -> i32 {
    let seed = l(opts, "seed", 1);
    let last = l(opts, "last", 150);
    let every = l(opts, "every", 10);
    let mut sim = GameSim::new(seed);
    let mut bot = BlindPlanner::new(seed);
    println!("trace seed {} [{}]", seed, configure(&mut bot, opts));
    let mut taps: Vec<bool> = Vec::new();
    // --taps dir: the run from a tap file (Autopsy), no planner (look / agree read 0).
    let tdir = opts.get("taps").cloned().unwrap_or_default();
    if !tdir.is_empty() {
        let bytes = std::fs::read(Path::new(&tdir).join(format!("{seed}.taps"))).expect("taps file");
        for b in bytes {
            taps.push(b != 0);
            sim.step(b != 0);
        }
    } else {
        while !sim.is_over() && (taps.len() as i64) < cap {
            let tap = bot.decide(&sim);
            taps.push(tap);
            sim.step(tap);
        }
    }
    if !sim.is_over() {
        println!("alive at the cap");
        return 0;
    }
    let died = taps.len() as i64;
    println!(
        "died at tick {}, score {}, room {}, cause {}",
        died,
        sim.state.score,
        room_name(&sim),
        DeathCause::NAMES[sim.state.death_cause as usize]
    );
    sim = GameSim::new(seed);
    bot = BlindPlanner::new(seed);
    configure(&mut bot, opts);
    for t in 0..died {
        let tap = if !tdir.is_empty() { taps[t as usize] } else { bot.decide(&sim) };
        if t >= died - last {
            let st = &sim.state;
            let side = if st.vx > 0 { 1 } else { 0 };
            if (t - (died - last)) % every == 0 {
                let mask = sim.wall_mask(side);
                let wall: String =
                    (0..SimConfig::SLOT_COUNT).map(|k| if RoomRules::has_slot(mask, k) { '#' } else { '.' }).collect();
                println!(
                    "  -- wall ahead ({}) {}  exit open {} preview {} side {} a_y {}  anchor {}  room t {}",
                    if side == 1 { "right" } else { "left" },
                    wall,
                    cs_bool(st.exit_open),
                    cs_bool(st.exit_preview),
                    st.exit_side,
                    st.exit_a_y / SimConfig::SUB,
                    st.anchor_y / SimConfig::SUB,
                    sim.room.t
                );
                for hz in sim.room.hazards.iter().filter(|h| h.alive()) {
                    println!("  -- {}: {}", hz_class(hz), hazard_fields(hz));
                }
            }
            println!(
                "  {:>5} x {:>3} y {:>3} vy {:>4} {} look {} agree {} to wall {}",
                t - died,
                st.x / SimConfig::SUB,
                st.y / SimConfig::SUB,
                st.vy * 10 / SimConfig::SUB,
                if tap { "TAP" } else { "   " },
                bot.last_look,
                bot.last_agree,
                sim.steps_to_wall(side)
            );
        }
        sim.step(tap);
    }
    0
}
