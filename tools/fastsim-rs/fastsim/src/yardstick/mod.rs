//! Yardstick/ (docs/YARDSTICK.md): one measure for every bot. Port of YardstickMain.cs:
//! `fastsim yardstick <run|compare|list|leak|humans|stats> [options]` (tools/yardstick.ps1): one
//! shared measure of every bot. Same seeds, same cap and the same numbers for all, written as
//! one JSON per bot and run set plus a comparison table across every JSON in the output folder.
//! `check` (Rust only) runs YardstickCheck.cs.
//!
//! Not ported: HonestBot.cs (`honest-v1`), WorldBots.cs and the RL bots (`add_rl`, `rl:*`).
pub mod bots;
pub mod check;
pub mod compare;
pub mod leak;
pub mod runs;
pub mod stats;
pub mod survival;
pub mod timing;

use std::collections::VecDeque;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use rayon::prelude::*;
use serde_json::{json, Value};
use sim::prelude::*;

use crate::speed::Opts;
use bots::{BotSpec, Bots, Copies};
use compare::Compare;
use leak::{pool, Leak};
use runs::{Run, RunInput};
use stats::{round, Stats};
use timing::{Timing, TimingResult};

pub const FORMAT: i32 = 1;
/// The shared protocol (bot-review.md): seeds 1..400, the bots' cap
/// (BotCaps.RUN_CAP, 60 minutes, about 2400 points), no revives. A
/// median over 64 seeds moves by about 25% by chance; over 400 by about 10%.
/// The quick set is the first 100 of them.
pub const FIRST: i64 = 0;
pub const QUICK: i32 = 100;
pub const FULL: i32 = 400;
pub const CAP: i64 = crate::speed::RUN_CAP;

fn parse<T: std::str::FromStr>(k: &str, v: &str) -> T {
    match v.trim().parse() {
        Ok(x) => x,
        Err(_) => panic!("yardstick: --{} '{}' is not a number", k, v),
    }
}

/// `fastsim yardstick run|compare|list|leak|humans|check` (YardstickMain.run). `pos` is the
/// words after `yardstick` (main passes `&rest[1..]`); a leading "yardstick" is skipped too,
/// as C# gets it (`pos[1]` is the mode there).
pub fn run(pos: &[String], opts: &Opts) -> i32 {
    let pos = if pos.first().map(|s| s.as_str()) == Some("yardstick") { &pos[1..] } else { pos };
    let what = if !pos.is_empty() { pos[0].as_str() } else { "run" };
    let o_ = |k: &str, d: &str| -> String { opts.get(k).cloned().unwrap_or_else(|| d.to_string()) };
    let out_raw = o_("out", r"D:\SoftwareProjects\SpikeCage-coord\research\yardstick");
    let out_dir = std::path::absolute(&out_raw).unwrap_or_else(|_| PathBuf::from(&out_raw));
    let res: Result<i32, String> = (|| match what {
        "list" => {
            for b in Bots::all() {
                println!("  {:<16} {:<10} {}", b.name, b.copies, b.about);
            }
            Ok(0)
        }
        "compare" => Ok(write_table(&out_dir)),
        "stats" => stats(opts),
        "check" => Ok(check::main()),
        "leak" => {
            let threads = parse::<i32>("threads", &o_("threads", "16")).clamp(1, 64);
            // Prints each bot's leak check and adds it to that bot's JSONs in --out.
            for bot in Bots::pick(&o_("bot", ""))? {
                let leak = Leak::check(&bot, parse("leak-seeds", &o_("leak-seeds", "24")), threads);
                println!("  {:<16} {}", bot.name, serde_json::to_string(&leak).unwrap());
                if !out_dir.is_dir() {
                    continue;
                }
                for p in json_files(&out_dir) {
                    let Ok(text) = std::fs::read_to_string(&p) else { continue };
                    let Ok(mut o) = serde_json::from_str::<Value>(&text) else { continue };
                    if !o.is_object() || o["bot"].as_str() != Some(bot.name.as_str()) {
                        continue;
                    }
                    o.as_object_mut().unwrap().insert("leak".to_string(), leak.clone());
                    write_text(&p, &(json_pretty(&o) + "\n"));
                }
            }
            Ok(write_table(&out_dir))
        }
        "run" => {
            let mut set = o_("set", "quick");
            let seeds: i32 =
                parse("seeds", &o_("seeds", &(if set == "full" { FULL } else { QUICK }).to_string()));
            if opts.contains_key("seeds") {
                set = format!("seeds{}", seeds);
            }
            let first: i64 = parse("first", &o_("first", &FIRST.to_string()));
            let cap: i64 = parse("cap", &o_("cap", &CAP.to_string()));
            let threads = parse::<i32>("threads", &o_("threads", "16")).clamp(1, 64);
            let t_runs: i32 = parse("timing-runs", &o_("timing-runs", "40"));
            let t_taps: i32 = parse("timing-taps", &o_("timing-taps", "20"));
            let human = if opts.contains_key("human") { Some(load_humans(&o_("human", ""), cap)?) } else { None };
            std::fs::create_dir_all(&out_dir).map_err(|e| e.to_string())?;
            let mut rc = 0;
            for bot in Bots::pick(&o_("bot", ""))? {
                let leak_seeds: i32 = parse("leak-seeds", &o_("leak-seeds", "24"));
                rc |= measure(&bot, &set, first, seeds, cap, threads, t_runs, t_taps, human.as_deref(), &out_dir, leak_seeds);
            }
            write_table(&out_dir);
            Ok(rc)
        }
        "humans" => {
            // Measures human run files on their own, as the "human" row.
            let cap: i64 = parse("cap", &o_("cap", &CAP.to_string()));
            let human = load_humans(&o_("human", ""), cap)?;
            if human.is_empty() {
                return Ok(1);
            }
            std::fs::create_dir_all(&out_dir).map_err(|e| e.to_string())?;
            let t_runs: i32 = parse("timing-runs", &o_("timing-runs", "40"));
            let t_taps: i32 = parse("timing-taps", &o_("timing-taps", "20"));
            let timing = judge(&human, t_runs, t_taps, parse("threads", &o_("threads", "16")));
            let about = format!("human run files: {}", o_("human", ""));
            let o = report("human", &about, Copies::NONE, "human", 0, human.len() as i32, cap, &human, &timing, None, 0.0);
            save(&o, &out_dir);
            write_table(&out_dir);
            Ok(0)
        }
        _ => {
            eprintln!("unknown yardstick mode '{}': run, compare, list, humans, leak, stats", what);
            Ok(2)
        }
    })();
    match res {
        Ok(rc) => rc,
        Err(e) => {
            eprintln!("{}", e);
            2
        }
    }
}

/// `stats --files a,b,...`: intervals and survival curves for saved run
/// sets (yardstick JSONs or death atlas TSVs), each compared with the
/// first one. No sim is played. `--json <path>` also writes the numbers.
fn stats(opts: &Opts) -> Result<i32, String> {
    let files: Vec<String> = opts
        .get("files")
        .map(|s| s.as_str())
        .unwrap_or("")
        .split(',')
        .map(|f| f.trim().to_string())
        .filter(|f| !f.is_empty())
        .collect();
    let reps: i32 = parse("reps", opts.get("reps").map(|s| s.as_str()).unwrap_or("2000"));
    println!("{}", survival::plan_text());
    if files.is_empty() {
        return Ok(0);
    }
    let sets: Vec<survival::Set> = files.iter().map(|f| survival::load(f)).collect::<Result<_, _>>()?;
    let mut o = json!({ "sets": [], "compare": [] });
    for s in &sets {
        let d = survival::describe(s, reps);
        o["sets"].as_array_mut().unwrap().push(d.clone());
        println!("{}", survival::text(&d));
    }
    for s in sets.iter().skip(1) {
        let c = survival::compare(s, &sets[0], reps);
        o["compare"].as_array_mut().unwrap().push(c.clone());
        println!("{}", survival::text_compare(&c));
    }
    if let Some(path) = opts.get("json") {
        write_text(Path::new(path), &(json_pretty(&o) + "\n"));
    }
    Ok(0)
}

#[allow(clippy::too_many_arguments)]
fn measure(
    bot: &BotSpec,
    set: &str,
    first: i64,
    seeds: i32,
    cap: i64,
    threads: i32,
    t_runs: i32,
    t_taps: i32,
    human: Option<&[Run]>,
    out_dir: &Path,
    leak_seeds: i32,
) -> i32 {
    let clock = Instant::now();
    let done = AtomicUsize::new(0);
    let n_seeds = seeds.max(0) as usize;
    let runs: Vec<Run> = pool(threads).install(|| {
        (0..n_seeds)
            .into_par_iter()
            .map(|i| {
                let input = Run::play(bot, first + 1 + i as i64, cap);
                let r = Run::analyze(&input, cap);
                let n = done.fetch_add(1, Ordering::SeqCst) + 1;
                if n % (n_seeds / 4).max(1) == 0 && clock.elapsed().as_secs_f64() > 30.0 {
                    eprintln!(
                        "  {}: {}/{} runs, {} s",
                        bot.name,
                        n,
                        seeds,
                        fmt_num(clock.elapsed().as_secs_f64(), "F0")
                    );
                }
                r
            })
            .collect()
    });
    let play_s = clock.elapsed().as_secs_f64();
    let timing = judge(&runs, t_runs, t_taps, threads);
    let leak = if leak_seeds > 0 { Some(Leak::check(bot, leak_seeds, threads)) } else { None };
    let mut o = report(
        &bot.name,
        &bot.about,
        bot.copies,
        set,
        first,
        seeds,
        cap,
        &runs,
        &timing,
        human,
        clock.elapsed().as_secs_f64(),
    );
    let m = o.as_object_mut().unwrap();
    m.insert("play_seconds".to_string(), stats::jf(round(play_s, 1)));
    if let Some(l) = &leak {
        m.insert("leak".to_string(), l.clone());
    }
    let s = &o["strength"];
    let claimed = Stats::claimed_tier(&bot.name);
    println!(
        "yardstick {} ({}, {} runs, cap {}): median {}, p25 {}, p75 {}, p90 {}, {} alive at the cap, rate median {} -> {}{}{}  [{} s]",
        bot.name,
        set,
        seeds,
        cap,
        node_str(&s["median"]),
        node_str(&s["p25"]),
        node_str(&s["p75"]),
        node_str(&s["p90"]),
        node_str(&s["capped"]),
        node_str(&s["rate_median"]),
        node_str(&s["tier_by_rate"]),
        if !claimed.is_empty() { format!(" (claims {})", claimed) } else { String::new() },
        match &leak {
            Some(l) => format!(", leaks: {}", node_str(&l["leaks"])),
            None => String::new(),
        },
        fmt_num(clock.elapsed().as_secs_f64(), "F0")
    );
    save(&o, out_dir);
    0
}

fn judge(runs: &[Run], t_runs: i32, t_taps: i32, threads: i32) -> TimingResult {
    let n = (t_runs.max(0) as usize).min(runs.len());
    let parts: Vec<TimingResult> =
        pool(threads).install(|| (0..n).into_par_iter().map(|i| Timing::judge(&runs[i].input, &runs[i], t_taps)).collect());
    let mut all = TimingResult::default();
    for p in parts {
        all.taps_judged += p.taps_judged;
        all.critical += p.critical;
        all.errors.extend(p.errors);
        all.widths.extend(p.widths);
    }
    all
}

#[allow(clippy::too_many_arguments)]
fn report(
    name: &str,
    about: &str,
    copies: &str,
    set: &str,
    first: i64,
    seeds: i32,
    cap: i64,
    runs: &[Run],
    timing: &TimingResult,
    human: Option<&[Run]>,
    seconds: f64,
) -> Value {
    let mut o = json!({
        "yardstick": FORMAT,
        "bot": name,
        "about": about,
        "copies": copies,
        "peeks": copies == Copies::REAL,
        "claimed_tier": Stats::claimed_tier(name),
        "set": set,
        "first_seed": first + 1,
        "seeds": seeds,
        "cap": cap,
        "gameplay_version": SimConfig::GAMEPLAY_VERSION,
        "made": made_now(),
        "seconds": stats::jf(round(seconds, 1)),
        "strength": Stats::strength(runs),
        "human": Stats::human(runs, Some(timing)),
    });
    let m = o.as_object_mut().unwrap();
    if let Some(h) = human {
        if !h.is_empty() {
            m.insert("vs_human".to_string(), Compare::against(runs, h));
        }
    }
    let list: Vec<Value> = runs
        .iter()
        .map(|r| {
            json!({
                "seed": r.input.seed, "points": r.points, "ticks": r.ticks, "dead": r.dead,
                "room": r.room, "cause": r.cause, "taps": r.taps_played,
            })
        })
        .collect();
    m.insert("runs".to_string(), Value::Array(list));
    o
}

/// C# `DateTime.Now.ToString("yyyy-MM-dd HH:mm")`. Rust's std has no local time zone, so this
/// is UTC (the only field that differs from a C# file written at the same moment).
fn made_now() -> String {
    let secs = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0);
    let days = secs.div_euclid(86400);
    let rem = secs.rem_euclid(86400);
    // Howard Hinnant's civil_from_days.
    let z = days + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + if m <= 2 { 1 } else { 0 };
    format!("{:04}-{:02}-{:02} {:02}:{:02}", y, m, d, rem / 3600, rem % 3600 / 60)
}

fn file_name(bot: &str, set: &str) -> String {
    let s: String = format!("{}_{}", bot, set)
        .chars()
        .map(|c| if c.is_alphanumeric() || c == '_' || c == '-' { c } else { '-' })
        .collect();
    s + ".json"
}

fn write_text(path: &Path, text: &str) {
    if let Err(e) = std::fs::write(path, text) {
        panic!("yardstick: cannot write {}: {}", path.display(), e);
    }
}

fn save(o: &Value, out_dir: &Path) {
    let path = out_dir.join(file_name(o["bot"].as_str().unwrap_or(""), o["set"].as_str().unwrap_or("")));
    write_text(&path, &(json_pretty(o) + "\n"));
    println!("  wrote {}", path.display());
}

/// `Directory.GetFiles(dir, "*.json")`, by name (NTFS lists a folder case-insensitively sorted).
fn json_files(dir: &Path) -> Vec<PathBuf> {
    let mut out_: Vec<PathBuf> = match std::fs::read_dir(dir) {
        Ok(rd) => rd
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .filter(|p| p.is_file() && p.extension().map(|x| x.eq_ignore_ascii_case("json")).unwrap_or(false))
            .collect(),
        Err(_) => Vec::new(),
    };
    out_.sort_by_key(|p| p.file_name().map(|n| n.to_string_lossy().to_uppercase()).unwrap_or_default());
    out_
}

/// `Directory.GetFiles(dir, "*.json", AllDirectories)`: a folder's files, then its subfolders
/// in turn (breadth first, as .NET's enumerator queues them).
fn json_files_deep(dir: &Path) -> Vec<PathBuf> {
    let mut out_ = Vec::new();
    let mut queue: VecDeque<PathBuf> = VecDeque::new();
    queue.push_back(dir.to_path_buf());
    while let Some(d) = queue.pop_front() {
        let mut entries: Vec<PathBuf> = match std::fs::read_dir(&d) {
            Ok(rd) => rd.filter_map(|e| e.ok()).map(|e| e.path()).collect(),
            Err(_) => continue,
        };
        entries.sort_by_key(|p| p.file_name().map(|n| n.to_string_lossy().to_uppercase()).unwrap_or_default());
        for p in entries {
            if p.is_dir() {
                queue.push_back(p);
            } else if p.extension().map(|x| x.eq_ignore_ascii_case("json")).unwrap_or(false) {
                out_.push(p);
            }
        }
    }
    out_
}

/// Run files (meta/run_file.gd), a folder of them, or a Your runs file
/// (user://runs.json): every object with "format": "flapjaw_run" counts.
pub fn load_humans(path: &str, cap: i64) -> Result<Vec<Run>, String> {
    let p = Path::new(path);
    let files = if p.is_dir() { json_files_deep(p) } else { vec![p.to_path_buf()] };
    let mut inputs: Vec<RunInput> = Vec::new();
    let mut old = 0;
    fn walk(n: &Value, f: &str, inputs: &mut Vec<RunInput>, old: &mut i32) {
        if let Value::Array(a) = n {
            for x in a {
                walk(x, f, inputs, old);
            }
        }
        let Value::Object(o) = n else { return };
        if o.get("format").and_then(|v| v.as_str()) == Some("flapjaw_run") {
            if o.get("gameplay_version").and_then(as_long) != Some(SimConfig::GAMEPLAY_VERSION) {
                *old += 1;
                return;
            }
            let taps: Vec<i64> = o
                .get("taps")
                .and_then(|t| t.as_array())
                .map(|a| a.iter().map(|t| as_long(t).expect("a tap tick")).collect())
                .unwrap_or_default();
            let seed = o.get("seed").and_then(as_long).expect("a run file without a seed");
            let season = o.get("season").and_then(as_long).unwrap_or(Seasons::NONE);
            inputs.push(RunInput::new(seed, season, taps, f));
            return;
        }
        for (_, v) in o {
            walk(v, f, inputs, old);
        }
    }
    for f in &files {
        if !f.is_file() {
            return Err(format!("{} not found", f.display()));
        }
        let text = std::fs::read_to_string(f).map_err(|e| format!("{}: {}", f.display(), e))?;
        let v: Value = match serde_json::from_str(&text) {
            Ok(v) => v,
            Err(e) => panic!("yardstick: {} is not JSON: {}", f.display(), e),
        };
        walk(&v, &f.display().to_string(), &mut inputs, &mut old);
    }
    println!(
        "yardstick: {} human runs from {}{}",
        inputs.len(),
        path,
        if old > 0 {
            format!(" ({} skipped: another gameplay version, they no longer replay)", old)
        } else {
            String::new()
        }
    );
    Ok(inputs.iter().map(|r| Run::analyze(r, cap)).collect())
}

/// C# `(long)node`: a JSON integer (a whole-number double is accepted too).
fn as_long(v: &Value) -> Option<i64> {
    v.as_i64().or_else(|| v.as_f64().filter(|x| x.fract() == 0.0).map(|x| x as i64))
}

// ---- formatting as C# does it ------------------------------------------------

/// `node.ToJsonString(PRETTY)` (WriteIndented, the default encoder): two-space indent,
/// Environment.NewLine between lines, strings escaped as JavaScriptEncoder.Default does
/// (`"` `&` `'` `+` `<` `>` and the backtick as \uXXXX, all outside printable ASCII too).
pub fn json_pretty(v: &Value) -> String {
    let nl = if cfg!(windows) { "\r\n" } else { "\n" };
    let mut out_ = String::new();
    json_write(v, 0, nl, &mut out_);
    out_
}

fn json_write(v: &Value, depth: usize, nl: &str, out_: &mut String) {
    match v {
        Value::Null => out_.push_str("null"),
        Value::Bool(b) => out_.push_str(if *b { "true" } else { "false" }),
        Value::Number(n) => match (n.as_i64(), n.as_u64(), n.as_f64()) {
            (Some(i), _, _) => out_.push_str(&i.to_string()),
            (None, Some(u), _) => out_.push_str(&u.to_string()),
            // A whole double (a negative zero too) without ".0", as .NET writes it.
            (None, None, Some(x)) if x.fract() == 0.0 && x.abs() < 1e15 => out_.push_str(&format!("{}", x)),
            _ => out_.push_str(&n.to_string()),
        },
        Value::String(s) => json_str(s, out_),
        Value::Array(a) => {
            if a.is_empty() {
                out_.push_str("[]");
                return;
            }
            out_.push('[');
            for (i, x) in a.iter().enumerate() {
                if i > 0 {
                    out_.push(',');
                }
                out_.push_str(nl);
                out_.push_str(&"  ".repeat(depth + 1));
                json_write(x, depth + 1, nl, out_);
            }
            out_.push_str(nl);
            out_.push_str(&"  ".repeat(depth));
            out_.push(']');
        }
        Value::Object(m) => {
            if m.is_empty() {
                out_.push_str("{}");
                return;
            }
            out_.push('{');
            for (i, (k, x)) in m.iter().enumerate() {
                if i > 0 {
                    out_.push(',');
                }
                out_.push_str(nl);
                out_.push_str(&"  ".repeat(depth + 1));
                json_str(k, out_);
                out_.push_str(": ");
                json_write(x, depth + 1, nl, out_);
            }
            out_.push_str(nl);
            out_.push_str(&"  ".repeat(depth));
            out_.push('}');
        }
    }
}

/// A JSON string as Utf8JsonWriter escapes it: \n \r \t \b \f \\ short, the rest \uXXXX.
fn json_str(s: &str, out_: &mut String) {
    out_.push('"');
    for c in s.chars() {
        match c {
            '\n' => out_.push_str("\\n"),
            '\r' => out_.push_str("\\r"),
            '\t' => out_.push_str("\\t"),
            '\u{8}' => out_.push_str("\\b"),
            '\u{C}' => out_.push_str("\\f"),
            '\\' => out_.push_str("\\\\"),
            ' '..='~' if !matches!(c, '"' | '&' | '\'' | '+' | '<' | '>' | '`') => out_.push(c),
            _ => {
                let mut buf = [0u16; 2];
                for u in c.encode_utf16(&mut buf) {
                    out_.push_str(&format!("\\u{:04X}", u));
                }
            }
        }
    }
    out_.push('"');
}

/// C# `JsonNode.ToString()` inside an interpolated string: null -> "", a string as it is,
/// a number in its shortest round-trip form.
pub fn node_str(v: &Value) -> String {
    match v {
        Value::Null => String::new(),
        Value::String(s) => s.clone(),
        Value::Bool(b) => b.to_string(),
        Value::Number(n) => {
            if let Some(i) = n.as_i64() {
                i.to_string()
            } else if let Some(u) = n.as_u64() {
                u.to_string()
            } else {
                format!("{}", n.as_f64().unwrap_or(f64::NAN))
            }
        }
        _ => serde_json::to_string_pretty(v).unwrap(),
    }
}

/// C# `x.ToString(fmt, InvariantCulture)` for the formats the yardstick uses: custom "0",
/// "0.0", "0.00", "0.0000", "0.#" and standard "F0"/"F1". .NET rounds the exact decimal value
/// of the double half away from zero; so does this (Rust's `{:.N}` would round ties to even).
/// A negative number that rounds to zero keeps its "-" (.NET Core 3.0 and later).
pub fn fmt_num(x: f64, fmt: &str) -> String {
    if x.is_nan() {
        return "NaN".to_string();
    }
    if x.is_infinite() {
        return if x > 0.0 { "Infinity".to_string() } else { "-Infinity".to_string() };
    }
    let (decimals, optional) = if let Some(n) = fmt.strip_prefix('F') {
        (n.parse::<usize>().unwrap_or(2), false)
    } else {
        match fmt.split_once('.') {
            None => (0, false),
            Some((_, frac)) => (frac.len(), frac.starts_with('#')),
        }
    };
    // .NET: custom formats ("0.00", "0.#") first take the double to 15 significant
    // digits, then round half away from zero; "F" formats round the exact value.
    let exact = if fmt.starts_with('F') { format!("{:.1100}", x.abs()) } else { sig15_plain(x.abs(), decimals + 2) };
    let (ip, fp) = exact.split_once('.').unwrap();
    let mut digits: Vec<u8> = ip.bytes().chain(fp.bytes().take(decimals)).map(|b| b - b'0').collect();
    if fp.as_bytes()[decimals] >= b'5' {
        let mut i = digits.len();
        loop {
            if i == 0 {
                digits.insert(0, 1);
                break;
            }
            i -= 1;
            if digits[i] == 9 {
                digits[i] = 0;
            } else {
                digits[i] += 1;
                break;
            }
        }
    }
    let int_len = digits.len() - decimals;
    let mut int_part: String = digits[..int_len].iter().map(|d| (b'0' + d) as char).collect();
    let trimmed = int_part.trim_start_matches('0').to_string();
    int_part = if trimmed.is_empty() { "0".to_string() } else { trimmed };
    let mut frac: String = digits[int_len..].iter().map(|d| (b'0' + d) as char).collect();
    if optional {
        frac = frac.trim_end_matches('0').to_string();
    }
    let mut s = String::new();
    if x.is_sign_negative() {
        s.push('-');
    }
    s.push_str(&int_part);
    if !frac.is_empty() {
        s.push('.');
        s.push_str(&frac);
    }
    s
}

/// YardstickMain.f: "-" for null, a number in `fmt`, a bool as yes / **no**, else its text.
fn f(n: &Value, fmt: &str) -> String {
    match n {
        Value::Null => "-".to_string(),
        Value::Number(x) => fmt_num(x.as_f64().unwrap(), fmt),
        Value::Bool(x) => (if *x { "yes" } else { "**no**" }).to_string(),
        _ => node_str(n),
    }
}

/// `f((double?)node * k, fmt)`.
fn fk(n: &Value, k: f64, fmt: &str) -> String {
    match n.as_f64() {
        None => "-".to_string(),
        Some(x) => fmt_num(x * k, fmt),
    }
}

fn leak_cell(l: &Value) -> String {
    if l.is_null() {
        return "-".to_string();
    }
    let v = node_str(&l["leaks"]);
    if v == "yes" {
        format!("**yes** ({}/{})", node_str(&l["forks_leaking"]), node_str(&l["forks_tested"]))
    } else if v == "no" {
        format!("no (0/{})", node_str(&l["forks_tested"]))
    } else {
        v
    }
}

// ---- the comparison table -------------------------------------------------

pub fn write_table(out_dir: &Path) -> i32 {
    if !out_dir.is_dir() {
        return 0;
    }
    let mut rows: Vec<Value> = Vec::new();
    for p in json_files(out_dir) {
        let Ok(text) = std::fs::read_to_string(&p) else { continue };
        if let Ok(o) = serde_json::from_str::<Value>(&text) {
            if o.is_object() && !o["yardstick"].is_null() {
                rows.push(o);
            }
        }
    }
    // C# OrderBy(set) (culture order; ordinal here) then ThenBy(rate_median ?? 1e9), stable.
    rows.sort_by(|a, b| {
        let sa = a["set"].as_str().unwrap_or("");
        let sb_ = b["set"].as_str().unwrap_or("");
        sa.cmp(sb_).then_with(|| {
            let ra = a["strength"]["rate_median"].as_f64().unwrap_or(1e9);
            let rb = b["strength"]["rate_median"].as_f64().unwrap_or(1e9);
            ra.partial_cmp(&rb).unwrap()
        })
    });
    let nl = if cfg!(windows) { "\r\n" } else { "\n" };
    let mut sb = String::new();
    let mut line = |s: &str| {
        sb.push_str(s);
        sb.push_str(nl);
    };
    line("# Bot yardstick: comparison");
    line("");
    line("Made by `tools/yardstick.ps1` (docs/YARDSTICK.md). Every bot plays the same seeds with the same tick cap;");
    line("runs end at the first death (no revive). *Rate median* is ln 0.5 / ln(1 - h), h = deaths per point:");
    line("scores are roughly exponential, so it is the steadier number for tiers. Tier edges are the geometric middles");
    line("of the targets 30 / 60 / 120 / 250 / 500 (42, 85, 173, 354). *Copies*: what a bot steps to look ahead: *real* copies");
    line("know the hidden random draws (a ceiling, not a player), *scrambled* copies have their RNG and salts replaced (rules and");
    line("visible motion only, which the user allows), *none* plays from what it sees. When runs reach the cap, their median is a floor.");
    line("*Leaks* (Leak.cs): each seed is played twice with every hidden draw replaced at a fork tick (next walls, portal, next room,");
    line("hazard salts and timers); a bot whose taps differ before anything on screen differs uses what it can't see (forks leaking / tested).");
    line("");
    line("## Strength");
    line("");
    line("| bot | set | copies | leaks | runs | median | p25 | p75 | p90 | deaths/pt | rate median | tier (rate) | claims | fits | exp KS | alive at cap | top killer | deadliest per visit |");
    line("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|");
    for o in &rows {
        let s = &o["strength"];
        let claim = o["claimed_tier"].as_str().unwrap_or("").to_string();
        let tier = node_str(&s["tier_by_rate"]);
        let fits = if claim.is_empty() {
            ""
        } else if tier == claim {
            "yes"
        } else {
            "**no**"
        };
        let k = s["killers"].as_array().and_then(|a| a.first());
        let dv = s["deadliest_per_visit"].as_array().and_then(|a| a.first());
        let copies = match o["copies"].as_str() {
            Some(c) => c.to_string(),
            None => (if o["peeks"].as_bool().unwrap_or(false) { "real" } else { "none" }).to_string(),
        };
        let killer = match k {
            None => "-".to_string(),
            Some(k) => format!("{} {}%", node_str(&k["room"]), fk(&k["share"], 100.0, "0")),
        };
        let deadly = match dv {
            None => "-".to_string(),
            Some(dv) => format!("{} {}%", node_str(&dv["room"]), fk(&dv["per_visit"], 100.0, "0.0")),
        };
        line(&format!(
            "| {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} |",
            node_str(&o["bot"]),
            node_str(&o["set"]),
            copies,
            leak_cell(&o["leak"]),
            node_str(&s["runs"]),
            f(&s["median"], "0.#"),
            f(&s["p25"], "0.#"),
            f(&s["p75"], "0.#"),
            f(&s["p90"], "0.#"),
            f(&s["death_rate_per_point"], "0.0000"),
            f(&s["rate_median"], "0.#"),
            tier,
            claim,
            fits,
            f(&s["exp_fit_ks"], "0.00"),
            node_str(&s["capped"]),
            killer,
            deadly
        ));
    }
    line("");
    line("## Deaths per 100 points by score band");
    line("");
    line("Points scored inside each band and the deaths there, in brackets (capped runs count their points, no death). It works");
    line("on capped runs and shows where a bot is weak: the first bands are the ramp through the first rooms, the later ones the plateau.");
    line("");
    let sbands = Stats::SCORE_BANDS;
    let bnames: Vec<String> = (0..sbands.len())
        .map(|i| if i + 1 < sbands.len() { format!("{}..{}", sbands[i], sbands[i + 1]) } else { format!("{}+", sbands[i]) })
        .collect();
    line(&format!("| bot | set | {} |", bnames.join(" | ")));
    line(&format!("|---|---|{}", bnames.iter().map(|_| "---|").collect::<String>()));
    for o in &rows {
        let Some(br) = o["strength"]["deaths_per_100_by_band"].as_array() else { continue };
        let cells: Vec<String> = br
            .iter()
            .map(|b| {
                if b["per_100"].is_null() {
                    "-".to_string()
                } else {
                    format!("{} ({})", f(&b["per_100"], "0.00"), node_str(&b["deaths"]))
                }
            })
            .collect();
        line(&format!("| {} | {} | {} |", node_str(&o["bot"]), node_str(&o["set"]), cells.join(" | ")));
    }
    line("");
    line("## Human-likeness");
    line("");
    line("Human reference until there are human runs: Isaksen et al. (FDG 2015): at most 7.7 taps/s (taps 8+ ticks apart),");
    line("timing sigma 2.2-3.7 ticks around the ideal tap, reaction to a new obstacle ~17 ticks (rarely under 10).");
    line("*Timing sd* is the spread of timing-critical taps around the middle of their survivable window (Timing.cs).");
    line("*React* is the first tap after a new room or hazard (a proxy: a tap can be planned before the new thing shows).");
    line("");
    line("| bot | set | taps/s | interval median | taps <8 ticks apart | timing sd | timing mean | critical taps | react (new) median | react <10 | react (bounce) median | bottom quarter | height bands (top→bottom, %) | humanlike | classifier acc |");
    line("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|");
    // Published human numbers (Isaksen et al. FDG 2015), until real runs exist.
    if !rows.iter().any(|o| o["bot"].as_str() == Some("human")) {
        line("| *human reference* | Isaksen 2015 | ≤ 7.7 | ≥ 8 | ~0% | 2.2-3.7 (36-61 ms) | ~0 | - | ~17 (288 ms) | rare | - | - | - | - | - |");
    }
    for o in &rows {
        let h = &o["human"];
        let t = &h["timing"];
        let bands: Vec<String> = h["height_bands"]
            .as_array()
            .map(|a| a.iter().map(|b| fk(b, 100.0, "0")).collect())
            .unwrap_or_default();
        let vs = &o["vs_human"];
        let critical = if t.is_null() {
            "-".to_string()
        } else {
            format!("{}/{}", node_str(&t["critical"]), node_str(&t["taps_judged"]))
        };
        line(&format!(
            "| {} | {} | {} | {} | {}% | {} | {} | {} | {} | {}% | {} | {}% | {} | {} | {} |",
            node_str(&o["bot"]),
            node_str(&o["set"]),
            f(&h["taps_per_s"]["median"], "0.00"),
            f(&h["interval"]["median"], "0.#"),
            fk(&h["interval"]["under_8_ticks"], 100.0, "0.0"),
            f(&t["error_sd"], "0.00"),
            f(&t["error_mean"], "0.00"),
            critical,
            f(&h["react_new"]["median"], "0.#"),
            fk(&h["react_new"]["under_10_ticks"], 100.0, "0"),
            f(&h["react_bounce"]["median"], "0.#"),
            fk(&h["bottom_quarter"], 100.0, "0"),
            bands.join(" "),
            f(&vs["likeness"], "0.00"),
            f(&vs["classifier"]["balanced_accuracy"], "0.00")
        ));
    }
    line("");
    line("No human runs of this game yet: *humanlike* and *classifier acc* stay empty until there are (docs/YARDSTICK.md).");
    let path = out_dir.join("comparison.md");
    write_text(&path, &sb);
    println!("yardstick: {} run sets -> {}", rows.len(), path.display());
    0
}

/// `x` (>= 0) at 15 significant digits as a plain decimal with at least `min_frac` fraction digits.
fn sig15_plain(x: f64, min_frac: usize) -> String {
    let sci = format!("{:.14e}", x);
    let (mant, exp) = sci.split_once('e').unwrap();
    let exp: i64 = exp.parse().unwrap();
    let digits: String = mant.chars().filter(|c| c.is_ascii_digit()).collect();
    let point = exp + 1; // digits before the decimal point
    let (ip, mut fp) = if point <= 0 {
        ("0".to_string(), "0".repeat((-point) as usize) + &digits)
    } else if point as usize >= digits.len() {
        (digits.clone() + &"0".repeat(point as usize - digits.len()), String::new())
    } else {
        (digits[..point as usize].to_string(), digits[point as usize..].to_string())
    };
    while fp.len() < min_frac {
        fp.push('0');
    }
    format!("{ip}.{fp}")
}
