//! Port of Measure/LeakRun.cs: `Visibility` (what the screen shows, deny by default) and the
//! whole-run leak check (`fastsim measure leak`, docs/BOT_TESTING.md).
//!
//! C# reads and writes the sim's fields by reflection. Rust has none, so `fields.rs` (generated
//! by `gen/rs_fields.py` from the Rust sim's structs) lists every field of SimState, RoomRuntime
//! and each hazard in C# `GetFields` order, with getters, setters for the transplant candidates
//! and the no-argument methods visible.tsv can name. Regenerate it when a sim type gains or
//! loses a field (gen/README.md):
//!
//!     cd tools/fastsim-rs
//!     python fastsim/src/measure/gen/rs_fields.py sim/src fastsim/src/measure/fields.rs
//!
//! The visible checksum only has to tell two sims apart the way C#'s does (A vs B), so its
//! value differs from C#'s; which fields and methods it covers is the same.
//! `Visibility.generate` (`measure visibility`, rebuilding visible.tsv from the GDScript
//! painters) is in visibility.rs, with the methods C# finds by reflection in methods.rs.
use std::collections::{BTreeSet, HashMap, HashSet};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::OnceLock;

use rayon::prelude::*;
use serde_json::{json, Map, Value};
use sim::prelude::*;

use super::bank::{Bank, BankRun, SeedSets};
use super::fields::{self, Ty, F, V};
use super::strat::Strat;
use super::{jr, OrdMap};
use crate::bots::BlindPlanner;
use crate::dotnet_random::DotnetRandom;
use crate::speed::Opts;
use crate::yardstick::bots::BotSpec;
use crate::yardstick::runs::Run;

pub struct Visibility;

/// Where a field lives: the state, the room, or hazard `i` of the room.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Owner {
    State,
    Room,
    Hz(usize),
}

/// A transplant candidate: C#'s (name, type, field, a, b), as owner and field index.
#[derive(Clone, Debug)]
struct Cand {
    name: String,
    owner: Owner,
    i: usize,
}

/// The visible fields (indices) and methods of one class.
struct Shown {
    f: Vec<usize>,
    m: Vec<&'static str>,
}

fn get(sim: &GameSim, o: Owner, i: usize) -> V {
    match o {
        Owner::State => fields::state_get(&sim.state, i),
        Owner::Room => fields::room_get(&sim.room, i),
        Owner::Hz(h) => fields::hz_get(&sim.room.hazards[h], i),
    }
}

fn set_v(sim: &mut GameSim, o: Owner, i: usize, v: &V) {
    match o {
        Owner::State => fields::state_set(&mut sim.state, i, v),
        Owner::Room => fields::room_set(&mut sim.room, i, v),
        Owner::Hz(h) => fields::hz_set(&mut sim.room.hazards[h], i, v),
    }
}

fn class_of(sim: &GameSim, o: Owner) -> &'static str {
    match o {
        Owner::State => "SimState",
        Owner::Room => "RoomRuntime",
        Owner::Hz(h) => fields::hz_class(&sim.room.hazards[h]),
    }
}

/// C# `Equals(v, old)` for a transplant candidate (long, bool by value; a SimRng and a long[]
/// are objects of their own sim, never equal; a List<long> by `SequenceEqual`).
fn cand_equal(ty: Ty, a: &V, b: &V) -> bool {
    match (ty, a, b) {
        (Ty::Long, V::I(x), V::I(y)) => x == y,
        (Ty::Bool, V::B(x), V::B(y)) => x == y,
        (Ty::ListLong, V::L(x), V::L(y)) => x == y,
        _ => false,
    }
}

/// C# `Equals(va, vc)` in `unscrambled` (lists, RNGs and defs are skipped before).
fn plain_equal(a: &V, b: &V) -> bool {
    match (a, b) {
        (V::Null, V::Null) => true,
        (V::I(x), V::I(y)) => x == y,
        (V::B(x), V::B(y)) => x == y,
        (V::S(x), V::S(y)) => x == y,
        _ => false,
    }
}

impl Visibility {
    /// tools/fastsim-rs/data/visible.tsv: from this crate's folder (tools/fastsim-rs/fastsim), or
    /// found from the executable's folder upward.
    pub fn file() -> String {
        let built = concat!(env!("CARGO_MANIFEST_DIR"), "/../data/visible.tsv");
        if std::path::Path::new(built).is_file() {
            return built.to_string();
        }
        if let Ok(exe) = std::env::current_exe() {
            let mut d = exe.parent().map(|p| p.to_path_buf());
            while let Some(p) = d {
                let c = p.join("tools").join("fastsim-rs").join("data").join("visible.tsv");
                if c.is_file() {
                    return c.to_string_lossy().to_string();
                }
                d = p.parent().map(|x| x.to_path_buf());
            }
        }
        built.to_string()
    }

    pub fn visible() -> &'static HashSet<String> {
        static VIS: OnceLock<HashSet<String>> = OnceLock::new();
        VIS.get_or_init(|| {
            let mut set = HashSet::new();
            if let Ok(text) = std::fs::read_to_string(Self::file()) {
                for l in text.lines() {
                    if !l.starts_with('#') && l.contains('\t') {
                        set.insert(l.split('\t').next().unwrap().to_string());
                    }
                }
            }
            set
        })
    }

    /// Visible names are "Class.field"; a hazard's base fields count under its own class.
    pub fn is_visible(class: &str, field: &str) -> bool {
        Self::visible().contains(&format!("{}.{}", class, field))
    }

    /// The visible fields and no-argument methods of a class (C# `shown`).
    fn shown(class: &str) -> &'static Shown {
        static SHOWN: OnceLock<HashMap<String, Shown>> = OnceLock::new();
        let all = SHOWN.get_or_init(|| {
            let mut m = HashMap::new();
            let mut classes: Vec<&str> = vec!["SimState", "RoomRuntime"];
            for c in Self::visible() {
                if let Some((k, _)) = c.split_once('.') {
                    if !classes.contains(&k) {
                        classes.push(k);
                    }
                }
            }
            for c in classes {
                let fs: &[F] = fields::class_fields(c);
                let f: Vec<usize> = (0..fs.len()).filter(|&i| Self::is_visible(c, fs[i].name)).collect();
                // Methods in visible.tsv order (any fixed order gives the same verdicts).
                let mut ms: Vec<&'static str> = fields::class_methods(c)
                    .iter()
                    .copied()
                    .filter(|n| Self::visible().contains(&format!("{}.{}()", c, n)))
                    .collect();
                ms.sort();
                m.insert(c.to_string(), Shown { f, m: ms });
            }
            m
        });
        static NONE: Shown = Shown { f: Vec::new(), m: Vec::new() };
        all.get(class).unwrap_or(&NONE)
    }

    // ------------------------------------------------------------ hashing

    fn hash_value(mut h: i64, v: &V) -> i64 {
        match v {
            V::Null => SimHash::mix(h, 0),
            V::I(x) => SimHash::mix(h, *x),
            V::B(b) => SimHash::mix(h, if *b { 1 } else { 0 }),
            V::S(s) => {
                for ch in s.encode_utf16() {
                    h = SimHash::mix(h, ch as i64);
                }
                h
            }
            V::L(l) => {
                h = SimHash::mix(h, l.len() as i64);
                for &x in l {
                    h = SimHash::mix(h, x);
                }
                h
            }
            V::LB(l) => {
                h = SimHash::mix(h, l.len() as i64);
                for &b in l {
                    h = SimHash::mix(h, if b { 1 } else { 0 });
                }
                h
            }
            // A list of objects: its count; the objects are not values on screen.
            V::Objs(n) => SimHash::mix(h, *n as i64),
            // Objects (defs, RNGs, other hazards) are not values on screen.
            V::Obj | V::Rng(_) => h,
        }
    }

    fn hash_obj(mut h: i64, sim: &GameSim, o: Owner) -> i64 {
        let class = class_of(sim, o);
        let s = Self::shown(class);
        for &i in &s.f {
            h = Self::hash_value(h, &get(sim, o, i));
        }
        for &m in &s.m {
            let v = match o {
                Owner::State => fields::state_method(&sim.state, m),
                Owner::Room => fields::room_method(&sim.room, m),
                Owner::Hz(k) => fields::hz_method(&sim.room.hazards[k], m),
            };
            h = Self::hash_value(h, &v.unwrap_or(V::Null));
        }
        h
    }

    /// A checksum of what the screen shows: every visible field and method result.
    pub fn checksum(sim: &GameSim) -> i64 {
        let mut h = SimHash::SEED;
        h = Self::hash_obj(h, sim, Owner::State);
        h = Self::hash_obj(h, sim, Owner::Room);
        h = SimHash::mix(h, sim.room.hazards.len() as i64);
        for i in 0..sim.room.hazards.len() {
            h = Self::hash_value(h, &V::S(fields::hz_class(&sim.room.hazards[i])));
            h = Self::hash_obj(h, sim, Owner::Hz(i));
        }
        h
    }

    /// Fields a transplant never copies: whether the bird is alive is not a hidden draw.
    const LIFE: [&'static str; 3] = ["SimState.alive", "SimState.death_cause", "SimState.revives"];

    fn of(dst: &GameSim, donor: &GameSim, o: Owner, tag: &str, out_: &mut Vec<Cand>) {
        let class = class_of(dst, o);
        let fs = fields::class_fields(class);
        for (i, f) in fs.iter().enumerate() {
            if Self::is_visible(class, f.name)
                || f.readonly
                || Self::LIFE.contains(&format!("{}.{}", class, f.name).as_str())
            {
                continue;
            }
            // Plain values, RNGs and lists of numbers only: references to other objects
            // (a gate's partner, the room's def) belong to the donor's world.
            if !matches!(f.ty, Ty::Long | Ty::Bool | Ty::Rng | Ty::ListLong | Ty::ArrLong) {
                continue;
            }
            let v = get(donor, o, i);
            let old = get(dst, o, i);
            if cand_equal(f.ty, &v, &old) {
                continue;
            }
            out_.push(Cand { name: format!("{}{}.{}", class, tag, f.name), owner: o, i });
        }
    }

    fn candidates(dst: &GameSim, donor: &GameSim) -> Vec<Cand> {
        let mut res = Vec::new();
        Self::of(dst, donor, Owner::State, "", &mut res);
        Self::of(dst, donor, Owner::Room, "", &mut res);
        for i in 0..dst.room.hazards.len() {
            Self::of(dst, donor, Owner::Hz(i), &format!("[{}]", i), &mut res);
        }
        res
    }

    fn lines_up(dst: &GameSim, donor: &GameSim) -> bool {
        if dst.room.hazards.len() != donor.room.hazards.len() {
            return false;
        }
        (0..dst.room.hazards.len())
            .all(|i| fields::hz_class(&dst.room.hazards[i]) == fields::hz_class(&donor.room.hazards[i]))
    }

    /// The hidden fields a transplant from `donor` would change.
    pub fn transplant_fields(dst: &GameSim, donor: &GameSim) -> Vec<String> {
        if Self::lines_up(dst, donor) {
            Self::candidates(dst, donor).into_iter().map(|c| c.name).collect()
        } else {
            Vec::new()
        }
    }

    /// Copies every hidden field of `dst`'s state, room and hazards from `donor`
    /// (same room and variant, hazards matched by place and type). One field at a time,
    /// kept only when the screen stays the same (a hidden input of something shown, such
    /// as a tide's salt, would change it). Returns the number of fields copied, or -1 when
    /// the hazards do not line up.
    pub fn transplant(dst: &mut GameSim, donor: &GameSim) -> i32 {
        if !Self::lines_up(dst, donor) {
            return -1;
        }
        let screen = Self::checksum(dst);
        let mut n = 0;
        for c in Self::candidates(dst, donor) {
            if Self::set(dst, donor, &c, screen) {
                n += 1;
            }
        }
        n
    }

    /// C# `transplant(dst, donor, only)`: only the field named `only`.
    pub fn transplant_one(dst: &mut GameSim, donor: &GameSim, only: &str) -> bool {
        if !Self::lines_up(dst, donor) {
            return false;
        }
        let screen = Self::checksum(dst);
        match Self::candidates(dst, donor).into_iter().find(|c| c.name == only) {
            Some(c) => Self::set(dst, donor, &c, screen),
            None => false,
        }
    }

    fn set(dst: &mut GameSim, donor: &GameSim, c: &Cand, screen: i64) -> bool {
        let v = get(donor, c.owner, c.i);
        let old = get(dst, c.owner, c.i);
        set_v(dst, c.owner, c.i, &v);
        if Self::checksum(dst) == screen {
            return true;
        }
        set_v(dst, c.owner, c.i, &old);
        false
    }

    /// Hidden fields (not on screen) that the bot's own blind_copy leaves as they are:
    /// the blind spots of the old leak check, which only tested blind_copy's list.
    pub fn unscrambled(sim: &GameSim) -> Vec<String> {
        let mut res = Vec::new();
        let b = BlindPlanner::blind_copy(sim, SimRng::new(12345), -1, 0, -1, false, false);
        let mut cmp = |oa: Owner, ob: Owner| {
            let class = class_of(sim, oa);
            let fs = fields::class_fields(class);
            for (i, f) in fs.iter().enumerate() {
                if Self::is_visible(class, f.name) {
                    continue;
                }
                let va = get(sim, oa, i);
                // `va is SimRng || va is RoomDef || va is IList` (a null def is compared).
                let skip = match f.ty {
                    Ty::Rng | Ty::ListLong | Ty::ArrLong | Ty::ListBool | Ty::ArrBool | Ty::Hazards => true,
                    Ty::Def => !matches!(va, V::Null),
                    _ => false,
                };
                if skip {
                    continue;
                }
                if plain_equal(&va, &get(&b, ob, i)) {
                    res.push(format!("{}.{}", class, f.name));
                }
            }
        };
        cmp(Owner::State, Owner::State);
        cmp(Owner::Room, Owner::Room);
        for i in 0..sim.room.hazards.len().min(b.room.hazards.len()) {
            if fields::hz_class(&sim.room.hazards[i]) != fields::hz_class(&b.room.hazards[i]) {
                continue; // C# would read b's field of another type and throw; blind_copy keeps the types
            }
            cmp(Owner::Hz(i), Owner::Hz(i));
        }
        res
    }
}

/// The whole-run leak check (`fastsim measure leak`, docs/BOT_TESTING.md).
/// On its own seeds (900 001 and up) the bot plays whole runs once (a bank).
/// Forks are spread over the whole run: random bounces, plus every boss room
/// (a bounce soon after entry) and every exit draw (the bounce before the exit
/// preview shows). At a fork two fresh copies of the bot (same seed) play two
/// sims that show the same screen: A is the real one, B has every hidden draw
/// replaced: the RNGs and seeds (BlindPlanner.blind_copy) and then, deny by
/// default, every field the screen does not show (`visible.tsv`) copied from a
/// donor: the same room and variant drawn again from the room's entry with
/// another spine, flown with the same taps to the fork tick. Until the
/// visible checksum differs, an honest bot taps the same in both; a tap that
/// differs earlier is a leak.
pub struct LeakRun;

/// C# record Fork(seed, at, why, room, verdict, first_diff, visible_from, transplanted, cause).
#[derive(Clone, Debug)]
pub struct Fork {
    pub seed: i64,
    pub at: i64,
    pub why: String,
    pub room: String,
    pub verdict: &'static str,
    pub first_diff: i64,
    pub visible_from: i64,
    pub transplanted: i32,
    pub cause: String,
}

impl LeakRun {
    pub const WINDOW: i64 = 400;

    #[allow(clippy::too_many_arguments)]
    fn mk(
        seed: i64,
        at: i64,
        why: &str,
        room: &str,
        verdict: &'static str,
        first_diff: i64,
        visible_from: i64,
        transplanted: i32,
        cause: &str,
    ) -> Fork {
        Fork {
            seed,
            at,
            why: why.to_string(),
            room: room.to_string(),
            verdict,
            first_diff,
            visible_from,
            transplanted,
            cause: cause.to_string(),
        }
    }

    /// C# `check(bot, opts, threads, log)`: the forks run on rayon's global pool.
    pub fn check(bot: &BotSpec, opts: &Opts, log: bool) -> Result<Value, String> {
        let o_ = |k: &str, d: &str| opts.get(k).cloned().unwrap_or_else(|| d.to_string());
        let seeds: i32 = super::parse(&o_("seeds", "12"), "seeds");
        let random_forks: i32 = super::parse(&o_("forks", "40"), "forks");
        let cap: i64 = super::parse(&o_("cap", &crate::speed::RUN_CAP.to_string()), "cap");
        let points: i64 = super::parse(&o_("points", "400"), "points");
        let bank = match opts.get("bank") {
            Some(bp) if std::path::Path::new(bp).is_file() => Bank::load(bp)?,
            _ => {
                let b = Bank::make(bot, SeedSets::LEAK, seeds, cap, points, log);
                if let Some(bp) = opts.get("bank") {
                    b.save(bp)?;
                }
                b
            }
        };
        if Visibility::visible().is_empty() {
            return Err(format!("no visible list at {}", Visibility::file()));
        }
        // Pick the forks per run.
        let mut jobs: Vec<(usize, i64, String)> = Vec::new();
        for (i, r) in bank.runs.iter().enumerate() {
            let mut rng = DotnetRandom::new((r.seed % 100000) as i32);
            for (tick, why) in Self::fork_points(r, random_forks, &mut rng) {
                jobs.push((i, tick, why));
            }
        }
        let done = AtomicUsize::new(0);
        let nj = jobs.len();
        let res: Vec<Fork> = (0..nj)
            .into_par_iter()
            .map(|i| {
                let (run, tick, ref why) = jobs[i];
                let f = Self::fork(bot, &bank.runs[run], tick, why);
                let d = done.fetch_add(1, Ordering::SeqCst) + 1;
                if log && d % 50 == 0 {
                    eprintln!("  leak forks {}/{}", d, nj);
                }
                f
            })
            .collect();
        let is_tested = |f: &Fork| f.verdict == "leak" || f.verdict == "same";
        let tested: Vec<&Fork> = res.iter().filter(|f| is_tested(f)).collect();
        let leaks = tested.iter().filter(|f| f.verdict == "leak").count() as i32;
        let power = |every: f64| 1.0 - (1.0 - 1.0 / every).powf(tested.len() as f64);
        let mut by_room_g: OrdMap<String, (i32, i32)> = OrdMap::new();
        for f in &tested {
            let e = by_room_g.entry_or(f.room.split('@').next().unwrap().to_string(), || (0, 0));
            e.0 += 1;
            if f.verdict == "leak" {
                e.1 += 1;
            }
        }
        let mut by_room_v: Vec<(String, (i32, i32))> = by_room_g.into_vec();
        by_room_v.sort_by(|a, b| b.1 .0.cmp(&a.1 .0));
        let mut by_room = Map::new();
        for (k, (n, l)) in by_room_v {
            by_room.insert(k, format!("{} forks, {} leaks", n, l).into());
        }
        let mut by_why_g: OrdMap<String, (i32, i32, i32)> = OrdMap::new();
        for f in &res {
            let e = by_why_g.entry_or(f.why.clone(), || (0, 0, 0));
            if is_tested(f) {
                e.0 += 1;
            }
            e.1 += 1;
            if f.verdict == "leak" {
                e.2 += 1;
            }
        }
        let mut by_why = Map::new();
        for (k, (t, n, l)) in by_why_g.iter() {
            by_why.insert(k.clone(), format!("{} tested of {}, {} leaks", t, n, l).into());
        }
        // Fields the screen does not show that the bot's own blind_copy keeps: the old check never varied them.
        let mut blind_spots: BTreeSet<String> = BTreeSet::new();
        for r in bank.runs.iter().take(4) {
            for (k, v) in r.visits.iter().enumerate() {
                if k % 3 != 0 {
                    continue;
                }
                let pre = Bank::replay(r, v.tick + 30);
                if !pre.is_over() {
                    for f in Visibility::unscrambled(&pre) {
                        blind_spots.insert(f);
                    }
                }
            }
        }
        let ex = res.iter().find(|f| f.verdict == "leak");
        let deepest = tested
            .iter()
            .map(|f| {
                bank.runs
                    .iter()
                    .find(|r| r.seed == f.seed)
                    .unwrap()
                    .visits
                    .iter()
                    .rev()
                    .find(|v| v.tick <= f.at)
                    .map(|v| v.score)
                    .unwrap_or(0)
            })
            .max()
            .unwrap_or(0);
        let mut o = Map::new();
        o.insert(
            "leaks".into(),
            (if tested.is_empty() {
                "untested"
            } else if leaks > 0 {
                "yes"
            } else {
                "no"
            })
            .into(),
        );
        o.insert("bot".into(), bot.name.clone().into());
        o.insert("seeds".into(), format!("{}..{}", SeedSets::LEAK + 1, SeedSets::LEAK + bank.runs.len() as i64).into());
        o.insert("forks_tested".into(), (tested.len() as i64).into());
        o.insert("forks_leaking".into(), leaks.into());
        o.insert("forks_untested".into(), ((res.len() - tested.len()) as i64).into());
        o.insert("deepest_fork_points".into(), deepest.into());
        o.insert("with_donor".into(), (tested.iter().filter(|f| f.transplanted >= 0).count() as i64).into());
        o.insert(
            "power".into(),
            json!({ "leak_1_in_100_flights": jr(power(100.0), 3), "1_in_200": jr(power(200.0), 3), "1_in_1000": jr(power(1000.0), 3) }),
        );
        o.insert("by_reason".into(), Value::Object(by_why));
        o.insert("by_room".into(), Value::Object(by_room));
        o.insert(
            "hidden_but_kept_by_blind_copy".into(),
            Value::Array(blind_spots.into_iter().map(Value::from).collect()),
        );
        o.insert(
            "how".into(),
            "forks over whole runs (random bounces, boss rooms, exit draws); B gets new RNGs and, deny by default, every \
             field visible.tsv does not list from a redrawn donor of the same room; a tap differing before the visible \
             checksum does is a leak"
                .into(),
        );
        o.insert(
            "leak_forks".into(),
            Value::Array(
                res.iter()
                    .filter(|f| f.verdict == "leak")
                    .map(|f| {
                        Value::from(format!(
                            "seed {} tick {} ({}, {}): taps differ at {}; read: {}",
                            f.seed, f.at, f.why, f.room, f.first_diff, f.cause
                        ))
                    })
                    .collect(),
            ),
        );
        if let Some(ex) = ex {
            o.insert(
                "example".into(),
                format!(
                    "seed {} ({}, {}), fork at tick {}: taps differ at {}, {}",
                    ex.seed,
                    ex.why,
                    ex.room,
                    ex.at,
                    ex.first_diff,
                    if ex.visible_from < 0 {
                        "nothing visible differed yet".to_string()
                    } else {
                        format!("the screen differed only from {}", ex.visible_from)
                    }
                )
                .into(),
            );
        }
        Ok(Value::Object(o))
    }

    /// Bounce ticks to fork at: `n` random ones, the first bounce 30+ ticks into
    /// every boss room, and the bounce before every exit preview.
    fn fork_points(r: &BankRun, n: i32, rng: &mut DotnetRandom) -> Vec<(i64, String)> {
        let mut sim = GameSim::with(r.seed, r.season, -1, "");
        let set: HashSet<i64> = r.taps.iter().copied().collect();
        let mut bounces: Vec<i64> = Vec::new();
        let mut res: Vec<(i64, String)> = Vec::new();
        let mut boss_from: i64 = -1;
        let mut last_bounce: i64 = -1;
        let end = r.ticks;
        while sim.state.tick < end && !sim.is_over() {
            let t = sim.state.tick;
            let ri = sim.state.room_index;
            sim.step(set.contains(&t));
            let bounce = sim.events.contains(&Event::BOUNCE) && sim.state.room_index == ri;
            if sim.state.room_index != ri && sim.room.def().boss {
                boss_from = sim.state.tick + 30;
            }
            if sim.events.contains(&Event::EXIT_PREVIEW) && last_bounce > 0 {
                res.push((last_bounce, "exit draw".to_string()));
            }
            if bounce {
                bounces.push(sim.state.tick);
                last_bounce = sim.state.tick;
                if boss_from >= 0 && sim.state.tick >= boss_from {
                    res.push((sim.state.tick, "boss room".to_string()));
                    boss_from = -1;
                }
            }
        }
        // Forks need a whole flight before the death.
        bounces.retain(|&b| b < end - 100);
        let mut i = 0;
        while i < n && !bounces.is_empty() {
            res.push((bounces[rng.next(bounces.len() as i32) as usize], "random".to_string()));
            i += 1;
        }
        // Exit draws are many (one per room): keep every boss fork, a sample of the rest.
        // OrderBy(_ => rng.Next()): every key drawn in order, then a stable sort.
        let mut exits: Vec<(i32, (i64, String))> =
            res.iter().filter(|x| x.1 == "exit draw").map(|x| (rng.next_int(), x.clone())).collect();
        exits.sort_by_key(|e| e.0);
        let exits: Vec<(i64, String)> = exits.into_iter().take(n.max(0) as usize).map(|e| e.1).collect();
        let mut out_: Vec<(i64, String)> = Vec::new();
        for x in res.iter().filter(|x| x.1 != "exit draw").cloned().chain(exits) {
            if x.0 < end - 100 && !out_.contains(&x) {
                out_.push(x);
            }
        }
        out_
    }

    /// Two fresh bots (same seed) on A and B, until a tap or the screen differs:
    /// (first tap difference, first visible difference, crashed).
    fn pair(bot: &BotSpec, r: &BankRun, at: i64, a0: &GameSim, b_sim: &GameSim) -> (i64, i64, bool) {
        let mut a = (bot.make)(r.seed + 77);
        let mut b = (bot.make)(r.seed + 77);
        let mut sa = a0.clone_deep();
        let mut sb = b_sim.clone_deep();
        while sa.state.tick < at + Self::WINDOW && !sa.is_over() && !sb.is_over() {
            let t = sa.state.tick;
            if Visibility::checksum(&sa) != Visibility::checksum(&sb) {
                return (-1, t, false);
            }
            let ta = a(&sa);
            let tb = b(&sb);
            if ta != tb {
                return (t, -1, false);
            }
            sa.step(ta);
            sb.step(tb);
        }
        (-1, -1, false)
    }

    pub fn fork(bot: &BotSpec, r: &BankRun, at: i64, why: &str) -> Fork {
        let sa = Bank::replay(r, at);
        if sa.is_over() {
            return Self::mk(r.seed, at, why, "", "dead", -1, -1, -1, "");
        }
        let room = Bank::key(&sa);
        // The donor: the room this fork is in, drawn again from its entry, flown with the run's taps.
        let mut donor: Option<GameSim> = None;
        if let Some(entry) = r.visits.iter().rev().find(|v| v.tick < at) {
            let pre = Bank::replay(r, entry.tick);
            let set: HashSet<i64> = r.taps.iter().copied().collect();
            let mut k: i64 = 0;
            while k < 64 && donor.is_none() {
                let c = Strat::redraw(&pre, entry.tap, Strat::spine_seed(r.seed, entry.tick, 50_000 + k));
                k += 1;
                let mut c = match c {
                    Some(c) if Run::room_name(&c) == Run::room_name(&sa) => c,
                    _ => continue,
                };
                let ri = c.state.room_index;
                while c.state.tick < at && !c.is_over() && c.state.room_index == ri {
                    let tap = set.contains(&c.state.tick);
                    c.step(tap);
                }
                if c.state.tick == at && !c.is_over() && c.state.room_index == ri {
                    donor = Some(c);
                }
            }
        }
        let a0 = sa.clone_deep();
        let b0 = BlindPlanner::blind_copy(&sa, SimRng::new(Strat::spine_seed(r.seed, at, 99)), -1, 0, -1, false, false);
        let mut b = b0.clone_deep();
        let moved = match &donor {
            None => -1,
            Some(d) => Visibility::transplant(&mut b, d),
        };
        if Visibility::checksum(&a0) != Visibility::checksum(&b) {
            return Self::mk(r.seed, at, why, &room, "visible at fork", -1, at, moved, "");
        }
        let (first_diff, visible_from, crashed) = Self::pair(bot, r, at, &a0, &b);
        if crashed {
            return Self::mk(r.seed, at, why, &room, "crash", -1, -1, moved, "");
        }
        let leak = first_diff >= 0;
        let mut cause = String::new();
        if leak {
            // What did it read? First the replaced RNGs and seeds alone, then each copied field alone.
            if Self::pair(bot, r, at, &a0, &b0).0 >= 0 {
                cause = "an RNG or seed blind_copy replaces".to_string();
            } else if let Some(d) = &donor {
                let mut hits: Vec<String> = Vec::new();
                for f in Visibility::transplant_fields(&b0, d) {
                    let mut one = b0.clone_deep();
                    if !Visibility::transplant_one(&mut one, d, &f) {
                        continue;
                    }
                    if Self::pair(bot, r, at, &a0, &one).0 >= 0 {
                        hits.push(f);
                    }
                }
                cause = if !hits.is_empty() { hits.join(" ") } else { "only several fields together".to_string() };
            }
        }
        Self::mk(r.seed, at, why, &room, if leak { "leak" } else { "same" }, first_diff, visible_from, moved, &cause)
    }
}
