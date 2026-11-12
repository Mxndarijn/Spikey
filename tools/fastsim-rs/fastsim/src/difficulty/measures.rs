//! Port of Difficulty/Measures.cs: bot survival per room entry (BotPlay) and the reaction
//! sweep (ReactSweep).
use std::collections::HashSet;

use sim::prelude::*;

use super::cases::{Cases, Target};
use crate::bots::boss_blind::BossBlind;
use crate::bots::{BlindPlanner, SurvivalSearch};
use crate::human::motor_player::{MotorPlayer, MotorTiers};

type Decide = Box<dyn FnMut(&GameSim) -> bool>;

/// Bot survival per room entry: the human-like tiers (MotorPlayer on
/// BlindPlanner, docs/HUMAN_BOT.md) and the honest BlindPlanner.
pub struct BotPlay;

impl BotPlay {
    pub const BOTS: [&'static str; 6] = ["beginner", "normal", "good", "expert", "beast", "honest"];

    pub fn make(bot: &str, seed: i64) -> Decide {
        match bot {
            "honest" => {
                let mut bp = BlindPlanner::new(seed);
                bp.horizon = 200;
                bp.past = 110;
                bp.margin = 10;
                Box::new(move |s: &GameSim| bp.decide(s))
            }
            _ => {
                let mut mp = MotorPlayer::new(MotorTiers::of(bot), seed, None);
                Box::new(move |s: &GameSim| mp.decide(s))
            }
        }
    }

    /// (cleared, ticks, death cause or "cap").
    pub fn play(target: &Target, trial: i64, bot: &str) -> Result<(bool, i64, String), String> {
        let mut sim = Cases::arrive(target, trial)?;
        let room = sim.state.room_index;
        let mut d = Self::make(bot, 1000 + trial * 7919 + target.index as i64);
        for t in 0..target.cap {
            let tap = d(&sim);
            sim.step(tap);
            if Cases::cleared(&sim, room) {
                return Ok((true, t + 1, String::new()));
            }
            if sim.is_over() {
                return Ok((false, t + 1, DeathCause::NAMES[sim.state.death_cause as usize].to_string()));
            }
        }
        Ok((false, target.cap, "cap".to_string()))
    }
}

/// The reaction sweep (the boss review's fairness sweep, BossRuns.fair, for
/// every room). The honest planner plays the entry. Each time something new
/// shows (new spikes on the wall ahead, a hazard appearing, a boss tell), the
/// bird keeps the plan it had before for R ticks, then SurvivalSearch (exact
/// knowledge) looks for a way to live until the next new thing plus 1 s.
///   verdict at R: 1 a way, 0 no way, -1 the old plan died within R.
/// At R = 0 a "no way" means the bird was already doomed when the thing showed
/// (the planner's own earlier mistake, or a room that dooms before it shows).
pub struct ReactSweep;

#[derive(Clone, Debug)]
pub struct Row {
    pub tick: i64,
    pub kind: &'static str,
    pub verdict: Vec<i64>,
}

struct Shown {
    tick: i64,
    kind: &'static str,
    sim: GameSim,
    plan: Vec<u8>,
}

impl ReactSweep {
    pub const REACTS: [i64; 4] = [0, 20, 40, 60];
    pub const AFTER: i64 = 59;

    pub fn run(target: &Target, trial: i64) -> Result<Vec<Row>, String> {
        let mut sim = Cases::arrive(target, trial)?;
        let room = sim.state.room_index;
        let mut bp = BlindPlanner::new(2000 + trial * 104729 + target.index as i64);
        bp.horizon = 200;
        bp.past = 110;
        bp.margin = 10;
        let mut shown: Vec<Shown> = Vec::new();
        // C# keeps the hazard objects (reference identity); hazards are never removed or
        // reordered in the room list, so the slot is the identity.
        let mut known: HashSet<usize> = HashSet::new();
        for (j, h) in sim.room.hazards.iter().enumerate() {
            if h.base().alive {
                known.insert(j);
            }
        }
        let mut score = sim.state.score;
        let mut tell = Self::boss_key(&sim);
        for _t in 0..target.cap {
            let tap = bp.decide(&sim);
            sim.step(tap);
            if sim.is_over() || Cases::cleared(&sim, room) {
                break;
            }
            let mut kind: Option<&'static str> = None;
            if sim.state.score != score {
                kind = Some("wall");
            }
            for (j, h) in sim.room.hazards.iter().enumerate() {
                if h.base().alive && known.insert(j) && kind.is_none() {
                    kind = Some("hazard");
                }
            }
            let k = Self::boss_key(&sim);
            if k != tell && kind.is_none() {
                kind = Some("tell");
            }
            score = sim.state.score;
            tell = k;
            if let Some(kind) = kind {
                if sim.state.arrival_hold <= 0 {
                    let plan: Vec<u8> = bp.plan().iter().map(|&x| if x { 1 } else { 0 }).collect();
                    shown.push(Shown { tick: sim.state.tick, kind, sim: sim.clone_deep(), plan });
                }
            }
        }
        let mut rows = Vec::new();
        for i in 0..shown.len() {
            let s = &shown[i];
            let next = if i + 1 < shown.len() { shown[i + 1].tick } else { s.tick + 120 };
            let mut v = vec![0i64; Self::REACTS.len()];
            for j in 0..Self::REACTS.len() {
                let r = Self::REACTS[j];
                let mut c = s.sim.clone_deep();
                let mut verdict = 1;
                let mut u = 0;
                while u < r && verdict == 1 {
                    c.step((u as usize) < s.plan.len() && s.plan[u as usize] != 0);
                    if Cases::cleared(&c, room) {
                        break;
                    }
                    if c.is_over() {
                        verdict = -1;
                    }
                    u += 1;
                }
                if verdict == 1 && !Cases::cleared(&c, room) {
                    let h = G::maxi(30, next + Self::AFTER - (s.tick + r));
                    if !SurvivalSearch::new().run(&c, h) {
                        verdict = 0;
                    }
                }
                v[j] = verdict;
            }
            rows.push(Row { tick: s.tick, kind: s.kind, verdict: v });
        }
        Ok(rows)
    }

    fn boss_key(s: &GameSim) -> i64 {
        for h in &s.room.hazards {
            if let Some(b) = h.as_boss() {
                return if b.down_at >= 0 { -1 } else { BossBlind::tell_key(h) };
            }
        }
        0
    }
}
