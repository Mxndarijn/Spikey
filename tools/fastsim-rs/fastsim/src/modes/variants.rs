//! `fastsim-rs variants [arrivals] [room]`: how each room variant really turns up out of a
//! portal, and how often a bird dies right after one. For every room (or the ones matching
//! `room`), `arrivals` portal arrivals at planned exit heights spread over the exit range
//! (SimConfig.EXIT_MIN_Y..EXIT_MAX_Y), the bird anywhere in the exit (anchor ± EXIT_FIT), at
//! scores from the room's unlock on. Per arrival: whether the picker may pick the room at that
//! height (`RoomDef.fits_arrival`), the variant the game draws (after ArrivalCheck's retries),
//! whether the room had to wait the whole ARRIVAL_BLIND, and whether PlannerBot reacting after
//! `--delay` ticks (default 45, 0.75 s) dies within `--within` ticks (default 120, 2 s).
//! A tool only: it plays the real arrival code, the same as `_go_through` after the pick.
//! Output: one TSV row per room variant (room, variant, drawn, share %, skipped heights %,
//! blind waits %, deaths % within 2 s). `--deaths 1` also lists every death (stderr) with its
//! seed, heights and whether SurvivalSearch finds a way to live after the same delay.
use std::collections::BTreeMap;

use rayon::prelude::*;
use sim::prelude::*;

use crate::bots::PlannerBot;
use crate::setups::Reaction;
use crate::speed::Opts;

struct Arrival {
    fits: bool,
    variant: &'static str,
    blind: bool,
    died: bool,
    /// --deaths: one line about a death (empty if none).
    note: String,
}

/// The planned exit heights the arrivals use: 110..530 px, the exit range.
const LO_PX: i64 = 110;
const HI_PX: i64 = 530;

fn arrive(index: i64, i: i64, delay: i64, within: i64, deaths: bool) -> Arrival {
    let def = &RoomCatalog::all()[index as usize];
    let mut sim = GameSim::with(70_001 + i * 7919, def.season, -1, "");
    sim.step(true);
    let every = SimConfig::POINTS_PER_ROOM;
    let base_ = G::maxi(every, (def.from_score + every - 1) / every * every);
    sim.state.score = base_ + (i % 8) * every;
    // Spread the planned height evenly over the exit range, and the bird over the exit.
    let span = HI_PX - LO_PX + 1;
    let y_px = LO_PX + (i * 211) % span;
    let anchor = GameSim::_arrival_y(y_px * SimConfig::SUB);
    let offs = [0, -48, 48, -24, 24, -40, 40, 0];
    let dy = offs[((i / 3) % offs.len() as i64) as usize] * SimConfig::SUB;
    let fits = def.fits_arrival(anchor);
    sim.state.anchor_y = anchor;
    sim.state.y = GameSim::_arrival_y(anchor + dy);
    sim.room.rng_seed = sim._spine.next_u32();
    let seed = sim.room.rng_seed;
    sim._rng.reseed(seed);
    let side = i % 2;
    let skip = sim._arrival_retries(side, index);
    for _ in 0..skip {
        sim._rng.next_u32();
    }
    sim._arrive_in(side, index);
    let variant = if def.variants.is_empty() { "" } else { def.variants[sim.room.variant as usize].id };
    let blind = sim.state.arrival_hold >= SimConfig::ARRIVAL_BLIND;
    let at = if deaths { Some(sim.clone_deep()) } else { None };
    let (seed_v, score) = (sim.seed_value, sim.state.score);
    let mut bot = PlannerBot::new(i + 1, 45, 2);
    let (tick, cause) = Reaction::play(sim, delay, &mut bot, within);
    let mut note = String::new();
    if let (true, Some(at)) = (tick >= 0 && fits, at) {
        // Whether any player reacting after `delay` ticks could have lived (SurvivalSearch).
        let forced = Reaction::forced(&at, delay, delay + 120);
        note = format!(
            "{}/{} arrival {} seed {} score {} exit {} px bird {} px side {} died tick {} {} way_to_live {}",
            def.id, variant, i, seed_v, score, anchor / SimConfig::SUB, (anchor + dy) / SimConfig::SUB, side, tick, cause, !forced
        );
    }
    Arrival { fits, variant, blind, died: tick >= 0, note }
}

pub fn run(pos: &[String], opts: &Opts) -> i32 {
    let arrivals: i64 = pos.first().map(|s| s.parse().expect("arrivals")).unwrap_or(200);
    let filter = pos.get(1).cloned().unwrap_or_else(|| "*".to_string());
    let delay: i64 = opts.get("delay").map(|v| v.parse().expect("--delay")).unwrap_or(45);
    let within: i64 = opts.get("within").map(|v| v.parse().expect("--within")).unwrap_or(120);
    let deaths = opts.get("deaths").is_some();
    let rooms = RoomCatalog::all();
    let mut jobs = Vec::new();
    for index in 0..rooms.len() {
        let d = &rooms[index];
        if d.boss || index as i64 == RoomCatalog::first_index() {
            continue;
        }
        if filter != "*" && !filter.split(',').any(|f| f == d.id) {
            continue;
        }
        for i in 0..arrivals {
            jobs.push((index as i64, i));
        }
    }
    let out: Vec<(i64, Arrival)> = jobs.par_iter().map(|&(r, i)| (r, arrive(r, i, delay, within, deaths))).collect();
    if deaths {
        for (_, a) in &out {
            if !a.note.is_empty() {
                eprintln!("{}", a.note);
            }
        }
    }
    println!("room\tvariant\tdrawn\tshare%\tskipped%\tblind%\tdied%");
    let mut by_room: BTreeMap<i64, Vec<&Arrival>> = BTreeMap::new();
    for (r, a) in &out {
        by_room.entry(*r).or_default().push(a);
    }
    for (r, list) in &by_room {
        let def = &rooms[*r as usize];
        // Only arrivals the picker allows count for the variant shares.
        let fit: Vec<&&Arrival> = list.iter().filter(|a| a.fits).collect();
        let skipped = 100.0 * (list.len() - fit.len()) as f64 / list.len() as f64;
        let ids: Vec<&'static str> = if def.variants.is_empty() { vec![""] } else { def.variants.iter().map(|v| v.id).collect() };
        for id in ids {
            let drawn: Vec<&&&Arrival> = fit.iter().filter(|a| a.variant == id).collect();
            let n = drawn.len();
            let pct = |k: usize| if n == 0 { 0.0 } else { 100.0 * k as f64 / n as f64 };
            println!(
                "{}\t{}\t{}\t{:.1}\t{:.1}\t{:.1}\t{:.1}",
                def.id,
                if id.is_empty() { "-" } else { id },
                n,
                if fit.is_empty() { 0.0 } else { 100.0 * n as f64 / fit.len() as f64 },
                skipped,
                pct(drawn.iter().filter(|a| a.blind).count()),
                pct(drawn.iter().filter(|a| a.died).count()),
            );
        }
    }
    0
}
