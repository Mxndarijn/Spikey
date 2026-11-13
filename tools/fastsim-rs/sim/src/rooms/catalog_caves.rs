//! Port of sim/rooms/catalog_caves.gd. Order is part of the rules.
use crate::hazards::cave_drip::CaveDrip;
use crate::hazards::cave_rock::CaveRock;
use crate::hazards::peg::Peg;
use crate::prelude::*;

pub struct CatalogCaves;

impl CatalogCaves {
    pub const SUB: i64 = SimConfig::SUB;
    pub const W: i64 = SimConfig::WORLD_W;
    pub const FORK: i64 = 0;
    pub const DRIPS: i64 = 1;
    pub const BATS: i64 = 2;
    pub const GALLERY_X: i64 = 272 * Self::SUB;
    pub const CAVE_SPREAD: i64 = SimConfig::EXIT_HALF;
    pub const BEND: [i64; 3] = [40, 65, 90];
    pub const BEND_HALF: [i64; 3] = [120, 115, 110];
    pub const BEND_CUT_TOP: i64 = 8 * Self::SUB;
    pub const BEND_CUT_BOTTOM: i64 = 30 * Self::SUB;
    pub const ISLE_TIP_X: i64 = 276 * Self::SUB;
    pub const ISLE_FLAT: i64 = 20 * Self::SUB;
    pub const FAR_FLAT: i64 = ExitZone::DEPTH + 4 * Self::SUB;
    pub const BRANCH_HALF: i64 = 90 * Self::SUB;
    pub const ISLE_HALF: i64 = 20 * Self::SUB;
    pub const ISLE_GAP: i64 = 6 * Self::SUB;
    pub const FANG_ROOM_MIN: i64 = 22 * Self::SUB;
    pub const FANG_ROOM_SPAN: i64 = 14 * Self::SUB;
    pub const LIP_STEP: i64 = 12 * Self::SUB;
    pub const FANG_STEP: i64 = 24 * Self::SUB;
    pub const FANG_STEP_SPAN: i64 = 10 * Self::SUB;
    pub const FANG_HALF: i64 = 6 * Self::SUB;
    pub const FANG_HALF_SPAN: i64 = 5 * Self::SUB;
    pub const LONG_HALF: i64 = 12 * Self::SUB;
    pub const LONG_TOP: [i64; 4] = [55, 115, 175, 235];
    pub const LONG_BOTTOM: [i64; 3] = [85, 145, 205];
    pub const DRIP_CADENCE: [i64; 3] = [48, 40, 32];
    pub const DRIP_FIRST: i64 = 200;
    pub const BAT_XS: [&'static [i64]; 3] = [&[70, 150, 230], &[70, 150, 230], &[60, 120, 180, 240]];
    pub const BAT_SWAY: i64 = 6 * Self::SUB;
    pub const BAT_PERIOD: [i64; 3] = [400, 360, 320];
    pub const BAT_ROOM: i64 = 48 * Self::SUB;
    pub const BAT_MARGIN: i64 = 4 * Self::SUB;
    pub const BAT_FOLLOW: i64 = 120;
    pub const BAT_JITTER: i64 = 16 * Self::SUB;
    pub const PEG_COUNT: [i64; 3] = [6, 8, 10];
    pub const PEG_APART: i64 = 128 * Self::SUB;
    pub const PEG_STRIP: i64 = 70 * Self::SUB;
    pub const PEG_WALL: i64 = 24 * Self::SUB;
    pub const PEG_EDGE: i64 = 10 * Self::SUB;
    pub const PEG_BOB: i64 = 20 * Self::SUB;
    pub const PEG_DRAWS: i64 = 80;
    pub const L_TOP0: usize = 0;
    pub const L_BOTTOM0: usize = 1;
    pub const L_TOP1: usize = 2;
    pub const L_BOTTOM1: usize = 3;
    pub const L_FORK: usize = 4;
    pub const L_TIP: usize = 5;
    pub const L_ISLE_TOP1: usize = 6;
    pub const L_ISLE_BOTTOM1: usize = 7;

    pub fn defs() -> Vec<RoomDef> {
        let mut out_ = Vec::new();
        let mut cave = RoomDef::new("cave", "mid", 40);
        cave.max_spikes = 4;
        cave.variants = vec![
            RoomVariant::new("fork")
                .generated(recipe(|sim, p| Self::_gen_cave(sim, p, Self::FORK)), false, 0)
                .checked_within(Self::CAVE_SPREAD),
            RoomVariant::new("drips")
                .generated(recipe(|sim, p| Self::_gen_cave(sim, p, Self::DRIPS)), false, 0)
                .checked_within(Self::CAVE_SPREAD),
            RoomVariant::new("bats")
                .generated(recipe(|sim, p| Self::_gen_cave(sim, p, Self::BATS)), false, 0)
                .checked_within(Self::CAVE_SPREAD),
        ];
        out_.push(cave);

        let mut pegs = RoomDef::new("pegs", "mid", 30);
        pegs.max_spikes = 5;
        pegs.variants = vec![
            RoomVariant::new("classic").generated(recipe(|sim, p| Self::_gen_pegs(sim, p, false)), false, 0),
            RoomVariant::new("drift").generated(recipe(|sim, p| Self::_gen_pegs(sim, p, true)), false, 0),
        ];
        out_.push(pegs);
        out_
    }

    fn _x(sim: &GameSim, p: &VariantParams, x: i64) -> i64 {
        if Self::_flip(sim, p) {
            Self::W - x
        } else {
            x
        }
    }

    fn _flip(sim: &GameSim, p: &VariantParams) -> bool {
        p.arriving && sim.state.vx < 0
    }

    pub fn _smooth(num: i64, den: i64) -> i64 {
        let t = G::clampi(num, 0, den);
        t * t / den * (3 * den - 2 * t) / den
    }

    fn _level(p: &VariantParams) -> usize {
        G::mini(p.level, 2) as usize
    }

    fn _cave_band(p: &VariantParams) -> [i64; 2] {
        let r = SimConfig::BIRD_RADIUS + VariantParams::MARGIN;
        let spread = Self::CAVE_SPREAD;
        let high = GameSim::_arrival_y(p.entry_y - spread);
        let low = GameSim::_arrival_y(p.entry_y + spread);
        let mut top = high - FairLanes::FIRST_HOP - r;
        let mut bottom = low + r;
        top = G::mini(top, GameSim::_arrival_y(p.entry_y - SimConfig::EXIT_FIT) - r);
        bottom = G::maxi(bottom, GameSim::_arrival_y(p.entry_y + SimConfig::EXIT_FIT) + r);
        [top, bottom]
    }

    fn _limits(sim: &mut GameSim, p: &VariantParams, variant: i64) -> [i64; 8] {
        let mut lim = [0i64; 8];
        let band = Self::_cave_band(p);
        let room = if variant == Self::BATS { Self::BAT_ROOM } else { 0 };
        lim[Self::L_TOP0] = band[0] - room;
        lim[Self::L_BOTTOM0] = band[1] + room;
        let c0 = (band[0] + band[1]) / 2;
        let lv = Self::_level(p);
        if variant == Self::FORK {
            let up = sim._rng.next_below(2) == 0;
            let tip = if up {
                lim[Self::L_TOP0] - Self::ISLE_GAP - Self::ISLE_HALF
            } else {
                lim[Self::L_BOTTOM0] + Self::ISLE_GAP + Self::ISLE_HALF
            };
            lim[Self::L_FORK] = 1;
            lim[Self::L_TIP] = tip;
            lim[Self::L_ISLE_TOP1] = tip - Self::ISLE_HALF;
            lim[Self::L_ISLE_BOTTOM1] = tip + Self::ISLE_HALF;
            let main_top = G::mini(lim[Self::L_TOP0], tip - Self::ISLE_HALF - 2 * Self::BRANCH_HALF);
            let main_bottom = G::maxi(lim[Self::L_BOTTOM0], tip + Self::ISLE_HALF + 2 * Self::BRANCH_HALF);
            lim[Self::L_TOP1] = if up { tip - Self::ISLE_HALF - 2 * Self::BRANCH_HALF } else { main_top };
            lim[Self::L_BOTTOM1] = if up { main_bottom } else { tip + Self::ISLE_HALF + 2 * Self::BRANCH_HALF };
            return lim;
        }
        let half = Self::BEND_HALF[lv] * Self::SUB;
        let bend = Self::BEND[lv] * Self::SUB;
        let lo = SimConfig::KILL_TOP + half + 24 * Self::SUB;
        let hi = SimConfig::KILL_BOTTOM - half - 24 * Self::SUB;
        let mut c1 = G::clampi(c0 - bend + sim._rng.next_below(2 * bend + 1), lo, hi);
        c1 = G::clampi(c1, band[1] - half - Self::BEND_CUT_BOTTOM, band[0] + half + Self::BEND_CUT_TOP);
        lim[Self::L_TOP1] = c1 - half;
        lim[Self::L_BOTTOM1] = c1 + half;
        lim
    }

    fn _limit(lim: &[i64; 8], which: usize, x: i64) -> i64 {
        if which < 2 {
            let span = Self::W - Self::FAR_FLAT - Self::GALLERY_X;
            let s = Self::_smooth(x - Self::GALLERY_X, span);
            let a = lim[Self::L_TOP0 + which];
            return a + (lim[Self::L_TOP1 + which] - a) * s / span;
        }
        let isle_span = Self::W - Self::ISLE_FLAT - Self::ISLE_TIP_X;
        let t = Self::_smooth(x - Self::ISLE_TIP_X, isle_span);
        let tip = lim[Self::L_TIP];
        tip + (lim[Self::L_ISLE_TOP1 + which - 2] - tip) * t / isle_span
    }

    fn _face(sim: &mut GameSim, lim: &[i64; 8], which: usize, from_x: i64, longs: &[i64]) -> Vec<i64> {
        let rock_up = which == 0 || which == 3;
        let sign: i64 = if rock_up { -1 } else { 1 };
        let isle = which >= 2;
        let mut lip_x: Vec<i64> = Vec::new();
        let mut lip_y: Vec<i64> = Vec::new();
        let mut x = from_x;
        loop {
            let off = if isle { 0 } else { Self::FANG_ROOM_MIN + sim._rng.next_below(Self::FANG_ROOM_SPAN + 1) };
            lip_x.push(x);
            lip_y.push(Self::_limit(lim, which, x) + sign * off);
            if x >= Self::W {
                break;
            }
            x = G::mini(x + Self::LIP_STEP, Self::W);
        }
        let mut fangs: Vec<[i64; 3]> = Vec::new();
        for &lx in longs {
            let cx = lx * Self::SUB;
            if cx - Self::LONG_HALF > from_x {
                fangs.push([cx, Self::LONG_HALF, 1000]);
            }
        }
        x = from_x + Self::FANG_STEP / 2 + sim._rng.next_below(Self::FANG_STEP_SPAN + 1);
        while !isle && x < Self::W - Self::FANG_STEP / 2 {
            let half = Self::FANG_HALF + sim._rng.next_below(Self::FANG_HALF_SPAN + 1);
            let reach = 350 + sim._rng.next_below(551);
            let mut free = true;
            for f in &fangs {
                if G::absi(f[0] - x) < f[1] + half + 2 * Self::SUB {
                    free = false;
                }
            }
            if free {
                fangs.push([x, half, reach]);
            }
            x += Self::FANG_STEP + sim._rng.next_below(Self::FANG_STEP_SPAN + 1);
        }
        fangs.sort_by(|a, b| a[0].cmp(&b[0]));
        let mut out_x: Vec<i64> = Vec::new();
        let mut out_y: Vec<i64> = Vec::new();
        let mut fi = 0;
        for i in 0..lip_x.len() {
            let lx = lip_x[i];
            while fi < fangs.len() && fangs[fi][0] + fangs[fi][1] < lx {
                Self::_add_fang(&mut out_x, &mut out_y, &lip_x, &lip_y, lim, which, &fangs[fi]);
                fi += 1;
            }
            let mut inside = false;
            for f in &fangs {
                if G::absi(f[0] - lx) <= f[1] {
                    inside = true;
                }
            }
            if !inside {
                out_x.push(lx);
                out_y.push(lip_y[i]);
            }
        }
        while fi < fangs.len() {
            Self::_add_fang(&mut out_x, &mut out_y, &lip_x, &lip_y, lim, which, &fangs[fi]);
            fi += 1;
        }
        let mut out_ = Vec::new();
        for i in 0..out_x.len() {
            out_.push(out_x[i]);
            out_.push(out_y[i]);
        }
        out_
    }

    #[allow(clippy::too_many_arguments)]
    fn _add_fang(
        xs: &mut Vec<i64>,
        ys: &mut Vec<i64>,
        lip_x: &[i64],
        lip_y: &[i64],
        lim: &[i64; 8],
        which: usize,
        f: &[i64; 3],
    ) {
        let x0 = f[0] - f[1];
        let x1 = f[0] + f[1];
        let y0 = CaveRock::edge_at(lip_x, lip_y, x0);
        let y1 = CaveRock::edge_at(lip_x, lip_y, x1);
        let base = (y0 + y1) / 2;
        let to = Self::_limit(lim, which, f[0]);
        xs.push(x0);
        ys.push(y0);
        xs.push(f[0]);
        ys.push(base + (to - base) * f[2] / 1000);
        xs.push(x1);
        ys.push(y1);
    }

    fn _store(sim: &GameSim, p: &VariantParams, pairs: &[i64]) -> (Vec<i64>, Vec<i64>) {
        let mut xs = Vec::new();
        let mut ys = Vec::new();
        let n = pairs.len() / 2;
        for i in 0..n {
            let j = if Self::_flip(sim, p) { n - 1 - i } else { i };
            xs.push(Self::_x(sim, p, pairs[2 * j]));
            ys.push(pairs[2 * j + 1]);
        }
        (xs, ys)
    }

    fn _gen_cave(sim: &mut GameSim, p: &VariantParams, variant: i64) {
        let lim = Self::_limits(sim, p, variant);
        let mut rock = CaveRock::new();
        let top_f = Self::_face(sim, &lim, 0, 0, &Self::LONG_TOP);
        let top = Self::_store(sim, p, &top_f);
        let bot_f = Self::_face(sim, &lim, 1, 0, &Self::LONG_BOTTOM);
        let bottom = Self::_store(sim, p, &bot_f);
        rock.top_x = top.0;
        rock.top_y = top.1;
        rock.bot_x = bottom.0;
        rock.bot_y = bottom.1;
        rock.reach_top = lim[Self::L_TOP0];
        rock.reach_bottom = lim[Self::L_BOTTOM0];
        if variant == Self::FORK {
            let upper = Self::_face(sim, &lim, 2, Self::ISLE_TIP_X, &[]);
            let lower = Self::_face(sim, &lim, 3, Self::ISLE_TIP_X, &[]);
            Self::_store_isle(sim, p, &mut rock, &upper, &lower);
        }
        let shape = rock.clone();
        p.add(sim, rock.into());
        if variant == Self::DRIPS {
            Self::_add_drips(sim, p, &shape);
        } else if variant == Self::BATS {
            Self::_add_bats(sim, p, &lim);
        }
    }

    fn _add_bats(sim: &mut GameSim, p: &VariantParams, lim: &[i64; 8]) {
        let lv = Self::_level(p);
        let band = Self::_cave_band(p);
        let mid = (lim[Self::L_TOP0] + lim[Self::L_BOTTOM0]) / 2;
        let swing = (lim[Self::L_BOTTOM0] - lim[Self::L_TOP0]) / 2 - Mover::RADIUS - Self::BAT_MARGIN;
        for &bx in Self::BAT_XS[lv] {
            let mut bat = Mover::new("figure8", 1);
            bat.loop_w = Self::BAT_SWAY;
            bat.loop_h = swing;
            bat.loop_period = Self::BAT_PERIOD[lv];
            let jitter = sim._rng.next_below(2 * Self::BAT_JITTER + 1);
            bat.center_x = Self::_x(sim, p, bx * Self::SUB - Self::BAT_JITTER + jitter);
            bat.center_y = mid;
            let i = p.add(sim, bat.into());
            if !p.arriving {
                continue;
            }
            let mut b = match std::mem::replace(&mut sim.room.hazards[i], Hz::Taken) {
                Hz::Mover(m) => m,
                _ => unreachable!(),
            };
            let start = b.phase;
            let mut best = start;
            let mut fewest: i64 = -1;
            for d in 0..b.period() {
                b.phase = (start + d) % b.period();
                let n = Self::_bat_meets(sim, &mut b, &band);
                if n >= 0 && (fewest < 0 || n < fewest) {
                    fewest = n;
                    best = b.phase;
                    if n == 0 {
                        break;
                    }
                }
            }
            b.phase = best;
            b._place();
            sim.room.hazards[i] = b.into();
        }
    }

    fn _bat_meets(sim: &GameSim, bat: &mut Mover, band: &[i64; 2]) -> i64 {
        let reach = SimConfig::BIRD_RADIUS + Mover::RADIUS + Self::BAT_MARGIN;
        let keep = bat.base.t;
        let mut meets = 0;
        for k in 1..VariantCheck::HOLD_STEPS + Self::BAT_FOLLOW + 1 {
            bat.base.t = k;
            bat._place();
            if G::absi(bat.xs[0] - FairLanes::arrival_x(sim, k)) >= reach {
                continue;
            }
            if bat.ys[0] + Mover::RADIUS + Self::BAT_MARGIN > band[0] && bat.ys[0] - Mover::RADIUS - Self::BAT_MARGIN < band[1] {
                if k <= VariantCheck::HOLD_STEPS {
                    meets = -1;
                    break;
                }
                meets += 1;
            }
        }
        bat.base.t = keep;
        meets
    }

    fn _store_isle(sim: &GameSim, p: &VariantParams, rock: &mut CaveRock, upper: &[i64], lower: &[i64]) {
        let mut lx = Vec::new();
        let mut ly = Vec::new();
        for i in 0..lower.len() / 2 {
            lx.push(lower[2 * i]);
            ly.push(lower[2 * i + 1]);
        }
        let mut pairs = Vec::new();
        let mut bottoms = Vec::new();
        for i in 0..upper.len() / 2 {
            let x = upper[2 * i];
            pairs.push(x);
            pairs.push(upper[2 * i + 1]);
            bottoms.push(G::maxi(CaveRock::edge_at(&lx, &ly, x), upper[2 * i + 1]));
        }
        let top = Self::_store(sim, p, &pairs);
        let mut bot_pairs = Vec::new();
        for i in 0..bottoms.len() {
            bot_pairs.push(upper[2 * i]);
            bot_pairs.push(bottoms[i]);
        }
        let bottom = Self::_store(sim, p, &bot_pairs);
        rock.isle_x = top.0;
        rock.isle_top = top.1;
        rock.isle_bot = bottom.1;
    }

    fn _add_drips(sim: &mut GameSim, p: &VariantParams, rock: &CaveRock) {
        let lv = Self::_level(p);
        let cadence = Self::DRIP_CADENCE[lv];
        let n = Self::LONG_TOP.len();
        let mut order: Vec<usize> = (0..n).collect();
        let mut i = n - 1;
        while i > 0 {
            let j = sim._rng.next_below(i as i64 + 1) as usize;
            order.swap(i, j);
            i -= 1;
        }
        let first = Self::DRIP_FIRST + sim._rng.next_below(cadence);
        let mut drips: Vec<CaveDrip> = Vec::new();
        let mut longest = 0;
        for k in 0..n {
            let x = Self::_x(sim, p, Self::LONG_TOP[order[k]] * Self::SUB);
            let tip = CaveRock::edge_at(&rock.top_x, &rock.top_y, x);
            let floor_y = CaveRock::edge_at(&rock.bot_x, &rock.bot_y, x);
            let d = CaveDrip::new(x, tip, floor_y, first + k as i64 * cadence, 1);
            longest = G::maxi(longest, d.fall_steps());
            drips.push(d);
        }
        let every = G::maxi(n as i64 * cadence, longest + CaveDrip::GLINT + 12);
        for mut d in drips {
            d.every = every;
            p.add(sim, d.into());
        }
    }

    fn _gen_pegs(sim: &mut GameSim, p: &VariantParams, drift: bool) {
        let bob = if drift { Self::PEG_BOB } else { 0 };
        let phase = if drift { sim._rng.next_below(Peg::BOB_PERIOD) } else { 0 };
        let r = Peg::RADIUS + bob;
        let top = p.hold_top(sim);
        let bottom = p.hold_bottom(sim);
        let want = Self::PEG_COUNT[Self::_level(p)];
        let mut made: Vec<[i64; 2]> = Vec::new();
        let lo_x = Self::PEG_WALL + Peg::RADIUS;
        let hi_x = Self::W - Self::PEG_STRIP - Peg::RADIUS;
        let lo_y = SimConfig::KILL_TOP + Self::PEG_EDGE + r;
        let hi_y = SimConfig::KILL_BOTTOM - Self::PEG_EDGE - r;
        for _k in 0..Self::PEG_DRAWS {
            if made.len() as i64 >= want {
                break;
            }
            let x = lo_x + sim._rng.next_below(hi_x - lo_x + 1);
            let y = lo_y + sim._rng.next_below(hi_y - lo_y + 1);
            if x < Self::GALLERY_X + Peg::RADIUS && y + r > top && y - r < bottom {
                continue;
            }
            let mut apart = true;
            for q in &made {
                let dx = q[0] - x;
                let dy = q[1] - y;
                if dx * dx + dy * dy < Self::PEG_APART * Self::PEG_APART {
                    apart = false;
                }
            }
            if apart {
                made.push([x, y]);
            }
        }
        for q in &made {
            let px = Self::_x(sim, p, q[0]);
            p.add(sim, Peg::new(px, q[1], bob, phase).into());
        }
    }
}
