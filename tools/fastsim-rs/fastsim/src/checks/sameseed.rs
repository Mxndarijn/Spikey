//! Checks.SameSeedRevive (SameSeed.cs), `fastsim check sameseed`, and the parts of SameSeed it
//! uses (Record, RevivePlay, BotPlay, MapDiffs). The `fastsim sameseed` research mode itself is
//! not ported.
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
    fn hz(sim: &GameSim) -> String {
        let parts: Vec<String> = sim
            .room
            .hazards
            .iter()
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
                        hazards: Self::hz(&sim),
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
            for (k, wa) in &a.walls.list {
                if !k.starts_with(&prefix) {
                    continue;
                }
                let Some(wb) = b.walls.get(k) else { continue };
                let timed = wa.in_room == wb.in_room && wa.hazards == wb.hazards;
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
    /// (seed, die).
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
        out_
    }
}

impl Check for SameSeedRevive {
    fn name(&self) -> &'static str {
        "sameseed"
    }
    fn test(&self) -> &'static str {
        "tools/fastsim/SameSeed.cs"
    }
    fn count(&self) -> usize {
        self.cases().len()
    }

    fn run(&self, n: usize) -> Value {
        let (seed, die) = self.cases()[n];
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
        format!(
            "{} plays ({} seeds x deaths on an even and an odd score), {} revived",
            results.len(),
            Self::SEEDS,
            results.iter().map(|r| i(&r["revived"])).sum::<i64>()
        )
    }
}

/// `fastsim sameseed ...` (SameSeed.run, the research mode). STUB: being ported.
pub fn run_mode(_pos: &[String], _opts: &crate::speed::Opts) -> i32 {
    eprintln!("sameseed: not ported yet");
    2
}
