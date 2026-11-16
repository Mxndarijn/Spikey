//! fastsim-rs repeats [runs] [max_score] [season]: how often a room comes back soon, from the
//! real picker (RoomCatalog::pick_next, its deck and RoomPacing), the way tools/room_odds.gd
//! plays it: a pick at every POINTS_PER_ROOM points, a boss at every BOSS_EVERY (the boss is a
//! room in the sequence but never picked), arrival heights spread over the exit range. Prints,
//! per score band: the share of picks whose room was among the last 3, 5 and 8 rooms, the mean
//! gap (rooms) between two of the same room, the shortest gap, and the share of picks per tier;
//! then the mean distinct rooms in the first 20 and 40 picks. Reads the sim only.
use sim::prelude::*;
use sim::rooms::room_pacing::RoomPacing;
use sim::sim_state::SimState;

const BANDS: [(i64, i64); 6] = [(10, 49), (50, 99), (100, 199), (200, 299), (300, 499), (500, 999)];
const TIER_NAMES: [&str; 7] = ["easy", "steady", "middle", "hard", "harder", "hardest", "bonus"];

fn tier_of(id: &str) -> usize {
    let tiers = [
        RoomPacing::EASY,
        RoomPacing::STEADY,
        RoomPacing::MIDDLE,
        RoomPacing::HARD,
        RoomPacing::HARDER,
        RoomPacing::HARDEST,
        RoomPacing::BONUS,
    ];
    let t = RoomPacing::TIERS.iter().find(|t| t.0 == id).expect("room without a tier").1;
    tiers.iter().position(|x| std::ptr::eq(*x, t) || *x == t).unwrap()
}

#[derive(Default, Clone)]
struct Band {
    picks: i64,
    within: [i64; 3],
    gaps: i64,
    gap_sum: i64,
    gap_min: i64,
    tiers: [i64; 7],
}

pub fn run(pos: &[String]) -> i32 {
    let runs: i64 = pos.first().map(|s| s.parse().expect("runs")).unwrap_or(2000);
    let max_score: i64 = pos.get(1).map(|s| s.parse().expect("max_score")).unwrap_or(990);
    let season: i64 = pos.get(2).map(|s| s.parse().expect("season")).unwrap_or(Seasons::NONE);
    let list = RoomCatalog::all();
    let low = SimConfig::KILL_TOP + SimConfig::ARRIVAL_EDGE;
    let high = SimConfig::KILL_BOTTOM - SimConfig::ARRIVAL_EDGE;
    let mut bands = vec![Band { gap_min: i64::MAX, ..Default::default() }; BANDS.len()];
    let windows = [3usize, 5, 8];
    let mut distinct = [0i64; 2];
    let mut distinct_runs = [0i64; 2];
    let mut stays = 0i64;
    for run in 0..runs {
        let mut rng = SimRng::new(1000 + run);
        let mut heights = SimRng::new(500000 + run);
        let mut state = SimState::default();
        let mut current = RoomCatalog::first_index();
        // Every room entered after the first, bosses too.
        let mut seq: Vec<i64> = Vec::new();
        let mut picks: Vec<i64> = Vec::new();
        let mut score = SimConfig::POINTS_PER_ROOM;
        while score <= max_score {
            if score % SimConfig::BOSS_EVERY == 0 {
                current = RoomCatalog::bosses()[0];
                seq.push(-1);
                score += SimConfig::POINTS_PER_ROOM;
                continue;
            }
            state.score = score;
            state.anchor_y = low + heights.next_below(high - low);
            let prev = current;
            current = RoomCatalog::pick_next(&mut rng, &mut state, current, season);
            if current == prev {
                stays += 1;
            }
            if let Some(b) = BANDS.iter().position(|b| score >= b.0 && score <= b.1) {
                let band = &mut bands[b];
                band.picks += 1;
                band.tiers[tier_of(list[current as usize].id)] += 1;
                for (w, &n) in windows.iter().enumerate() {
                    let from = seq.len().saturating_sub(n);
                    if seq[from..].contains(&current) {
                        band.within[w] += 1;
                    }
                }
                if let Some(last) = seq.iter().rposition(|&r| r == current) {
                    let gap = (seq.len() - last) as i64;
                    band.gaps += 1;
                    band.gap_sum += gap;
                    band.gap_min = band.gap_min.min(gap);
                }
            }
            seq.push(current);
            picks.push(current);
            score += SimConfig::POINTS_PER_ROOM;
        }
        for (k, n) in [20usize, 40].iter().enumerate() {
            if picks.len() >= *n {
                let mut seen: Vec<i64> = picks[..*n].to_vec();
                seen.sort();
                seen.dedup();
                distinct[k] += seen.len() as i64;
                distinct_runs[k] += 1;
            }
        }
    }
    println!("REPEATS runs={} max_score={} season={} no_room_fits={}", runs, max_score, season, stays);
    println!("band\tpicks\tin_last3%\tin_last5%\tin_last8%\tmean_gap\tmin_gap\t{}", TIER_NAMES.join("%\t") + "%");
    for (b, band) in bands.iter().enumerate() {
        if band.picks == 0 {
            continue;
        }
        let pct = |v: i64| 100.0 * v as f64 / band.picks as f64;
        let tiers: Vec<String> = band.tiers.iter().map(|&t| format!("{:.1}", pct(t))).collect();
        println!(
            "{}-{}\t{}\t{:.2}\t{:.2}\t{:.2}\t{:.1}\t{}\t{}",
            BANDS[b].0,
            BANDS[b].1,
            band.picks,
            pct(band.within[0]),
            pct(band.within[1]),
            pct(band.within[2]),
            if band.gaps > 0 { band.gap_sum as f64 / band.gaps as f64 } else { 0.0 },
            if band.gap_min == i64::MAX { 0 } else { band.gap_min },
            tiers.join("\t")
        );
    }
    for (k, n) in [20, 40].iter().enumerate() {
        if distinct_runs[k] > 0 {
            println!("distinct in first {} picks: {:.2}", n, distinct[k] as f64 / distinct_runs[k] as f64);
        }
    }
    0
}

/// How long room `id` (variant `v`) looks like the starter cage, wall spikes only, from its
/// start (game/run painters, 2026-11-16 read): None = never, Some(-1) = the whole room,
/// Some(-2) = until its first point, Some(t) = its first t ticks.
fn plain_for(id: &str, v: &str) -> Option<i64> {
    match (id, v) {
        ("open", _) | ("crowded", _) | ("belt", _) => Some(-1),
        ("squeeze", "classic") | ("squeeze", "left-only") | ("lava", _) => Some(-2),
        ("crosswind", "gusty") => Some(110),
        ("crates", _) | ("gifts", _) => Some(66),
        ("hunter", _) | ("cupid", _) | ("echo", _) => Some(60),
        ("rain", _) | ("icicle", _) | ("keepy", _) | ("beachball", _) => Some(30),
        _ => None,
    }
}

/// Rooms whose only change is to the walls (still spikes on walls): tide, narrow, blink.
fn wall_only(id: &str) -> bool {
    matches!(id, "tide" | "narrow" | "blink")
}

/// fastsim-rs plain [seeds] [cap_ticks]: PlannerBot full runs; per score band the share of
/// ticks on a screen that looks like the starter (plain_for), split into the starter room
/// itself, rooms plain the whole time, rooms plain until their hazard shows, and wall-only
/// rooms (wall_only); plus room changes per minute.
pub fn plain(pos: &[String]) -> i32 {
    use crate::bots::PlannerBot;
    use rayon::prelude::*;
    let seeds: i64 = pos.first().map(|s| s.parse().expect("seeds")).unwrap_or(64);
    let cap: i64 = pos.get(1).map(|s| s.parse().expect("cap")).unwrap_or(36000);
    RoomCatalog::all();
    // Per band: total, starter, whole-room plain, plain at start, wall-only, room changes.
    let per: Vec<Vec<[i64; 6]>> = (0..seeds)
        .into_par_iter()
        .map(|s| {
            let seed_value = 5000 + s * 131;
            let mut sim = GameSim::new(seed_value);
            let mut bot = PlannerBot::new(seed_value, PlannerBot::HORIZON, PlannerBot::ROLLOUTS);
            let mut out = vec![[0i64; 6]; BANDS.len() + 1];
            while !sim.is_over() && sim.state.tick < cap {
                let tap = bot.decide(&sim);
                sim.step(tap);
                let score = sim.state.score;
                let b = if score < 10 { 0 } else { 1 + BANDS.iter().position(|b| score >= b.0 && score <= b.1).unwrap_or(BANDS.len() - 1) };
                let def = sim.room.def();
                let v = if sim.room.variant >= 0 && (sim.room.variant as usize) < def.variants.len() {
                    def.variants[sim.room.variant as usize].id
                } else {
                    ""
                };
                let o = &mut out[b];
                o[0] += 1;
                if sim.events.contains(&Event::ROOM_CHANGE) {
                    o[5] += 1;
                }
                if def.id == "open" {
                    o[1] += 1;
                    continue;
                }
                match plain_for(def.id, v) {
                    Some(-1) => o[2] += 1,
                    Some(-2) if sim.room.points == 0 => o[3] += 1,
                    Some(t) if t > 0 && sim.room.t < t => o[3] += 1,
                    _ => {}
                }
                if wall_only(def.id) {
                    o[4] += 1;
                }
            }
            out
        })
        .collect();
    let mut sum = vec![[0i64; 6]; BANDS.len() + 1];
    for run in &per {
        for (b, o) in run.iter().enumerate() {
            for k in 0..6 {
                sum[b][k] += o[k];
            }
        }
    }
    println!("PLAIN seeds={} cap={}", seeds, cap);
    println!("band\tminutes\tstarter%\tplain_room%\tplain_start%\tlooks_starter%\twall_only%\trooms_per_min");
    for (b, o) in sum.iter().enumerate() {
        if o[0] == 0 {
            continue;
        }
        let name = if b == 0 { "0-9".to_string() } else { format!("{}-{}", BANDS[b - 1].0, BANDS[b - 1].1) };
        let pct = |v: i64| 100.0 * v as f64 / o[0] as f64;
        let mins = o[0] as f64 / 3600.0;
        println!(
            "{}\t{:.1}\t{:.1}\t{:.1}\t{:.1}\t{:.1}\t{:.1}\t{:.2}",
            name, mins, pct(o[1]), pct(o[2]), pct(o[3]), pct(o[1] + o[2] + o[3]), pct(o[4]), o[5] as f64 / mins
        );
    }
    0
}
