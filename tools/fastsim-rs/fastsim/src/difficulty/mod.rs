//! Port of Difficulty/DiffMain.cs: `fastsim difficulty list|measure|score|show`
//! (docs/ROOM_DIFFICULTY.md).
//!   list                       every room and variant it can score
//!   measure --what tube,react,bots [--rooms a,b/v] [--trials 16] [--first 0]
//!           [--bots beginner,...,honest] [--jobs 8] --out m.tsv
//!                              one TSV row per (measure, room, entry, bot); rows already
//!                              in --out are kept and not played again (resume)
//!   score --in m.tsv[,more.tsv] [--out report]  the ranked table (report.md, report.json)
//!   show --rooms <label> --first <entry>        one entry's tube, tick by tick
//! measure writes each row as it finishes (as C#, so a stopped run resumes): the row order in
//! the file is the finishing order, on both. --jobs is the global rayon pool.
use std::collections::HashSet;
use std::io::Write;
use std::sync::Mutex;
use std::time::Instant;

use rayon::prelude::*;

use crate::bots::SurvivalSearch;
use crate::dotnet_random::DotnetRandom;
use crate::human::fmt_f;
use crate::speed::Opts;
use crate::yardstick::fmt_num;

pub mod cases;
pub mod measures;
pub mod score;
pub mod tube;

pub use cases::{Cases, DifficultyCheck, Target};
use measures::{BotPlay, ReactSweep};
use score::Score;
use tube::Tube;

pub fn run(pos: &[String], opts: &Opts) -> i32 {
    let pos = if pos.first().map(|s| s.as_str()) == Some("difficulty") { &pos[1..] } else { pos };
    let what = pos.first().map(|s| s.as_str()).unwrap_or("list");
    match what {
        "list" => {
            for t in Cases::all(opts.get("rooms").map(|s| s.as_str()).unwrap_or("*")) {
                println!("{:<26} {:<9} from {:>4}  cap {}", t.label, t.def.group, t.def.from_score, t.cap);
            }
            return 0;
        }
        "measure" => return measure(opts),
        "score" => return Score::run(opts),
        "show" => {
            // One entry's tube, tick by tick: --rooms <label> --first <entry>.
            let t = Cases::all(&opts["rooms"]).into_iter().next().expect("no such room");
            let entry: i64 = opts.get("first").map(|s| s.as_str()).unwrap_or("0").parse().expect("--first");
            let log: fn(&str) = |s: &str| println!("{}", s);
            let tube = Tube { log: Some(log) };
            let r = tube.run(&Cases::arrive(&t, entry).unwrap_or_else(|e| panic!("{}", e)), t.cap);
            println!(
                "way {} first_exit {} band min {} p10 {} window {} med {}",
                if r.way { "True" } else { "False" },
                r.first_exit,
                r.band_min,
                r.band_p10,
                r.line_window,
                r.line_window_med
            );
            // A second opinion on the way through: SurvivalSearch (finer buckets, escalating), to the exit.
            let at = Cases::arrive(&t, entry).unwrap_or_else(|e| panic!("{}", e));
            let mut ss = SurvivalSearch::new();
            let lived = ss.run(&at, t.cap);
            let out_ = lived && ss.best.as_ref().is_some_and(|b| Cases::cleared(b, at.state.room_index));
            let deaths: Vec<String> = ss.last_deaths.iter().map(|(k, v)| format!("{} {}", k, v)).collect();
            println!(
                "survival search: {}",
                if out_ {
                    "gets through".to_string()
                } else if lived {
                    "lives to the cap but is still in the room".to_string()
                } else {
                    format!("all die by tick {} ({})", ss.ticks_survived, deaths.join(", "))
                }
            );
            return 0;
        }
        _ => {}
    }
    eprintln!("fastsim difficulty list|measure|score");
    2
}

struct Item {
    m: String,
    t: Target,
    i: i64,
    bot: String,
}

fn measure(opts: &Opts) -> i32 {
    let o_ = |k: &str, d: &str| -> String { opts.get(k).cloned().unwrap_or_else(|| d.to_string()) };
    let whats: Vec<String> = o_("what", "tube").split(',').filter(|s| !s.is_empty()).map(|s| s.to_string()).collect();
    let targets = Cases::all(&o_("rooms", "*"));
    let trials: i32 = o_("trials", "16").parse().expect("--trials");
    let first: i64 = o_("first", "0").parse().expect("--first");
    let jobs = rayon::current_num_threads();
    let bots: Vec<String> =
        o_("bots", &BotPlay::BOTS.join(",")).split(',').filter(|s| !s.is_empty()).map(|s| s.to_string()).collect();
    let path = o_("out", "difficulty.tsv");
    let mut done: HashSet<String> = HashSet::new();
    if std::path::Path::new(&path).exists() {
        for line in Score::lines(&path) {
            let f: Vec<&str> = line.split('\t').collect();
            if f.len() > 4 {
                done.insert(format!("{}\t{}\t{}\t{}", f[0], f[1], f[2], f[3]));
            }
        }
    }
    let mut work: Vec<Item> = Vec::new();
    for m in &whats {
        for t in &targets {
            for i in first..first + trials as i64 {
                if m == "bots" {
                    for b in &bots {
                        if !done.contains(&format!("bots\t{}\t{}\t{}", t.label, i, b)) {
                            work.push(Item { m: m.clone(), t: t.clone(), i, bot: b.clone() });
                        }
                    }
                } else if !done.contains(&format!("{}\t{}\t{}\t-", m, t.label, i)) {
                    work.push(Item { m: m.clone(), t: t.clone(), i, bot: "-".to_string() });
                }
            }
        }
    }
    // Heavy and light rooms mixed, the same order every time (OrderBy(_ => rnd.Next()): one key
    // per item in list order, then a stable sort).
    let mut rnd = DotnetRandom::new(7);
    let keys: Vec<i32> = work.iter().map(|_| rnd.next_int()).collect();
    let mut order: Vec<usize> = (0..work.len()).collect();
    order.sort_by_key(|&k| keys[k]);
    let mut slots: Vec<Option<Item>> = work.into_iter().map(Some).collect();
    let work: Vec<Item> = order.into_iter().map(|k| slots[k].take().unwrap()).collect();
    println!("difficulty measure: {} items ({} already in {}), {} threads", work.len(), done.len(), path, jobs);
    let clock = Instant::now();
    let file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .unwrap_or_else(|e| panic!("{}: {}", path, e));
    let nl = if cfg!(windows) { "\r\n" } else { "\n" };
    let gate = Mutex::new((file, 0usize));
    let total = work.len();
    work.par_iter().for_each(|item| {
        let sw = Instant::now();
        let row = match one(&item.m, &item.t, item.i, &item.bot) {
            Ok(r) => r,
            Err(e) => format!("error\tException: {}", e.replace('\t', " ").replace('\n', " ")),
        };
        let ms = sw.elapsed().as_millis();
        let mut g = gate.lock().unwrap();
        let line = format!("{}\t{}\t{}\t{}\t{}\t{}{}", item.m, item.t.label, item.i, item.bot, row, ms, nl);
        g.0.write_all(line.as_bytes()).expect("write the tsv");
        g.0.flush().expect("flush the tsv");
        g.1 += 1;
        if g.1 % 50 == 0 || g.1 == total {
            println!("  {}/{}  {} min", g.1, total, fmt_f(clock.elapsed().as_secs_f64() / 60.0, 1));
        }
    });
    println!("difficulty measure: done in {} min", fmt_f(clock.elapsed().as_secs_f64() / 60.0, 1));
    0
}

/// `x.ToString("0.###", InvariantCulture)`.
fn f_(x: f64) -> String {
    fmt_num(x, "0.###")
}

/// One measure row (Err: C# throws, the row is "error\t...").
fn one(m: &str, t: &Target, i: i64, bot: &str) -> Result<String, String> {
    match m {
        "tube" => {
            let r = Tube::new().run(&Cases::arrive(t, i)?, t.cap);
            // The tube merges near-equal states, so it can miss a way: a "no way" is
            // checked with SurvivalSearch (finer, escalating). 1 confirmed, 0 it got through, - not needed.
            let mut confirmed = "-";
            if !r.way {
                let at = Cases::arrive(t, i)?;
                let mut ss = SurvivalSearch::new();
                let through = ss.run(&at, t.cap) && ss.best.as_ref().is_some_and(|b| Cases::cleared(b, at.state.room_index));
                confirmed = if through { "0" } else { "1" };
            }
            let cells: Vec<String> = vec![
                (if r.way { 1 } else { 0 }).to_string(),
                r.ticks.to_string(),
                r.first_exit.to_string(),
                r.peak.to_string(),
                r.band_min.to_string(),
                r.band_p10.to_string(),
                r.band_med.to_string(),
                f_(r.tight_s),
                f_(r.paths_bits),
                f_(r.bits_per_s),
                r.line_window.to_string(),
                r.line_window_med.to_string(),
                r.line_taps.to_string(),
                r.line_tight.to_string(),
                f_(r.line_s),
                f_(r.choice_s),
                f_(r.viable_frac),
                confirmed.to_string(),
            ];
            Ok(cells.join("\t"))
        }
        "react" => {
            let rows = ReactSweep::run(t, i)?;
            // Per R: shown, no way, died within R; and the same for the shown things with a way at R = 0.
            let mut cells: Vec<String> = vec![rows.len().to_string()];
            for j in 0..ReactSweep::REACTS.len() {
                cells.push(rows.iter().filter(|r| r.verdict[j] == 0).count().to_string());
                cells.push(rows.iter().filter(|r| r.verdict[j] < 0).count().to_string());
                cells.push(rows.iter().filter(|r| r.verdict[0] == 1 && r.verdict[j] != 1).count().to_string());
            }
            let detail: Vec<String> = rows
                .iter()
                .filter(|r| r.verdict.iter().any(|&v| v != 1))
                .map(|r| {
                    let marks: String =
                        r.verdict.iter().map(|&v| if v == 1 { 'o' } else if v == 0 { 'x' } else { 'd' }).collect();
                    format!("{}@{}:{}", r.kind, r.tick, marks)
                })
                .collect();
            let d = detail.join(",");
            cells.push(if d.is_empty() { "-".to_string() } else { d });
            Ok(cells.join("\t"))
        }
        "bots" => {
            let (ok, ticks, why) = BotPlay::play(t, i, bot)?;
            Ok(format!("{}\t{}\t{}", if ok { 1 } else { 0 }, ticks, if why.is_empty() { "-" } else { why.as_str() }))
        }
        _ => Err(format!("unknown measure {}", m)),
    }
}
