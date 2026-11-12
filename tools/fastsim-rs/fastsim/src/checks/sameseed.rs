//! Checks.SameSeedRevive (SameSeed.cs), `fastsim check sameseed`, and the parts of SameSeed it
//! uses (Record, RevivePlay, BotPlay, MapDiffs), and the `fastsim sameseed` research mode
//! (SameSeed.run: `run_mode`).
use std::collections::HashMap;
use std::sync::OnceLock;

use serde_json::{json, Value};
use sim::prelude::*;

use super::{i, result, Check};
use crate::bots::PlannerBot;

#[derive(Default, Clone)]
#[allow(dead_code)]
pub struct Wall {
    pub tick: i64,
    pub in_room: i64,
    pub score: i64,
    pub side: i64,
    pub mask: i64,
    pub anchor: i64,
    pub bird_y: i64,
    pub life: i64,
    pub hazards: String,
    pub coin: String,
}

#[derive(Default, Clone)]
#[allow(dead_code)]
pub struct Room {
    pub index: i64,
    pub life: i64,
    pub arrive_tick: i64,
    pub hold: i64,
    pub route: i64,
    pub bird_y: i64,
    pub anchor: i64,
    pub kind: String,
    pub variant: String,
    pub seed: String,
    pub plan: String,
    pub hazards: String,
    pub spikes: String,
    pub ghost: String,
    pub open: String,
    pub taken: String,
    pub ghost_tick: i64,
    pub open_tick: i64,
    pub taken_tick: i64,
}

/// C# Dictionary<string, Wall>: keys in first-insertion order, a set replaces in place.
#[derive(Default)]
pub struct Walls {
    pub list: Vec<(String, Wall)>,
    at: HashMap<String, usize>,
}

impl Walls {
    pub fn set(&mut self, k: String, w: Wall) {
        match self.at.get(&k) {
            Some(&n) => self.list[n].1 = w,
            None => {
                self.at.insert(k.clone(), self.list.len());
                self.list.push((k, w));
            }
        }
    }
    pub fn get(&self, k: &str) -> Option<&Wall> {
        self.at.get(k).map(|&n| &self.list[n].1)
    }
    pub fn get_mut(&mut self, k: &str) -> Option<&mut Wall> {
        match self.at.get(k) {
            Some(&n) => Some(&mut self.list[n].1),
            None => None,
        }
    }
}

#[derive(Default)]
#[allow(dead_code)]
pub struct Play {
    pub name: String,
    pub start_tick: i64,
    pub revive_tick: i64,
    pub death_tick: i64,
    pub death: String,
    pub rooms: Vec<Room>,
    pub walls: Walls,
}

pub struct SameSeed;

impl SameSeed {
    /// The hazards' states at a room's arrival, but for those that follow the
    /// bird by design: the Echo's shadow flies the bird's own path, and a coin
    /// is taken by whoever flies through it (as coin spawns, a player's choice).
    /// At a wall every hazard counts (`hz_all`): a wall that follows a hazard the
    /// bird changed is not compared.
    fn hz(sim: &GameSim) -> String {
        Self::hz_of(sim, true)
    }

    fn hz_all(sim: &GameSim) -> String {
        Self::hz_of(sim, false)
    }

    fn hz_of(sim: &GameSim, skip_bird: bool) -> String {
        let parts: Vec<String> = sim
            .room
            .hazards
            .iter()
            .filter(|h| !skip_bird || (h.kind() != "echo" && h.kind() != "coin"))
            .map(|h| format!("{}:{:x}", h.kind(), if h.alive() { h.checksum(0) & 0xffff } else { -1i64 }))
            .collect();
        parts.join(",")
    }

    fn new_room(sim: &GameSim, life: i64, tick: i64) -> Room {
        let st = &sim.state;
        Room {
            index: st.room_index,
            life,
            arrive_tick: tick,
            hold: st.arrival_hold,
            route: st.route,
            bird_y: st.y / SimConfig::SUB,
            anchor: st.anchor_y / SimConfig::SUB,
            kind: RoomCatalog::all()[st.room_kind as usize].id.to_string(),
            variant: sim.room.variant_id().to_string(),
            seed: format!("{:x}", sim.room.rng_seed),
            plan: format!(
                "L {}/{} R {}/{}",
                st.plan_a_y_left / SimConfig::SUB,
                st.plan_b_y_left / SimConfig::SUB,
                st.plan_a_y_right / SimConfig::SUB,
                st.plan_b_y_right / SimConfig::SUB
            ),
            hazards: Self::hz(sim),
            spikes: format!("{:x}|{:x}", st.left_spikes, st.right_spikes),
            ghost: String::new(),
            open: String::new(),
            taken: String::new(),
            ghost_tick: -1,
            open_tick: -1,
            taken_tick: -1,
        }
    }

    /// C# Record's `rel`: a tick from the run's start (0 before it).
    fn rel(start_tick: i64, t: i64) -> i64 {
        if start_tick < 0 { 0 } else { t - start_tick }
    }

    fn exit_text(st: &SimState) -> String {
        format!("side {} y {}", st.exit_side, st.exit_a_y / SimConfig::SUB)
            + &if st.exit_b_kind != ExitKind::NORMAL { format!("/{}", st.exit_b_y / SimConfig::SUB) } else { String::new() }
    }

    fn record(
        name: &str,
        mut sim: GameSim,
        mut decide: impl FnMut(&GameSim) -> Option<bool>,
        revive: bool,
        max_ticks: i64,
    ) -> Play {
        let mut p = Play {
            name: name.to_string(),
            start_tick: -1,
            revive_tick: -1,
            death_tick: -1,
            ..Default::default()
        };
        let mut life: i64 = 0;
        p.rooms.push(Self::new_room(&sim, life, 0));
        let mut cur = p.rooms.len() - 1;
        let mut steps: i64 = 0;
        while steps < max_ticks {
            let d = decide(&sim);
            let Some(d) = d else { break };
            steps += 1;
            sim.step(d);
            let events = sim.events.clone();
            for e in events {
                let st = &sim.state;
                if e == Event::START {
                    p.start_tick = st.tick - 1;
                }
                let rel = |t: i64| Self::rel(p.start_tick, t);
                if e == Event::ROOM_CHANGE {
                    let t = rel(st.tick);
                    p.rooms[cur].taken_tick = t;
                    p.rooms[cur].taken = format!("{}", st.anchor_y / SimConfig::SUB);
                    p.rooms.push(Self::new_room(&sim, life, t));
                    cur = p.rooms.len() - 1;
                }
                let st = &sim.state;
                let rel = |t: i64| Self::rel(p.start_tick, t);
                if e == Event::EXIT_PREVIEW && p.rooms[cur].ghost_tick < 0 {
                    let t = rel(st.tick);
                    p.rooms[cur].ghost_tick = t;
                    p.rooms[cur].ghost = Self::exit_text(st);
                }
                if e == Event::EXIT_OPEN && p.rooms[cur].open_tick < 0 {
                    let t = rel(st.tick);
                    p.rooms[cur].open_tick = t;
                    p.rooms[cur].open = Self::exit_text(st);
                }
                if e == Event::BOUNCE || e == Event::ROOM_CHANGE {
                    let side = if st.vx > 0 { 1 } else { 0 };
                    let w = Wall {
                        tick: rel(st.tick),
                        in_room: rel(st.tick) - p.rooms[cur].arrive_tick,
                        score: st.score,
                        side,
                        mask: if side == 0 { st.left_spikes } else { st.right_spikes },
                        anchor: st.anchor_y / SimConfig::SUB,
                        bird_y: st.y / SimConfig::SUB,
                        life,
                        hazards: Self::hz_all(&sim),
                        coin: String::new(),
                    };
                    p.walls.set(format!("{}:{}", st.room_index, sim.room.walls), w);
                }
                if e == Event::COIN_SPAWN {
                    let k = format!("{}:{}", st.room_index, sim.room.walls);
                    let coin = format!("{},{}", st.coin_x / SimConfig::SUB, st.coin_y / SimConfig::SUB);
                    if let Some(w) = p.walls.get_mut(&k) {
                        w.coin = coin;
                    }
                }
            }
            if !sim.state.alive {
                let rel = |t: i64| Self::rel(p.start_tick, t);
                let st = &sim.state;
                p.death_tick = rel(st.tick);
                p.death = format!("{} room {} score {}", st.death_cause, st.room_index, st.score);
                if sim.can_revive() && revive {
                    sim.revive();
                    life += 1;
                    let t = rel(sim.state.tick);
                    p.revive_tick = t;
                    p.rooms.push(Self::new_room(&sim, life, t));
                    cur = p.rooms.len() - 1;
                    continue;
                }
                break;
            }
        }
        p
    }

    /// Bot seed 1 until room 2 or later with a score ending in `die`, then no taps until the bird
    /// dies, a revive, and on with the bot.
    pub fn revive_play(sim: GameSim, die: i64, max_ticks: i64) -> Play {
        let mut bot = PlannerBot::new(1, PlannerBot::HORIZON, PlannerBot::ROLLOUTS);
        let mut dying = false;
        let mut done = false;
        Self::record(
            "R (revive)",
            sim,
            |s| {
                if !done
                    && !dying
                    && s.state.room_index >= 2
                    && s.state.score % 10 == die
                    && !s.state.exit_preview
                    && s.state.arrival_hold == 0
                {
                    dying = true;
                }
                if dying && s.state.revives == 0 {
                    return Some(false);
                }
                if dying {
                    dying = false;
                    done = true;
                }
                Some(bot.decide(s))
            },
            true,
            max_ticks,
        )
    }

    pub fn bot_play(sim: GameSim, max_ticks: i64) -> Play {
        let mut bot = PlannerBot::new(1, PlannerBot::HORIZON, PlannerBot::ROLLOUTS);
        Self::record("A", sim, |s| Some(bot.decide(s)), false, max_ticks)
    }

    /// What differs in the map between a play and a revived play, in the rooms both reached (see
    /// SameSeed.cs MapDiffs).
    pub fn map_diffs(a: &Play, b: &Play) -> Vec<String> {
        let mut out_ = Vec::new();
        for ra in &a.rooms {
            let Some(rb) = b.rooms.iter().rev().find(|r| r.index == ra.index) else { continue };
            let played_apart = ra.open_tick >= 0
                && rb.open_tick >= 0
                && ra.open_tick - ra.arrive_tick - ra.hold != rb.open_tick - rb.arrive_tick - rb.hold;
            let head = format!("room {} {}/{}", ra.index, ra.kind, ra.variant);
            if ra.kind != rb.kind {
                out_.push(format!("{}: room kind {} vs {}", head, ra.kind, rb.kind));
            }
            if ra.variant != rb.variant {
                out_.push(format!("{}: variant {} vs {}", head, ra.variant, rb.variant));
            }
            if ra.seed != rb.seed {
                out_.push(format!("{}: room seed {} vs {}", head, ra.seed, rb.seed));
            }
            if ra.plan != rb.plan {
                out_.push(format!("{}: plan {} vs {}", head, ra.plan, rb.plan));
            }
            if ra.hazards != rb.hazards {
                out_.push(format!("{}: hazards at arrival differ", head));
            }
            if ra.spikes != rb.spikes {
                out_.push(format!("{}: arrival spikes {} vs {}", head, ra.spikes, rb.spikes));
            }
            if played_apart {
                break;
            }
            if !ra.ghost.is_empty() && !rb.ghost.is_empty() && ra.ghost != rb.ghost {
                out_.push(format!("{}: ghost {} vs {}", head, ra.ghost, rb.ghost));
            }
            if !ra.open.is_empty() && !rb.open.is_empty() && ra.open != rb.open {
                out_.push(format!("{}: open {} vs {}", head, ra.open, rb.open));
            }
            let prefix = format!("{}:", ra.index);
            // Each wall's anchor follows the last one, so once a wall was met at
            // another tick or with the hazards elsewhere (a key taken later), the
            // later walls of the room may differ too: only side and score then.
            let mut apart = false;
            for (k, wa) in &a.walls.list {
                if !k.starts_with(&prefix) {
                    continue;
                }
                let Some(wb) = b.walls.get(k) else { continue };
                // A room entered by the other exit of a fork has more spikes on
                // every wall after its arrival (WILD_SPIKES): a player's choice.
                let timed = !apart && wa.in_room == wb.in_room && wa.hazards == wb.hazards && ra.route == rb.route;
                apart = !timed;
                if wa.side != wb.side || wa.score != wb.score || timed && (wa.mask != wb.mask || wa.anchor != wb.anchor) {
                    out_.push(format!(
                        "{} wall {}: spikes {:x}/{:x} side {}/{} score {}/{} anchor {}/{}",
                        head,
                        k.split(':').nth(1).unwrap_or(""),
                        wa.mask,
                        wb.mask,
                        wa.side,
                        wb.side,
                        wa.score,
                        wb.score,
                        wa.anchor,
                        wb.anchor
                    ));
                }
            }
        }
        out_
    }
}

/// A revive restarts the room as the bird came in, score and coins too, so the rest of the run is
/// the map a player who never died there meets: PlannerBot without a death vs the same bot with
/// a death and a revive in room 2 or later, on an even and an odd score (docs/REVIVE.md).
#[derive(Default)]
pub struct SameSeedRevive {
    /// (seed, die), or (-1 - generated variant number, anchor slot) for a generated-variant case.
    _cases: OnceLock<Vec<(i64, i64)>>,
}

impl SameSeedRevive {
    pub const SEEDS: i64 = 24;
    pub const TICKS: i64 = 20000;

    fn cases(&self) -> &Vec<(i64, i64)> {
        self._cases.get_or_init(Self::make)
    }

    fn make() -> Vec<(i64, i64)> {
        let mut out_ = Vec::new();
        for s in 0..Self::SEEDS {
            for die in [4i64, 5] {
                out_.push((4206176851i64 + s * 7919, die));
            }
        }
        for g in 0..Self::generated().len() {
            for slot in 0..Self::GEN_ANCHORS.len() {
                out_.push((-1 - g as i64, slot as i64));
            }
        }
        out_
    }

    /// Planned exit heights (px) the generated-variant cases come out of.
    pub const GEN_ANCHORS: [i64; 5] = [120, 220, 320, 420, 520];
    pub const GEN_SEEDS: i64 = 3;

    /// Every GENERATED room variant: (room index, variant id).
    fn generated() -> Vec<(usize, &'static str)> {
        let mut out_ = Vec::new();
        for (i, def) in RoomCatalog::all().iter().enumerate() {
            for v in &def.variants {
                if v.kind == Kind::GENERATED {
                    out_.push((i, v.id));
                }
            }
        }
        out_
    }

    /// The layout as built out of the portal: every hazard's kind and checksum (positions and
    /// sizes), the Echo's turning height only (the shadow itself follows the bird by design).
    fn layout(sim: &GameSim) -> String {
        let parts: Vec<String> = sim
            .room
            .hazards
            .iter()
            .map(|h| match h {
                Hz::Echo(e) => format!("echo:{}:{}", e.mode, e.pivot_y),
                _ => format!("{}:{}:{:x}", h.kind(), h.alive(), h.checksum(0)),
            })
            .collect();
        format!("{}/{} {}", sim.room.def().id, sim.room.variant_id(), parts.join(","))
    }

    /// Practice in the variant, then through the exit at `exit_px` (kind NORMAL, CALM or WILD)
    /// with the bird `dy_px` from the exit's middle (taps and timing differ only in that).
    fn gen_arrival(index: usize, variant: &'static str, seed: i64, side: i64, kind: i64, exit_px: i64, dy_px: i64) -> String {
        let def = &RoomCatalog::all()[index];
        let mut sim = GameSim::with(seed, def.season, index as i64, variant);
        sim.step(true);
        let every = SimConfig::POINTS_PER_ROOM;
        sim.state.score = G::maxi(every, (def.from_score + every - 1) / every * every);
        let through = exit_px * SimConfig::SUB;
        sim.state.y = through + dy_px * SimConfig::SUB;
        sim._go_through(side, kind, through);
        Self::layout(&sim)
    }

    /// The same layout whatever the bird did: two heights in the exit, both ways in, and at a
    /// fork the Calm and the Wild exit (both lead to one door).
    fn run_generated(g: usize, slot: usize) -> Vec<String> {
        let (index, variant) = Self::generated()[g];
        let exit_px = Self::GEN_ANCHORS[slot];
        let mut fails = Vec::new();
        for k in 0..Self::GEN_SEEDS {
            let seed = 77_001 + k * 104_729 + slot as i64 * 13;
            for side in 0..2 {
                let a = Self::gen_arrival(index, variant, seed, side, ExitKind::NORMAL, exit_px, 40);
                let b = Self::gen_arrival(index, variant, seed, side, ExitKind::NORMAL, exit_px, -40);
                if a != b {
                    fails.push(format!("{}: exit {} px, side {}, seed {}: bird +40 / -40 px give different layouts", variant, exit_px, side, seed));
                }
                let c = Self::gen_arrival(index, variant, seed, side, ExitKind::CALM, exit_px, 20);
                let d = Self::gen_arrival(index, variant, seed, side, ExitKind::WILD, G::mini(exit_px + 80, 520), -30);
                if c != d {
                    fails.push(format!("{}: fork near {} px, side {}, seed {}: Calm and Wild give different layouts", variant, exit_px, side, seed));
                }
            }
        }
        fails
    }
}

impl Check for SameSeedRevive {
    fn name(&self) -> &'static str {
        "sameseed"
    }
    fn test(&self) -> &'static str {
        "tools/fastsim-rs/fastsim/src/checks/sameseed.rs"
    }
    fn count(&self) -> usize {
        self.cases().len()
    }

    fn run(&self, n: usize) -> Value {
        let (seed, die) = self.cases()[n];
        if seed < 0 {
            let fails = Self::run_generated((-1 - seed) as usize, die as usize);
            return result(fails, json!({ "generated": 1 }));
        }
        let a = SameSeed::bot_play(GameSim::new(seed), Self::TICKS);
        let r = SameSeed::revive_play(GameSim::new(seed), die, Self::TICKS + 600);
        let mut fails = Vec::new();
        if r.revive_tick >= 0 {
            for d in SameSeed::map_diffs(&a, &r) {
                fails.push(format!("seed {}, death on a score ending in {}: {}", seed, die, d));
            }
        }
        result(fails, json!({ "revived": if r.revive_tick >= 0 { 1 } else { 0 } }))
    }

    fn summary(&self, results: &[Value]) -> String {
        let gen = results.iter().map(|r| i(&r["generated"])).sum::<i64>();
        format!(
            "{} plays ({} seeds x deaths on an even and an odd score), {} revived; {} generated variants x {} exits x {} seeds: same layout for two bird heights and for Calm / Wild",
            results.len() as i64 - gen,
            Self::SEEDS,
            results.iter().map(|r| i(&r["revived"])).sum::<i64>(),
            gen / Self::GEN_ANCHORS.len() as i64,
            Self::GEN_ANCHORS.len(),
            Self::GEN_SEEDS
        )
    }
}

impl SameSeed {
    /// At an open fork on the wall ahead: flap to hold the Calm exit's height.
    fn calm(sim: &GameSim) -> Option<bool> {
        let s = &sim.state;
        let heading = if s.vx > 0 { 1 } else { 0 };
        if !s.exit_open || s.exit_side != heading || s.exit_b_kind == ExitKind::NORMAL {
            return None;
        }
        let target = if s.exit_a_kind == ExitKind::CALM { s.exit_a_y } else { s.exit_b_y };
        let margin = 6 * SimConfig::SUB;
        if sim.room.gravity < 0 {
            return Some(s.y < target - margin && s.vy <= 0);
        }
        Some(s.y > target + margin && s.vy >= 0)
    }

    /// `JsonSerializer.SerializeToNode(p, IncludeFields)`: the fields in declaration order.
    fn play_json(p: &Play) -> Value {
        let rooms: Vec<Value> = p
            .rooms
            .iter()
            .map(|r| {
                json!({
                    "index": r.index, "life": r.life, "arrive_tick": r.arrive_tick, "hold": r.hold,
                    "route": r.route, "bird_y": r.bird_y, "anchor": r.anchor,
                    "kind": r.kind, "variant": r.variant, "seed": r.seed, "plan": r.plan,
                    "hazards": r.hazards, "spikes": r.spikes, "ghost": r.ghost, "open": r.open,
                    "taken": r.taken, "ghost_tick": r.ghost_tick, "open_tick": r.open_tick,
                    "taken_tick": r.taken_tick,
                })
            })
            .collect();
        let mut walls = serde_json::Map::new();
        for (k, w) in &p.walls.list {
            walls.insert(
                k.clone(),
                json!({
                    "tick": w.tick, "in_room": w.in_room, "score": w.score, "side": w.side,
                    "mask": w.mask, "anchor": w.anchor, "bird_y": w.bird_y, "life": w.life,
                    "hazards": w.hazards, "coin": w.coin,
                }),
            );
        }
        json!({
            "name": p.name, "start_tick": p.start_tick, "revive_tick": p.revive_tick,
            "death_tick": p.death_tick, "death": p.death, "rooms": rooms, "walls": Value::Object(walls),
        })
    }
}

/// `fastsim sameseed <seed> [season] [ticks] --out file.json` (SameSeed.run; pos[0] = the seed):
/// plays one seed several ways (different taps, and one play with a revive) and lists what
/// differs between the plays: rooms, variants, room seeds, exits (planned, ghost, open, taken),
/// wall spikes, anchors, hazard states at each bounce and coin spawns. A research tool: it never
/// changes the sim.
pub fn run_mode(pos: &[String], opts: &crate::speed::Opts) -> i32 {
    let seed: i64 = pos.first().map(|s| s.as_str()).unwrap_or("3392377610").parse().expect("seed");
    let season: i64 = pos.get(1).map(|s| s.as_str()).unwrap_or("-1").parse().expect("season");
    let ticks: i64 = pos.get(2).map(|s| s.as_str()).unwrap_or("20000").parse().expect("ticks");
    let start = || GameSim::with(seed, season, -1, "");

    let die: i64 = opts.get("die").map(|s| s.as_str()).unwrap_or("4").parse().expect("--die");
    let only_r = opts.contains_key("onlyrevive");
    let mut plays: Vec<Play> = Vec::new();
    // A, B: PlannerBot with two bot seeds (it aims for the Wild exit at a fork).
    let ab: &[(&str, i64)] = if only_r { &[("A", 1)] } else { &[("A", 1), ("B", 2)] };
    for &(nm, bs) in ab {
        let mut bot = PlannerBot::new(bs, PlannerBot::HORIZON, PlannerBot::ROLLOUTS);
        plays.push(SameSeed::record(nm, start(), |s| Some(bot.decide(s)), false, ticks));
    }
    // C: bot seed 3, and it takes the Calm exit at every fork.
    if !only_r {
        let mut bot = PlannerBot::new(3, PlannerBot::HORIZON, PlannerBot::ROLLOUTS);
        plays.push(SameSeed::record(
            "C (calm)",
            start(),
            |s| Some(SameSeed::calm(s).unwrap_or_else(|| bot.decide(s))),
            false,
            ticks,
        ));
    }
    // R: bot seed 1 until the middle of room 2 (score ends in `die`), then no taps until the bird
    // dies, a revive, and on with the bot.
    plays.push(SameSeed::revive_play(start(), die, ticks + 600));
    let mut arr: Vec<Value> = Vec::new();
    for p in &plays {
        println!(
            "== play {}: {} rooms, {} walls, death {} at {}, revive at {}",
            p.name,
            p.rooms.len(),
            p.walls.list.len(),
            p.death,
            p.death_tick,
            p.revive_tick
        );
        for r in &p.rooms {
            println!(
                "  room {} life {} {}/{} seed {} in@{} hold {} route {} anchor {} bird {} plan [{}] ghost@{} {} open@{} {} taken@{}",
                r.index,
                r.life,
                r.kind,
                r.variant,
                r.seed,
                r.arrive_tick,
                r.hold,
                r.route,
                r.anchor,
                r.bird_y,
                r.plan,
                r.ghost_tick,
                r.ghost,
                r.open_tick,
                r.open,
                r.taken_tick
            );
        }
        arr.push(SameSeed::play_json(p));
    }

    // Diffs against play A.
    let mut diffs: Vec<Value> = Vec::new();
    let a = &plays[0];
    for p in plays.iter().skip(1) {
        println!("-- A vs {}", p.name);
        let (mut same_walls, mut diff_walls, mut cmp_walls) = (0, 0, 0);
        for ra in &a.rooms {
            let Some(rb) = p.rooms.iter().rev().find(|r| r.index == ra.index) else { continue };
            let mut fields: Vec<String> = Vec::new();
            if ra.kind != rb.kind {
                fields.push(format!("room kind {} vs {}", ra.kind, rb.kind));
            }
            if ra.variant != rb.variant {
                fields.push(format!("variant {} vs {}", ra.variant, rb.variant));
            }
            if ra.seed != rb.seed {
                fields.push(format!("room seed {} vs {}", ra.seed, rb.seed));
            }
            if ra.plan != rb.plan {
                fields.push(format!("plan {} vs {}", ra.plan, rb.plan));
            }
            if ra.arrive_tick != rb.arrive_tick {
                fields.push(format!("arrive tick {} vs {}", ra.arrive_tick, rb.arrive_tick));
            }
            if rb.life != ra.life {
                fields.push("after a revive".to_string());
            }
            if ra.hold != rb.hold {
                fields.push(format!("hold {} vs {}", ra.hold, rb.hold));
            }
            if ra.hazards != rb.hazards {
                fields.push("hazards at arrival differ".to_string());
            }
            if ra.spikes != rb.spikes {
                fields.push(format!("arrival spikes {} vs {}", ra.spikes, rb.spikes));
            }
            if ra.bird_y != rb.bird_y {
                fields.push(format!("bird y at portal {} vs {}", ra.bird_y, rb.bird_y));
            }
            if ra.ghost != rb.ghost && !ra.ghost.is_empty() && !rb.ghost.is_empty() {
                fields.push(format!("ghost {} vs {}", ra.ghost, rb.ghost));
            }
            if ra.ghost_tick >= 0 && rb.ghost_tick >= 0 && ra.ghost_tick - ra.arrive_tick != rb.ghost_tick - rb.arrive_tick {
                fields.push(format!(
                    "ghost tick in room {} vs {}",
                    ra.ghost_tick - ra.arrive_tick,
                    rb.ghost_tick - rb.arrive_tick
                ));
            }
            if ra.open != rb.open && !ra.open.is_empty() && !rb.open.is_empty() {
                fields.push(format!("open {} vs {}", ra.open, rb.open));
            }
            if ra.open_tick >= 0 && rb.open_tick >= 0 && ra.open_tick - ra.arrive_tick != rb.open_tick - rb.arrive_tick {
                fields.push(format!(
                    "open tick in room {} vs {}",
                    ra.open_tick - ra.arrive_tick,
                    rb.open_tick - rb.arrive_tick
                ));
            }
            let mut wd: Vec<String> = Vec::new();
            let prefix = format!("{}:", ra.index);
            // Each wall's anchor follows the last one, so once a wall was met at
            // another tick or with the hazards elsewhere (a key taken later), the
            // later walls of the room may differ too: only side and score then.
            let mut apart = false;
            for (k, wa) in &a.walls.list {
                if !k.starts_with(&prefix) {
                    continue;
                }
                let Some(wb) = p.walls.get(k) else { continue };
                cmp_walls += 1;
                let mut f: Vec<String> = Vec::new();
                if wa.mask != wb.mask {
                    f.push(format!("spikes {:x} vs {:x}", wa.mask, wb.mask));
                }
                if wa.in_room != wb.in_room {
                    f.push(format!("tick in room {} vs {}", wa.in_room, wb.in_room));
                }
                if wa.score != wb.score {
                    f.push(format!("score {} vs {}", wa.score, wb.score));
                }
                if wa.side != wb.side {
                    f.push(format!("side {} vs {}", wa.side, wb.side));
                }
                if wa.anchor != wb.anchor {
                    f.push(format!("anchor {} vs {}", wa.anchor, wb.anchor));
                }
                if wa.coin != wb.coin {
                    f.push(format!("coin {} vs {}", wa.coin, wb.coin));
                }
                if wa.hazards != wb.hazards {
                    let ha: Vec<&str> = wa.hazards.split(',').collect();
                    let hb: Vec<&str> = wb.hazards.split(',').collect();
                    let mut kinds: Vec<&str> = Vec::new();
                    for q in 0..ha.len().min(hb.len()) {
                        if ha[q] != hb[q] {
                            let kind = ha[q].split(':').next().unwrap_or("");
                            // Distinct (first-seen order).
                            if !kinds.contains(&kind) {
                                kinds.push(kind);
                            }
                        }
                    }
                    f.push(format!("hazard state differs: {}", kinds.join("+")));
                }
                if f.is_empty() {
                    same_walls += 1;
                } else {
                    diff_walls += 1;
                    wd.push(format!("wall {} (score {}): {}", k.split(':').nth(1).unwrap_or(""), wa.score, f.join("; ")));
                }
            }
            let head = format!("room {} {}/{}", ra.index, ra.kind, ra.variant);
            println!("  {}: {}", head, if fields.is_empty() { "same".to_string() } else { fields.join("; ") });
            for w in &wd {
                println!("    {}", w);
            }
            diffs.push(json!({
                "vs": p.name, "room": ra.index, "kind": ra.kind, "variant": ra.variant,
                "room_diffs": fields, "wall_diffs": wd,
            }));
        }
        println!("  walls compared {}: same {}, differ {}", cmp_walls, same_walls, diff_walls);
    }
    let outj = json!({ "seed": seed, "season": season, "plays": arr, "diffs": diffs });
    if let Some(file) = opts.get("out") {
        std::fs::write(file, crate::yardstick::json_pretty(&outj)).expect("--out");
    }
    0
}
