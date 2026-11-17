//! Duel's rules on the server (docs/DUEL_MODE.md, section 3): two players fly
//! the same seed at the same moment, best of three. Each phone streams its taps
//! with the tick it has reached; the server steps both players' Rust sims with
//! them and decides, so a result never comes from a phone.
//!
//! A round is settled when one bird crashed at score S and the other reaches
//! S + 1 (or crashes too), or at the 4-minute cap. Equal scores go to coins,
//! then the round is a draw and one more is played (5 rounds at most). The
//! clock check: a phone may not run ahead of the server's clock since the
//! countdown ended, and one more than 5 s behind it (a lost connection, a
//! phone in the background, slow motion) crashes where it last was.
//!
//! Pure logic with the time passed in, so it is tested without a network.

use sim::game_sim::GameSim;

/// First to two round wins.
pub const FIRST_TO: usize = 2;
/// Draws add rounds; never more than this.
pub const MAX_ROUNDS: usize = 5;
/// The 4-minute cap of a round, in ticks.
pub const ROUND_CAP: i64 = 4 * 60 * 60;
/// How far behind the clock a phone may fall before its bird is down (5 s).
pub const GRACE_TICKS: i64 = 5 * 60;
/// How far ahead of the clock a phone may be (its clock, the network).
pub const AHEAD_TICKS: i64 = 30;
/// A bird waits for its first tap; in a Duel it must come within 3 s of the
/// start, or the bird is down at 0 (no hovering out the round).
pub const START_TICKS: i64 = 3 * 60;
/// Most taps in one message.
pub const MAX_TAPS_PER_BATCH: usize = 64;

pub fn ticks_since(start_ms: i64, now_ms: i64) -> i64 {
    ((now_ms - start_ms).max(0)) * 60 / 1000
}

/// Why a bird is down.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Down {
    Crashed,
    Capped,
    FellBehind,
    Left,
}

pub struct Side {
    pub sim: GameSim,
    /// The tick the phone said it reached; the sim is stepped to here.
    pub last_t: i64,
    pub taps: Vec<i64>,
    pub down: Option<Down>,
}

impl Side {
    fn new(seed: i64, season: i64) -> Side {
        Side { sim: GameSim::with(seed, season, -1, ""), last_t: 0, taps: Vec::new(), down: None }
    }

    pub fn score(&self) -> i64 {
        self.sim.state.score
    }

    pub fn coins(&self) -> i64 {
        self.sim.state.coins
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum RoundResult {
    /// Side 0 or 1.
    Win(usize),
    Draw,
}

pub struct Round {
    pub number: usize,
    pub seed: i64,
    pub season: i64,
    /// When the countdown ended (ms): tick 0 of both runs.
    pub start_ms: i64,
    pub sides: [Side; 2],
    pub result: Option<RoundResult>,
}

impl Round {
    pub fn new(number: usize, seed: i64, season: i64, start_ms: i64) -> Round {
        Round {
            number,
            seed,
            season,
            start_ms,
            sides: [Side::new(seed, season), Side::new(seed, season)],
            result: None,
        }
    }

    /// A phone's batch: it reached tick `t`, tapping at `taps` since its last
    /// batch. Steps that side's sim to `t` (or its crash, or the cap). An
    /// error means the batch breaks the rules and changes nothing.
    pub fn feed(&mut self, who: usize, t: i64, taps: &[i64], now_ms: i64) -> Result<(), String> {
        if self.result.is_some() {
            return Ok(());
        }
        let clock = ticks_since(self.start_ms, now_ms);
        let side = &mut self.sides[who];
        if side.down.is_some() {
            return Ok(());
        }
        if taps.len() > MAX_TAPS_PER_BATCH {
            return Err("too many taps in one message".into());
        }
        if t < side.last_t {
            return Err("ticks went back".into());
        }
        if t > clock + AHEAD_TICKS {
            return Err("ahead of the clock".into());
        }
        let mut prev = side.taps.last().copied().unwrap_or(-1);
        for &tap in taps {
            if tap <= prev || tap < side.last_t || tap >= t.max(side.last_t + 1) {
                return Err("taps out of order".into());
            }
            prev = tap;
        }
        let mut next = 0;
        while side.sim.state.tick < t && !side.sim.is_over() && side.sim.state.tick < ROUND_CAP {
            let tick = side.sim.state.tick;
            let tap = next < taps.len() && taps[next] == tick;
            if tap {
                next += 1;
                side.taps.push(tick);
            }
            side.sim.step(tap);
        }
        side.last_t = t;
        if side.sim.is_over() || (!side.sim.state.started && side.sim.state.tick >= START_TICKS) {
            side.down = Some(Down::Crashed);
        } else if side.sim.state.tick >= ROUND_CAP {
            side.down = Some(Down::Capped);
        }
        Ok(())
    }

    /// The server's clock moved on: a phone more than GRACE_TICKS behind is
    /// down where its bird last was.
    pub fn tick_clock(&mut self, now_ms: i64) {
        let clock = ticks_since(self.start_ms, now_ms);
        for side in self.sides.iter_mut() {
            if side.down.is_none() && clock - side.last_t > GRACE_TICKS {
                side.down = Some(Down::FellBehind);
            }
        }
    }

    /// A player left the round (or the match).
    pub fn leave(&mut self, who: usize) {
        if self.sides[who].down.is_none() {
            self.sides[who].down = Some(Down::Left);
        }
    }

    /// Decides the round when it is settled.
    pub fn judge(&mut self) -> Option<RoundResult> {
        if self.result.is_some() {
            return self.result;
        }
        let [a, b] = &self.sides;
        let r = match (a.down.is_some(), b.down.is_some()) {
            (true, true) => Some(compare(a, b)),
            // One is down at S; the other wins the moment it passes S.
            (true, false) if b.score() > a.score() => Some(RoundResult::Win(1)),
            (false, true) if a.score() > b.score() => Some(RoundResult::Win(0)),
            _ => None,
        };
        self.result = r;
        r
    }
}

fn compare(a: &Side, b: &Side) -> RoundResult {
    if a.score() != b.score() {
        return RoundResult::Win(if a.score() > b.score() { 0 } else { 1 });
    }
    if a.coins() != b.coins() {
        return RoundResult::Win(if a.coins() > b.coins() { 0 } else { 1 });
    }
    RoundResult::Draw
}

/// How a match ended.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Ending {
    /// Side 0 or 1 won by playing.
    Won(usize),
    /// Every round drawn up to MAX_ROUNDS, or level when the last one ended.
    Draw,
    /// Side `.0` left; the other wins.
    Left(usize),
}

/// The match: rounds, wins and its end.
pub struct Match {
    pub rounds: Vec<Round>,
    pub wins: [usize; 2],
    pub ending: Option<Ending>,
}

impl Default for Match {
    fn default() -> Match {
        Match::new()
    }
}

impl Match {
    pub fn new() -> Match {
        Match { rounds: Vec::new(), wins: [0, 0], ending: None }
    }

    pub fn current(&mut self) -> Option<&mut Round> {
        self.rounds.last_mut().filter(|r| r.result.is_none())
    }

    /// The next round on `seed`, its tick 0 at `start_ms`.
    pub fn start_round(&mut self, seed: i64, season: i64, start_ms: i64) -> usize {
        let n = self.rounds.len() + 1;
        self.rounds.push(Round::new(n, seed, season, start_ms));
        n
    }

    /// After a round settled: counts it and ends the match when it is decided.
    pub fn round_settled(&mut self, result: RoundResult) {
        if let RoundResult::Win(w) = result {
            self.wins[w] += 1;
        }
        if self.wins[0] >= FIRST_TO {
            self.ending = Some(Ending::Won(0));
        } else if self.wins[1] >= FIRST_TO {
            self.ending = Some(Ending::Won(1));
        } else if self.rounds.len() >= MAX_ROUNDS {
            self.ending = Some(match self.wins[0].cmp(&self.wins[1]) {
                std::cmp::Ordering::Greater => Ending::Won(0),
                std::cmp::Ordering::Less => Ending::Won(1),
                std::cmp::Ordering::Equal => Ending::Draw,
            });
        }
    }

    pub fn leave(&mut self, who: usize) {
        if self.ending.is_none() {
            if let Some(r) = self.current() {
                r.leave(who);
            }
            self.ending = Some(Ending::Left(who));
        }
    }

    /// Rounds decided so far (a leave after the first round still counts).
    pub fn rounds_played(&self) -> usize {
        self.rounds.iter().filter(|r| r.result.is_some()).count()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    fn golden() -> (i64, i64, Vec<i64>, i64) {
        let path = format!(
            "{}/../tests/replay/golden/g{}_seed_2024.json",
            env!("CARGO_MANIFEST_DIR"),
            sim::sim_config::SimConfig::GAMEPLAY_VERSION
        );
        let g: Value = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        let taps = g["taps"].as_array().unwrap().iter().map(|t| t.as_i64().unwrap()).collect();
        (g["seed"].as_i64().unwrap(), g["season"].as_i64().unwrap(), taps, g["score"].as_i64().unwrap())
    }

    /// Feeds `taps` up to tick `t` in batches of 6 ticks, `now` following the ticks.
    fn fly(r: &mut Round, who: usize, taps: &[i64], to: i64) {
        let mut from = r.sides[who].last_t;
        while from < to && r.sides[who].down.is_none() {
            let t = (from + 6).min(to);
            let batch: Vec<i64> = taps.iter().copied().filter(|x| *x >= from && *x < t).collect();
            r.feed(who, t, &batch, t * 1000 / 60).unwrap();
            from = t;
        }
    }

    #[test]
    fn the_survivor_wins_once_it_passes_the_crashed_score() {
        let (seed, season, taps, score) = golden();
        assert!(score >= 2, "the golden run scores");
        let mut r = Round::new(1, seed, season, 0);
        // Side 1 never taps: down at 0 after 3 s of waiting.
        fly(&mut r, 1, &[], 600);
        assert_eq!(r.sides[1].down, Some(Down::Crashed));
        assert_eq!(r.judge(), None, "side 0 hasn't passed 0 yet");
        let mut t = 0;
        while r.judge().is_none() {
            t += 6;
            fly(&mut r, 0, &taps, t);
        }
        assert_eq!(r.result, Some(RoundResult::Win(0)));
        assert_eq!(r.sides[0].score(), 1, "decided at S + 1, the run still in the air");
        assert!(r.sides[0].down.is_none());
    }

    #[test]
    fn the_same_run_twice_is_a_draw_and_the_server_replays_it_exactly() {
        let (seed, season, taps, score) = golden();
        let mut r = Round::new(1, seed, season, 0);
        fly(&mut r, 0, &taps, ROUND_CAP);
        fly(&mut r, 1, &taps, ROUND_CAP);
        assert_eq!(r.sides[0].score(), score, "the server's sim matches the golden replay");
        assert_eq!(r.judge(), Some(RoundResult::Draw));
    }

    #[test]
    fn the_clock_check() {
        let (seed, season, _, _) = golden();
        let mut r = Round::new(1, seed, season, 0);
        // One second in, a phone claiming two seconds is running fast.
        assert!(r.feed(0, 120, &[], 1000).is_err());
        assert!(r.feed(0, 60 + AHEAD_TICKS, &[], 1000).is_ok());
        assert!(r.feed(0, 10, &[], 1000).is_err(), "ticks never go back");
        assert!(r.feed(0, 100, &[95, 95], 1500).is_err(), "taps out of order");
        // Side 1 says nothing for 6 seconds: down where it was.
        r.tick_clock(6_000);
        assert_eq!(r.sides[1].down, Some(Down::FellBehind));
    }

    #[test]
    fn best_of_three_with_draws_adding_rounds() {
        let mut m = Match::new();
        m.start_round(1, -1, 0);
        m.round_settled(RoundResult::Win(0));
        assert!(m.ending.is_none());
        m.start_round(2, -1, 0);
        m.round_settled(RoundResult::Draw);
        m.start_round(3, -1, 0);
        m.round_settled(RoundResult::Win(1));
        m.start_round(4, -1, 0);
        m.round_settled(RoundResult::Win(0));
        assert_eq!(m.ending, Some(Ending::Won(0)), "first to two");
        let mut d = Match::new();
        for i in 0..MAX_ROUNDS {
            d.start_round(i as i64, -1, 0);
            d.round_settled(RoundResult::Draw);
        }
        assert_eq!(d.ending, Some(Ending::Draw), "five draws");
        let mut l = Match::new();
        l.start_round(1, -1, 0);
        l.leave(1);
        assert_eq!(l.ending, Some(Ending::Left(1)));
        assert_eq!(l.rounds_played(), 0);
    }
}
