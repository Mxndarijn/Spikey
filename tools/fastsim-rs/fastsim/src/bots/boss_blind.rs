//! Port of Bots/BossBlind.cs: what a player can and cannot know about a boss
//! (research/planner-review/07-bosses.md). Every attack is drawn from
//! `Boss.seed` (hidden). The attack being told is on screen; every later one
//! is not. Tool only.
use sim::hazards::boss_crusher::Crate;
use sim::hazards::boss_watcher::Beam as WBeam;
use sim::hazards::boss_watcher::Dart as WDart;
use sim::prelude::*;

pub struct BossBlind;

impl BossBlind {
    /// Replaces the boss's seed in a planner's copy. The attack on screen stays
    /// as it is, unless `unseen` (its tell appeared less than a reaction ago):
    /// then it is a guess too. `hz` must be a boss.
    pub fn scramble(hz: &mut Hz, own: &mut SimRng, unseen: bool) {
        let old = hz.as_boss().expect("a boss").seed;
        hz.as_boss_mut().unwrap().seed = own.next_u32();
        match hz {
            Hz::BossWatcher(w) => {
                // `lit` is kept for the cycle it was drawn in (on screen while it warns and fires).
                if unseen && w.beam == WBeam::WARN && w._lit_k >= 0 {
                    w.lit = w.lit_rows(w.boss.phase, w._lit_k);
                }
            }
            Hz::BossCrusher(cr) => {
                let c = cr.boss.clock();
                if c >= 0 && cr.boss.phase == 1 && !unseen {
                    // The slam height is drawn again every step from the seed: keep the one on screen.
                    let k = c / BossCrusher::CYCLE;
                    let want = Self::slam_with(cr, old, k);
                    let mut i = 0;
                    while i < 64 && cr.slam_of(k) != want {
                        cr.boss.seed = own.next_u32();
                        i += 1;
                    }
                    if cr.slam_of(k) != want {
                        cr.boss.seed = old;
                    }
                }
                if unseen && cr.telling && cr.boss.phase > 1 && cr.lane_from >= 0 {
                    cr.lane_to = cr._next_lane(cr._k);
                }
                if unseen {
                    for i in 0..2 {
                        if cr.crate_[i] == Crate::MARK {
                            cr.crate_x[i] =
                                BossCrusher::COLUMN_X0 + own.next_below(BossCrusher::COLUMNS) * BossCrusher::COLUMN_STEP;
                        }
                    }
                }
            }
            Hz::BossSaw(s) => {
                if unseen && s.telling && s._k >= 0 {
                    s.to_y = if s.boss.phase == 2 {
                        BossSaw::RING_YS[(s.boss.draw(s._k, 2) % 2) as usize]
                    } else {
                        s.hop_to(s.from_y, s._k)
                    };
                }
            }
            _ => {}
        }
    }

    fn slam_with(cr: &mut BossCrusher, seed: i64, k: i64) -> i64 {
        let keep = cr.boss.seed;
        cr.boss.seed = seed;
        let v = cr.slam_of(k);
        cr.boss.seed = keep;
        v
    }

    /// Changes whenever a new tell starts (what a player has to take in).
    pub fn tell_key(hz: &Hz) -> i64 {
        let b = hz.as_boss().expect("a boss");
        let mut h = SimHash::mix(SimHash::SEED, b.phase);
        match hz {
            Hz::BossWatcher(w) => {
                h = SimHash::mix(h, if w.boss.phase != 2 { w._lit_k } else { -1 });
                h = SimHash::mix(h, if w.dart == WDart::NONE { -1 } else { w.dart_lane * 4 + w.dart_side });
            }
            Hz::BossCrusher(cr) => {
                let c = cr.boss.clock();
                h = SimHash::mix(h, if c >= 0 && cr.boss.phase == 1 { c / BossCrusher::CYCLE } else { cr._k });
                for i in 0..2 {
                    h = SimHash::mix(h, if cr.crate_[i] == Crate::NONE { -1 } else { cr.crate_x[i] });
                }
            }
            Hz::BossSaw(s) => {
                h = SimHash::mix(h, s._k);
            }
            _ => {}
        }
        SimHash::mix(h, if b.down_at >= 0 { 1 } else { 0 })
    }
}
