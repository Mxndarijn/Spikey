//! Port of sim/hazards/crowd_fill.gd: Crowded (Filling up), the walls keep their spikes and
//! newcomers take seats on the wall the bird just left.
use crate::prelude::*;

#[derive(Clone, Debug)]
pub struct CrowdFill {
    pub base: Base,
    pub seats_left: i64,
    pub seats_right: i64,
    pub coming_left: i64,
    pub coming_right: i64,
    pub started_left: bool,
    pub started_right: bool,
    pub since_pick: i64,
    pub start_seats: i64,
    pub newcomers: i64,
    pub left_only: bool,
    pub last_run: i64,
    pub keep_run: i64,
    pub _seed: i64,
    pub _rng: SimRng,
}

impl CrowdFill {
    pub const START: i64 = 2;
    pub const SALT: i64 = 0x51C7D2;

    pub fn new() -> CrowdFill {
        CrowdFill {
            base: Base::new("crowd_fill"),
            seats_left: 0,
            seats_right: 0,
            coming_left: 0,
            coming_right: 0,
            started_left: false,
            started_right: false,
            since_pick: 0,
            start_seats: Self::START,
            newcomers: 1,
            left_only: false,
            last_run: 0,
            keep_run: 4,
            _seed: 0,
            _rng: SimRng::new(0),
        }
    }

    pub fn seats(&self, side: i64) -> i64 {
        if side == 0 {
            self.seats_left
        } else {
            self.seats_right
        }
    }

    pub fn coming(&self, side: i64) -> i64 {
        if side == 0 {
            self.coming_left
        } else {
            self.coming_right
        }
    }

    fn _pick(&mut self, taken: i64, keep_free: i64, n: i64) -> i64 {
        let mut out_ = taken;
        for _i in 0..n {
            let mut free: Vec<i64> = Vec::new();
            for slot in 0..SimConfig::SLOT_COUNT {
                if RoomRules::has_slot(out_, slot) || RoomRules::has_slot(keep_free, slot) {
                    continue;
                }
                if RoomRules::longest_gap(out_ | (1i64 << slot)) < self.keep_run {
                    continue;
                }
                free.push(slot);
            }
            if free.is_empty() {
                break;
            }
            out_ |= 1i64 << free[self._rng.next_below(free.len() as i64) as usize];
        }
        out_
    }
}

impl Hazard for CrowdFill {
    impl_base!();

    fn setup(&mut self, sim: &mut GameSim, _rng_room: &mut SimRng) {
        match sim.room.variant_id() {
            "lopsided" => self.left_only = true,
            "storm" => {
                self.start_seats = 1;
                self.newcomers = 2;
            }
            _ => {}
        }
        self.keep_run = sim.room.def().gap;
        self._seed = SimHash::mix(sim.room.rng_seed, Self::SALT);
    }

    fn step(&mut self, _sim: &mut GameSim) {
        self.since_pick += 1;
    }

    fn adjust_wall(&mut self, sim: &mut GameSim, side: i64, mask: i64) -> i64 {
        self._rng.reseed(SimHash::mix(self._seed, sim.room.walls));
        let span = (1i64 << self.keep_run) - 1;
        let mut run = RoomRules::longest_gap_mask(mask);
        if sim.wall_run[0] >= 0 {
            run = span << sim.wall_run[0];
        }
        let mut have = self.seats(side) | self.coming(side);
        let started = if side == 0 { self.started_left } else { self.started_right };
        if !started {
            let n = self.start_seats;
            have = self._pick(have, run, n);
        }
        let mut kept = -1;
        if sim.wall_run[0] >= 0 {
            for start in sim.wall_run[1]..sim.wall_run[2] + 1 {
                if have & (span << start) == 0 {
                    kept = start;
                    break;
                }
            }
        }
        if kept >= 0 {
            run = span << kept;
        }
        have &= !run;
        self.last_run = run;
        if side == 0 {
            self.seats_left = have;
            self.coming_left = 0;
            self.started_left = true;
        } else {
            self.seats_right = have;
            self.coming_right = 0;
            self.started_right = true;
        }
        let other = 1 - side;
        if !self.left_only || other == 0 {
            let taken = self.seats(other) | self.coming(other);
            let n = self.newcomers;
            let add = self._pick(taken, 0, n) & !self.seats(other);
            if other == 0 {
                self.coming_left = add & !self.seats_left;
            } else {
                self.coming_right = add & !self.seats_right;
            }
        }
        self.since_pick = 0;
        have
    }

    fn checksum(&self, h: i64) -> i64 {
        mix_all(
            h,
            &[
                self.seats_left,
                self.seats_right,
                self.coming_left,
                self.coming_right,
                G::b(self.started_left),
                G::b(self.started_right),
                self.since_pick,
                self.start_seats,
                self.newcomers,
                G::b(self.left_only),
                self.keep_run,
                self.last_run,
                self._seed,
            ],
        )
    }
}
