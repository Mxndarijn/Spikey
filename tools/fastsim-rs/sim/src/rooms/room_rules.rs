//! Port of sim/rooms/room_rules.gd (Sim/Rooms/RoomRules.cs).
use crate::g::G;
use crate::rooms::room_def::RoomDef;
use crate::sim_config::SimConfig;
use crate::sim_rng::SimRng;

pub struct RoomRules;

impl RoomRules {
    pub const GAP_REACH: i64 = 200 * SimConfig::SUB;

    pub fn spike_count(score: i64, def: &RoomDef, bonus: i64) -> i64 {
        if !def.spikes {
            return 0;
        }
        let n = SimConfig::BASE_SPIKES + score / SimConfig::POINTS_PER_EXTRA_SPIKE + def.extra_spikes;
        let room_for_spikes = SimConfig::SLOT_COUNT - def.gap;
        G::maxi(G::mini(G::mini(n, def.max_spikes) + bonus, room_for_spikes), 1)
    }

    pub fn gap_reach(def: &RoomDef) -> i64 {
        if def.reach > 0 {
            return def.reach;
        }
        if !def.hazards.is_empty() || !def.combos.is_empty() || def.squeeze {
            return Self::GAP_REACH;
        }
        // Rooms that keep their hazards only in variants count too.
        for variant in &def.variants {
            if !variant.hazards.is_empty() || variant.kind == crate::rooms::room_def::Kind::GENERATED {
                return Self::GAP_REACH;
            }
        }
        0
    }

    /// GDScript defaults: bird_y = -1, bonus = 0, p_reach = -1.
    pub fn generate_wall(rng: &mut SimRng, score: i64, def: &RoomDef, bird_y: i64, bonus: i64, p_reach: i64) -> i64 {
        let n = Self::spike_count(score, def, bonus);
        if n == 0 {
            return 0;
        }
        let gap = def.gap;
        let mut lo = 0;
        let mut hi = SimConfig::SLOT_COUNT - gap;
        let reach = if p_reach < 0 { Self::gap_reach(def) } else { p_reach };
        if bird_y >= 0 && reach > 0 {
            let mut first = hi;
            let mut last = lo;
            for start in lo..hi + 1 {
                let center = SimConfig::slot_center_y(start) + (gap - 1) * SimConfig::SLOT_SIZE / 2;
                if G::absi(center - bird_y) <= reach {
                    first = G::mini(first, start);
                    last = G::maxi(last, start);
                }
            }
            if first <= last {
                lo = first;
                hi = last;
            }
        }
        let gap_start = lo + rng.next_below(hi - lo + 1);
        let mut candidates = [0i64; SimConfig::SLOT_COUNT as usize];
        let mut count: i64 = 0;
        for slot in 0..SimConfig::SLOT_COUNT {
            if slot < gap_start || slot >= gap_start + gap {
                candidates[count as usize] = slot;
                count += 1;
            }
        }
        let mut mask = 0;
        for i in 0..n {
            let j = i + rng.next_below(count - i);
            let picked = candidates[j as usize];
            candidates[j as usize] = candidates[i as usize];
            candidates[i as usize] = picked;
            mask |= 1i64 << picked;
        }
        mask
    }

    #[inline(always)]
    pub fn has_slot(mask: i64, slot: i64) -> bool {
        ((mask >> slot) & 1) == 1
    }

    pub fn longest_gap(mask: i64) -> i64 {
        let mut best = 0;
        let mut run = 0;
        for slot in 0..SimConfig::SLOT_COUNT {
            if Self::has_slot(mask, slot) {
                run = 0;
            } else {
                run += 1;
                best = G::maxi(best, run);
            }
        }
        best
    }

    pub fn longest_gap_mask(mask: i64) -> i64 {
        let mut best = 0;
        let mut best_end = 0;
        let mut run = 0;
        for slot in 0..SimConfig::SLOT_COUNT {
            if Self::has_slot(mask, slot) {
                run = 0;
            } else {
                run += 1;
                if run > best {
                    best = run;
                    best_end = slot;
                }
            }
        }
        let mut out_ = 0;
        for slot in best_end - best + 1..best_end + 1 {
            out_ |= 1i64 << slot;
        }
        out_
    }

    /// `mask` if it has a run of `need` free slots all in `ok` (a slot mask);
    /// else `mask` with the run of `need` slots of `ok` nearest the middle of its
    /// free run cleared (unchanged if `ok` has no such run). No RNG draws.
    pub fn keep_run(mask: i64, need: i64, ok: i64) -> i64 {
        let all = (1i64 << SimConfig::SLOT_COUNT) - 1;
        if need <= 0 || Self::longest_gap(mask | (all & !ok)) >= need {
            return mask;
        }
        let free = Self::longest_gap_mask(mask);
        let mut mid = 0;
        let mut n = 0;
        for slot in 0..SimConfig::SLOT_COUNT {
            if ((free >> slot) & 1) == 1 {
                mid += SimConfig::slot_center_y(slot);
                n += 1;
            }
        }
        if n > 0 {
            mid /= n;
        }
        let mut best = -1;
        let mut best_d = 0;
        let span = (1i64 << need) - 1;
        for start in 0..SimConfig::SLOT_COUNT - need + 1 {
            if ((ok >> start) & span) != span {
                continue;
            }
            let y = SimConfig::slot_center_y(start) + (need - 1) * SimConfig::SLOT_SIZE / 2;
            let d = G::absi(y - mid);
            if best < 0 || d < best_d {
                best = start;
                best_d = d;
            }
        }
        if best < 0 {
            return mask;
        }
        mask & !(span << best)
    }
}
