//! `rl review crossings --tapsdir <dir> --seedlist a,b|--first N --seeds M [--rooms a,b]`:
//! replays saved autopsy taps (no bot) and, per room/variant, the ticks from each bounce until
//! the bird reaches the opposite wall (the next bounce in the same room): how long the wall the
//! bird flies to is on screen before it gets there, now that a bounce draws that wall.
use rayon::prelude::*;
use sim::prelude::*;

use super::{room_name, NL};
use crate::speed::Opts;

pub fn run(opts: &Opts, seeds: i32) -> i32 {
    let l = |k: &str, d: i64| -> i64 { opts.get(k).map(|v| v.parse().expect(k)).unwrap_or(d) };
    let dir = opts.get("tapsdir").cloned().expect("--tapsdir");
    let list: Vec<i64> = match opts.get("seedlist") {
        Some(v) => v.split(',').filter(|x| !x.is_empty()).map(|x| x.trim().parse().expect("--seedlist")).collect(),
        None => (0..seeds as i64).map(|i| l("first", 0) + i + 1).collect(),
    };
    let rooms: Vec<String> =
        opts.get("rooms").map(|v| v.split(',').map(|s| s.to_string()).collect()).unwrap_or_default();
    let per: Vec<Vec<(String, i64)>> = list
        .into_par_iter()
        .filter_map(|seed| {
            let taps = std::fs::read(std::path::Path::new(&dir).join(format!("{seed}.taps"))).ok()?;
            let mut sim = GameSim::new(seed);
            let mut out = Vec::new();
            let (mut last_bounce, mut ri) = (-1i64, -1i64);
            for (t, &b) in taps.iter().enumerate() {
                let vx = sim.state.vx;
                sim.step(b != 0);
                if sim.is_over() {
                    break;
                }
                if sim.state.room_index != ri {
                    ri = sim.state.room_index;
                    last_bounce = -1;
                }
                if sim.state.vx != vx && vx != 0 {
                    let name = room_name(&sim);
                    if last_bounce >= 0 && (rooms.is_empty() || rooms.iter().any(|r| name.starts_with(r.as_str()))) {
                        out.push((name, t as i64 + 1 - last_bounce));
                    }
                    last_bounce = t as i64 + 1;
                }
            }
            Some(out)
        })
        .collect();
    let mut by: std::collections::BTreeMap<String, Vec<i64>> = std::collections::BTreeMap::new();
    for v in per {
        for (k, d) in v {
            by.entry(k).or_default().push(d);
        }
    }
    let mut sb = format!("room\tcrossings\tmin\tp10\tmedian\tp90\tmax{NL}");
    for (k, mut v) in by {
        v.sort();
        let q = |p: f64| v[((v.len() - 1) as f64 * p).round() as usize];
        sb.push_str(&format!("{k}\t{}\t{}\t{}\t{}\t{}\t{}{NL}", v.len(), v[0], q(0.1), q(0.5), q(0.9), v[v.len() - 1]));
    }
    match opts.get("out") {
        Some(p) => std::fs::write(p, &sb).expect("--out"),
        None => print!("{sb}"),
    }
    0
}
