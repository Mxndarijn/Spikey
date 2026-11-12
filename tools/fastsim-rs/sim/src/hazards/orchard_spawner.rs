//! Port of sim/hazards/orchard_spawner.gd (Sim/Hazards/OrchardSpawner.cs).
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct OrchardSpawner {
    pub base: Base,
    pub xs: Vec<i64>,
    pub ys: Vec<i64>,
    pub live: Vec<bool>,
    pub _rng: SimRng,
}

impl OrchardSpawner {
    pub const SUB: i64 = SimConfig::SUB;
    pub const SPAWN_EVERY: i64 = 36;
    pub const FALL: i64 = 2 * Self::SUB;
    pub const SLOTS: i64 = 12;
    pub const START_Y: i64 = 24 * Self::SUB;
    pub const COLUMNS: [i64; 5] = [80 * Self::SUB, 130 * Self::SUB, 180 * Self::SUB, 230 * Self::SUB, 280 * Self::SUB];

    pub fn new() -> OrchardSpawner {
        let mut o = OrchardSpawner {
            base: Base::new("orchard_spawner"),
            xs: Vec::new(),
            ys: Vec::new(),
            live: Vec::new(),
            _rng: SimRng::new(0),
        };
        for _i in 0..Self::SLOTS {
            o.xs.push(0);
            o.ys.push(0);
            o.live.push(false);
        }
        o
    }

    pub fn live_count(&self) -> i64 {
        let mut n = 0;
        for &v in &self.live {
            n += G::b(v);
        }
        n
    }
}

impl Hazard for OrchardSpawner {
    impl_base!();

    fn setup(&mut self, _sim: &mut GameSim, rng: &mut SimRng) {
        self._rng.reseed(rng.next_u32());
    }

    fn step(&mut self, _sim: &mut GameSim) {
        for i in 0..Self::SLOTS as usize {
            if self.live[i] {
                self.ys[i] += Self::FALL;
                if self.ys[i] > SimConfig::KILL_BOTTOM + SimConfig::COIN_RADIUS {
                    self.live[i] = false;
                }
            }
        }
        if self.base.t % Self::SPAWN_EVERY == 1 {
            for i in 0..Self::SLOTS as usize {
                if !self.live[i] {
                    self.live[i] = true;
                    self.xs[i] = Self::COLUMNS[self._rng.next_below(Self::COLUMNS.len() as i64) as usize];
                    self.ys[i] = Self::START_Y;
                    break;
                }
            }
        }
    }

    fn touch(&mut self, sim: &mut GameSim) {
        for i in 0..Self::SLOTS as usize {
            if self.live[i] && sim.bird_touches_circle(self.xs[i], self.ys[i], SimConfig::COIN_RADIUS) {
                self.live[i] = false;
                sim.collect_coin(self.xs[i], self.ys[i], 1);
            }
        }
    }

    fn checksum(&self, h: i64) -> i64 {
        let mut out_ = SimHash::mix(h, self._rng.state_checksum());
        for i in 0..Self::SLOTS as usize {
            out_ = mix_all(out_, &[self.xs[i], self.ys[i], G::b(self.live[i])]);
        }
        out_
    }
}
