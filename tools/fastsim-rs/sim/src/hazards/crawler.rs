//! Port of sim/hazards/crawler.gd (Sim/Hazards/Crawler.cs).
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct Crawler {
    pub base: Base,
    pub lane: i64,
    pub start: i64,
    pub segments: i64,
    pub seg_radius: i64,
    pub spacing: i64,
    pub speed: i64,
    pub reserve: i64,
    pub trails: bool,
    pub xs: Vec<i64>,
    pub ys: Vec<i64>,
}

impl Crawler {
    pub const SEGMENTS: i64 = 6;
    pub const SEG_RADIUS: i64 = 10 * SimConfig::SUB;
    pub const SPACING: i64 = 22 * SimConfig::SUB;
    pub const SPEED: i64 = SimConfig::SUB;
    pub const LEFT: i64 = 60 * SimConfig::SUB;
    pub const RIGHT: i64 = 300 * SimConfig::SUB;
    pub const TOP: i64 = 80 * SimConfig::SUB;
    pub const BOTTOM: i64 = 560 * SimConfig::SUB;
    pub const W: i64 = Self::RIGHT - Self::LEFT;
    pub const H: i64 = Self::BOTTOM - Self::TOP;
    pub const PERIMETER: i64 = 2 * (Self::W + Self::H);
    pub const CORNER_CLEAR: i64 = 50 * SimConfig::SUB;

    pub const SWARM_SEGMENTS: i64 = 4;
    pub const SWARM_RADIUS: i64 = 7 * SimConfig::SUB;
    pub const SWARM_SPACING: i64 = 15 * SimConfig::SUB;
    pub const SWARM_GAP: i64 = 50 * SimConfig::SUB;
    pub const SPRINT_SEGMENTS: i64 = 5;
    pub const SPRINT_SPEED: i64 = 2 * SimConfig::SUB;
    pub const FREE_RUN: i64 = 3;
    pub const FAR: i64 = 1i64 << 30;

    /// C# default: p_lane = 0.
    pub fn new(p_lane: i64) -> Crawler {
        Crawler {
            base: Base::new("crawler"),
            lane: p_lane,
            start: 0,
            segments: Self::SEGMENTS,
            seg_radius: Self::SEG_RADIUS,
            spacing: Self::SPACING,
            speed: Self::SPEED,
            reserve: 0,
            trails: false,
            xs: Vec::new(),
            ys: Vec::new(),
        }
    }

    fn _resize(l: &mut Vec<i64>, n: i64) {
        while (l.len() as i64) < n {
            l.push(0);
        }
        if l.len() as i64 > n {
            l.truncate(n as usize);
        }
    }

    pub fn swarm(mut self) -> Crawler {
        self.swarm_in_place();
        self
    }

    fn swarm_in_place(&mut self) {
        self.segments = Self::SWARM_SEGMENTS;
        self.seg_radius = Self::SWARM_RADIUS;
        self.spacing = Self::SWARM_SPACING;
        self.reserve = self.trail_offset();
    }

    pub fn trailing(mut self) -> Crawler {
        self.swarm_in_place();
        self.reserve = 0;
        self.trails = true;
        self
    }

    pub fn sprinter(mut self) -> Crawler {
        self.segments = Self::SPRINT_SEGMENTS;
        self.speed = Self::SPRINT_SPEED;
        self
    }

    pub fn body(&self) -> i64 {
        (self.segments - 1) * self.spacing
    }

    pub fn trail_offset(&self) -> i64 {
        self.body() + Self::SWARM_GAP
    }

    pub fn start_span(&self) -> i64 {
        Self::W - self.body() - Self::CORNER_CLEAR * self.speed / Self::SPEED - self.reserve
    }

    pub fn near_x(&self) -> i64 {
        self.seg_radius + SimConfig::BIRD_RADIUS + 8 * SimConfig::SUB
    }

    pub fn wall_window(&self) -> i64 {
        (Self::LEFT - SimConfig::BIRD_RADIUS + self.near_x()) / SimConfig::SPEED_X + 1
    }

    pub fn slot_clear(&self) -> i64 {
        SimConfig::SLOT_SIZE / 2 + self.seg_radius + SimConfig::BIRD_RADIUS + 2 * SimConfig::SUB
    }

    pub fn exit_clear(&self) -> i64 {
        SimConfig::EXIT_FIT + self.seg_radius + SimConfig::BIRD_RADIUS + SimConfig::SUB
    }

    /// C# returns the leader Crawler (or null); here a reference into the room.
    pub fn _leader<'a>(&self, sim: &'a GameSim) -> Option<&'a Crawler> {
        let mut out_: Option<&'a Crawler> = None;
        let hs = &sim.room.hazards;
        for i in 0..hs.len() {
            // C# `h == this`: our own slot (Taken while setup runs).
            if i == self.base.idx {
                break;
            }
            let h = &hs[i];
            if h.kind() == self.base.kind {
                if let Hz::Crawler(c) = h {
                    if c.lane == self.lane && !c.trails {
                        out_ = Some(c);
                    }
                }
            }
        }
        out_
    }

    pub fn _place(&mut self) {
        let tail = self.start + self.base.t * self.speed;
        for i in 0..self.segments {
            let s = G::posmod(tail + (self.segments - 1 - i) * self.spacing, Self::PERIMETER);
            self.xs[i as usize] = self.path_x(s);
            self.ys[i as usize] = self.path_y(s);
        }
    }

    pub fn path_x(&self, s: i64) -> i64 {
        if s < Self::W {
            return Self::LEFT + s;
        }
        if s < Self::W + Self::H {
            return Self::RIGHT;
        }
        if s < 2 * Self::W + Self::H {
            return Self::RIGHT - (s - Self::W - Self::H);
        }
        Self::LEFT
    }

    pub fn path_y(&self, s: i64) -> i64 {
        if s < Self::W {
            return Self::TOP;
        }
        if s < Self::W + Self::H {
            return Self::TOP + s - Self::W;
        }
        if s < 2 * Self::W + Self::H {
            return Self::BOTTOM;
        }
        Self::BOTTOM - (s - 2 * Self::W - Self::H)
    }

    pub fn _best_run(&self, mask: i64, covered: i64, bird_y: i64) -> i64 {
        let mut want = Self::FREE_RUN;
        while want > 0 {
            let mut best: i64 = 0;
            let mut best_rank: i64 = -1;
            for slot in 0..(SimConfig::SLOT_COUNT - want + 1) {
                let run = ((1i64 << want) - 1) << slot;
                if (covered & run) != 0 {
                    continue;
                }
                let centre = SimConfig::slot_center_y(slot) + (want - 1) * SimConfig::SLOT_SIZE / 2;
                let away = G::absi(centre - bird_y);
                let mut spikes: i64 = 0;
                for i in 0..want {
                    if RoomRules::has_slot(mask, slot + i) {
                        spikes += 1;
                    }
                }
                let mut rank = away + spikes * SimConfig::WORLD_H;
                if away > RoomRules::GAP_REACH {
                    rank += SimConfig::SLOT_COUNT * SimConfig::WORLD_H;
                }
                if best_rank < 0 || rank < best_rank {
                    best_rank = rank;
                    best = run;
                }
            }
            if best != 0 {
                return best;
            }
            want -= 1;
        }
        0
    }

    /// [lowest y, highest y] of the segments in the bird's way; [FAR, -FAR] when none is.
    pub fn _in_the_way(&self, sim: &GameSim, from: i64, side: i64, arrive: i64, after: i64) -> [i64; 2] {
        let r = SimConfig::BIRD_RADIUS;
        let wall = if side == 1 { sim.room.wall_right() - r } else { sim.room.wall_left() + r };
        let inward = if side == 1 { -SimConfig::SPEED_X } else { SimConfig::SPEED_X };
        let mut lo = Self::FAR;
        let mut hi = -Self::FAR;
        let near = self.near_x();
        for d in -self.wall_window()..(after + 1) {
            let bird_x = wall + inward * G::absi(d);
            let tail = from + (arrive + d) * self.speed;
            for i in 0..self.segments {
                let s = G::posmod(tail + i * self.spacing, Self::PERIMETER);
                if G::absi(self.path_x(s) - bird_x) < near {
                    let y = self.path_y(s);
                    lo = G::mini(lo, y);
                    hi = G::maxi(hi, y);
                }
            }
        }
        [lo, hi]
    }
}

impl Hazard for Crawler {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        let leader_start = if self.trails { self._leader(sim).map(|c| c.start) } else { None };
        if let Some(ls) = leader_start {
            self.start = ls - self.trail_offset();
        } else {
            self.start = self.reserve + rng.next_below(self.start_span()) + self.lane * (Self::W + Self::H);
        }
        Self::_resize(&mut self.xs, self.segments);
        Self::_resize(&mut self.ys, self.segments);
        self._place();
    }

    fn step(&mut self, _sim: &mut GameSim) {
        self._place();
    }

    fn kills(&self, sim: &GameSim) -> bool {
        for i in 0..self.segments {
            if sim.bird_touches_circle(self.xs[i as usize], self.ys[i as usize], self.seg_radius) {
                return true;
            }
        }
        false
    }

    fn blocks_exit(&self, sim: &GameSim, side: i64, y: i64) -> bool {
        let span = self._in_the_way(sim, self.start, side, self.base.t + sim.steps_to_exit(side), 0);
        y > span[0] - self.exit_clear() && y < span[1] + self.exit_clear()
    }

    fn adjust_wall(&mut self, sim: &mut GameSim, side: i64, mask: i64) -> i64 {
        let sim: &GameSim = sim;
        let s = &sim.state;
        if s.exit_open && s.exit_side == side {
            return mask;
        }
        let arrive = self.base.t + sim.steps_to_wall(side);
        let mut covered: i64 = 0;
        let mut first = true;
        let hs = &sim.room.hazards;
        for hi in 0..hs.len() {
            // C# would see `this` at our own slot (Taken while adjust_wall runs).
            let is_self = hi == self.base.idx;
            let h_kind = if is_self { self.base.kind } else { hs[hi].kind() };
            if h_kind != self.base.kind {
                continue;
            }
            if first && !is_self {
                return mask;
            }
            first = false;
            let c: &Crawler = if is_self {
                self
            } else {
                match &hs[hi] {
                    Hz::Crawler(c) => c,
                    _ => panic!("kind crawler is not a Crawler"),
                }
            };
            let from = c.start;
            let span = c._in_the_way(sim, from, side, arrive, c.wall_window());
            let clear = c.slot_clear();
            for slot in 0..SimConfig::SLOT_COUNT {
                let cy = SimConfig::slot_center_y(slot);
                if cy > span[0] - clear && cy < span[1] + clear {
                    covered |= 1i64 << slot;
                }
            }
        }
        if covered == 0 {
            return mask;
        }
        mask & !self._best_run(mask, covered, s.anchor_y)
    }

    fn checksum(&self, h: i64) -> i64 {
        let mut out_ = mix_all(h, &[self.lane, self.start]);
        for i in 0..self.segments {
            out_ = mix_all(out_, &[self.xs[i as usize], self.ys[i as usize]]);
        }
        if self.segments != Self::SEGMENTS || self.speed != Self::SPEED || self.reserve != 0 || self.trails {
            out_ = mix_all(
                out_,
                &[self.segments, self.seg_radius, self.spacing, self.speed, self.reserve, G::b(self.trails)],
            );
        }
        out_
    }
}
