//! `fastsim-rs rl review <what>`: port of RL/Review.cs `run` for the modes that do
//! not need the RL policy: fair (RL/Fairness.cs), exposure, bouncefair, fixtest and
//! autopsy (RL/Autopsy.cs), horizon and honest (honest.rs), atlas (atlas.rs), trace
//! (trace.rs), blindcheck (blindcheck.rs) and exitpass, bosstell and entrytrace
//! (RL/ExitPass.cs, exit_pass.rs). Same options, same printed text
//! (docs/BOT_TESTING.md).
//!
//! Not ported: rescue, speed (use `fastsim-rs speed`), sens and shape (RL policy), and
//! `rl deaths` (RL/Deaths.cs, RL policy). The BlindPlanner's `steps` counter (search steps
//! per tick in honest and atlas) is C# only: printed as "?".
//! `--threads` is not read: every mode runs on rayon's global pool (`--jobs N`).
use std::cmp::Ordering;

use sim::prelude::*;

use crate::bots::BlindPlanner;
use crate::speed::Opts;

pub mod atlas;
pub mod autopsy;
pub mod blindcheck;
pub mod exit_pass;
pub mod fairness;
pub mod honest;
pub mod trace;

/// C# `Environment.NewLine` (what `StringBuilder.AppendLine` and `Console.WriteLine` end with).
pub const NL: &str = if cfg!(windows) { "\r\n" } else { "\n" };

/// BotCaps.RUN_CAP.
pub const RUN_CAP: i64 = 60 * 60 * SimConfig::TICKS_PER_SECOND;

/// Review.run (the words after `rl review`; pos[0] = the mode).
pub fn run(pos: &[String], opts: &Opts) -> i32 {
    let what = pos.first().map(|s| s.as_str()).unwrap_or("");
    let o = |k: &str, d: &str| opts.get(k).cloned().unwrap_or_else(|| d.to_string());
    let seeds: i32 = o("seeds", "32").parse().expect("--seeds");
    let cap: i64 = o("cap", &RUN_CAP.to_string()).parse().expect("--cap");
    match what {
        "fair" => fairness::run(opts, seeds, cap),
        "entrytrace" => exit_pass::entry_trace(opts),
        "bosstell" => exit_pass::boss_tell(opts),
        "exitpass" => exit_pass::run(opts, seeds),
        "arrivalwait" => exit_pass::arrival_wait(opts, seeds),
        "exposure" => autopsy::exposure(opts, seeds),
        "bouncefair" => autopsy::bouncefair(opts, seeds),
        "fixtest" => autopsy::fixtest(opts),
        "autopsy" => autopsy::run(opts, seeds, cap),
        "horizon" => {
            for h in o("h", "20,40,60,90").split(',') {
                honest::horizon(h.parse().expect("--h"), o("k", "4").parse().expect("--k"), o("cut", "0") == "1", seeds, cap);
            }
            0
        }
        "honest" => {
            honest::honest(opts, seeds, cap);
            0
        }
        "atlas" => atlas::atlas(opts, seeds, cap),
        "blindcheck" => blindcheck::blindcheck(seeds),
        "trace" => trace::trace(opts, cap),
        "rescue" | "speed" | "sens" | "shape" => {
            eprintln!("rl review {what}: not ported to Rust (use C# FastSim)");
            2
        }
        _ => {
            eprintln!("rl review: horizon, sens or shape");
            2
        }
    }
}

fn l(opts: &Opts, k: &str, d: i64) -> i64 {
    opts.get(k).map(|v| v.parse().expect(k)).unwrap_or(d)
}

/// Review.configure: crate::speed::configure sets every knob but `speeds` and `fine`;
/// this sets those two too and returns C#'s setup text.
pub fn configure(bot: &mut BlindPlanner, opts: &Opts) -> String {
    crate::speed::configure(bot, opts);
    bot.speed_buckets = l(opts, "speeds", bot.speed_buckets);
    bot.fine_px = l(opts, "fine", bot.fine_px);
    let f = |b: bool, c: &str| if b { c.to_string() } else { "-".to_string() };
    format!(
        "h {} past {} k {}/{} n {} lines {} wobble {} part {} mid {} tap {} margin {}/{}{} fangs {} rules {}{}{}{}{}{}{}{} buckets {}px x{} fine {}{}{}{}",
        bot.horizon,
        bot.past,
        bot.replan,
        bot.replan_danger,
        bot.copies,
        bot.lines,
        bot.wobble,
        bot.part,
        bot.mid_cost,
        bot.tap_cost,
        bot.margin,
        bot.margin_cost,
        if bot.spike_margin { " +spikes" } else { "" },
        bot.worst_fangs,
        f(bot.no_pingpong, "P"),
        f(bot.keep_plan, "K"),
        f(bot.bounce_look, "B"),
        f(bot.wide_key, "W"),
        f(bot.aim_exit, "A"),
        f(bot.wall_look, "L"),
        f(bot.full_speeds, "S"),
        f(bot.aim_anchor, "N"),
        bot.bucket_px,
        bot.speed_buckets,
        bot.fine_px,
        // C# also prints " longest", " aimwall" and " midvisible": research switches only C# has.
        if bot.follow > 0 { format!(" follow {}", bot.follow) } else { String::new() },
        if bot.tap_free { " tapfree" } else { "" },
        if bot.aim_anchor { " aimanchor" } else { "" }
    )
}

/// Tiers.pct (0 for no values).
pub fn pct(xs: &[i64], p: f64) -> f64 {
    let mut s = xs.to_vec();
    s.sort();
    if s.is_empty() {
        return 0.0;
    }
    let at = p * (s.len() - 1) as f64;
    let lo = at.floor() as usize;
    let hi = at.ceil() as usize;
    s[lo] as f64 + (s[hi] - s[lo]) as f64 * (at - lo as f64)
}

/// C# `double.ToString()` (shortest round trip) for the values printed here
/// (medians of whole points: no exponent form needed).
pub fn dbl(x: f64) -> String {
    format!("{x}")
}

/// C# default string order (`OrderBy(s => s)`: culture compare, ICU root collation with
/// non-ignorable punctuation) for the characters room ids and keys use: tab, space,
/// `_`, `-`, `/` and the other ASCII punctuation in DUCET order, then digits, then
/// letters (case only breaks ties, lower case first). Other characters sort by code.
pub fn culture_cmp(a: &str, b: &str) -> Ordering {
    // FastSim.csproj sets InvariantGlobalization: culture compares are ordinal.
    a.cmp(b)
}

/// C# `room.def.id + "/" + room.variant_id()`.
pub fn room_name(sim: &GameSim) -> String {
    format!("{}/{}", sim.room.def().id, sim.room.variant_id())
}

/// C# `h.GetType().Name`.
pub fn hz_name(h: &Hz) -> &'static str {
    crate::checks::honesty::hz_name(h)
}

/// The first CrateDrop in the room (C# `hazards.OfType<CrateDrop>().FirstOrDefault()`).
pub fn crate_drop(sim: &GameSim) -> Option<&CrateDrop> {
    sim.room.hazards.iter().find_map(|h| match h {
        Hz::CrateDrop(cd) => Some(cd),
        _ => None,
    })
}

/// C# `x.ToString("F<n>")` on .NET 9: the exact value of the double, ties to even (`2.5` ->
/// "2", `81.25` -> "81.2"), which is what Rust's `{:.n}` does. (yardstick::fmt_num rounds
/// ties away from zero.)
pub fn fixed(x: f64, n: usize) -> String {
    format!("{:.*}", n, x)
}
