//! Port of sim/hazards/spike_ball.gd (Sim/Hazards/SpikeBall.cs).
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct SpikeBall {
    pub base: Base,
    pub x: i64,
    pub y: i64,
    pub spots: Vec<i64>,
}

impl SpikeBall {
    pub const SUB: i64 = SimConfig::SUB;
    pub const RADIUS: i64 = 15 * Self::SUB;

    /// C# default: p_spots = null (an empty list).
    pub fn new(p_spots: Vec<i64>) -> SpikeBall {
        SpikeBall { base: Base::new("spike_ball"), x: 0, y: 0, spots: p_spots }
    }

    pub fn _in_the_way(&self, sim: &GameSim, bx: i64, by: i64) -> bool {
        let margin = 10 * Self::SUB;
        if FairLanes::start_path_hits_rect(
            sim,
            bx - Self::RADIUS,
            by - Self::RADIUS,
            bx + Self::RADIUS,
            by + Self::RADIUS,
            margin,
        ) {
            return true;
        }
        if FairLanes::blocks_start_lane(sim, bx - Self::RADIUS, by - Self::RADIUS, bx + Self::RADIUS, by + Self::RADIUS)
        {
            return true;
        }
        if !sim.state.started {
            return false;
        }
        let path = FairLanes::arrival_path(sim);
        for k in 0..FairLanes::ARRIVAL_PATH_TICKS {
            if FairLanes::arrival_path_hits(&path, k, bx, by, Self::RADIUS) {
                return true;
            }
        }
        false
    }
}

impl Hazard for SpikeBall {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
        let n = self.spots.len() as i64 / 2;
        let first = rng.next_below(n);
        let mut pick = first;
        for k in 0..n {
            let i = (first + k) % n;
            if !self._in_the_way(sim, self.spots[(2 * i) as usize], self.spots[(2 * i + 1) as usize]) {
                pick = i;
                break;
            }
        }
        self.x = self.spots[(2 * pick) as usize];
        self.y = self.spots[(2 * pick + 1) as usize];
        let hs = &mut sim.room.hazards;
        for j in 0..hs.len() {
            // Our own slot holds Hz::Taken: as_coin_pickup_mut gives None there.
            if let Some(c) = hs[j].as_coin_pickup_mut() {
                if c.x == self.x && c.y == self.y {
                    c.base.alive = false;
                }
            }
        }
    }

    fn kills(&self, sim: &GameSim) -> bool {
        sim.bird_touches_circle(self.x, self.y, Self::RADIUS)
    }

    fn checksum(&self, h: i64) -> i64 {
        mix_all(h, &[self.x, self.y])
    }
}
