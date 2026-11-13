//! Port of sim/rooms/catalog_machines.gd (Sim/Rooms/CatalogMachines.cs). Order is part of the rules.
use crate::prelude::*;

pub struct CatalogMachines;

impl CatalogMachines {
    pub const SUB: i64 = SimConfig::SUB;

    pub const PRESS_MIN: i64 = 3;
    pub const PRESS_MORE_AT: i64 = 100;
    pub const PRESS_ROW_GAP: i64 = 84 * Self::SUB;
    pub const PRESS_ROW_GAP_FEW: i64 = 110 * Self::SUB;
    pub const PRESS_TOP: i64 = 150 * Self::SUB;
    pub const PRESS_BOTTOM: i64 = 490 * Self::SUB;
    pub const PRESS_MAX_RIGHT: i64 = 2;
    pub const PRESS_REACH_MIN: i64 = 120 * Self::SUB;
    pub const PRESS_REACH_STEP: i64 = 20 * Self::SUB;
    pub const PRESS_REACH_STEPS: i64 = 4;
    pub const PRESS_GLOW: i64 = 44;
    pub const PRESS_GLOW_STEP: i64 = 6;
    pub const PRESS_DELAY: i64 = 30;
    pub const PRESS_BEAT_MIN: i64 = 24;
    pub const PRESS_BEAT_SPAN: i64 = 24;
    pub const WAVE_DOWN: i64 = 0;
    pub const WAVE_UP: i64 = 1;
    pub const HALVES: i64 = 2;
    pub const SCATTER: i64 = 3;
    pub const BEAM_STEP: i64 = 4 * Self::SUB;
    pub const BEAM_SHIFT: i64 = 60 * Self::SUB;
    pub const BEAM_APART: i64 = 80 * Self::SUB;
    pub const BEAM_TOP: i64 = 110 * Self::SUB;
    pub const BEAM_BOTTOM: i64 = 540 * Self::SUB;
    pub const BEAM_EXIT_CLEAR: i64 = SimConfig::EXIT_HALF + Beam::HALF_H;
    pub const BEAM_PHASE_STEP: i64 = 5;
    pub const BEAM_START_STEP: i64 = 20 * Self::SUB;
    pub const BEAM_LATE: i64 = 20;
    pub const BEAM_CALM_SPIKES: i64 = 5;
    pub const BEAM_LANE: i64 = SimConfig::EXIT_HALF - SimConfig::BIRD_RADIUS;
    pub const WIDE_COLS: i64 = 4;
    pub const WIDE_COL_W: i64 = 70 * Self::SUB;
    pub const WIDE_W: i64 = 64 * Self::SUB;
    pub const WIDE_H: i64 = 48 * Self::SUB;
    pub const WIDE_MAX: i64 = 3;
    pub const FANG_GAP: i64 = 100 * Self::SUB;
    pub const TRIO_X: [i64; 3] = [75, 180, 285];
    pub const ALT_GAP: i64 = 150 * Self::SUB;
    pub const ALT_LO: i64 = 260 * Self::SUB;
    pub const ALT_HI: i64 = 380 * Self::SUB;
    pub const SHORT_GAP: i64 = 300 * Self::SUB;
    pub const SHORT_Y: i64 = 320 * Self::SUB;
    pub const SHORT_HALF_W: i64 = 18 * Self::SUB;
    pub const ENTRY_X: i64 = 110 * Self::SUB;
    pub const FAR_X: i64 = 292 * Self::SUB;
    pub const FAR_GAP: i64 = 200 * Self::SUB;
    pub const GEN_SLACK: i64 = 4 * Self::SUB;
    pub const ENTRY_GAP: i64 = 2 * SimConfig::EXIT_FIT
        + FairLanes::FIRST_HOP
        + 2 * (SimConfig::BIRD_RADIUS + VariantParams::MARGIN)
        + 2 * Self::GEN_SLACK;

    pub fn defs() -> Vec<RoomDef> {
        const SUB: i64 = CatalogMachines::SUB;
        let mut out_ = Vec::new();

        let mut piston = RoomDef::new("piston", "mid", 30);
        piston.max_spikes = 6;
        piston.variants =
            vec![RoomVariant::new("generated").generated(recipe(|sim, p| Self::_gen_press(sim, p)), false, 0)];
        out_.push(piston);

        let mut crates = RoomDef::new("crates", "mid", 60);
        crates.max_spikes = 6;
        crates.variants = Self::crate_variants(false);
        out_.push(crates);

        let mut beams = RoomDef::new("beams", "mid", 50);
        beams.max_spikes = 7;
        beams.variants =
            vec![RoomVariant::new("generated").generated(recipe(|sim, p| Self::_gen_beams(sim, p)), false, 0)];
        out_.push(beams);

        let mut stalac = RoomDef::new("stalac", "mid", 30);
        stalac.max_spikes = 4;
        stalac.variants = vec![
            RoomVariant::new("classic").generated(recipe(|sim, p| Self::_gen_columns(sim, p, Self::BOTH)), false, 0),
            RoomVariant::new("floor").generated(recipe(|sim, p| Self::_gen_columns(sim, p, Self::FLOOR)), false, 0),
            RoomVariant::new("ceiling-only").generated(recipe(|sim, p| Self::_gen_columns(sim, p, Self::CEILING)), false, 0),
            RoomVariant::new("alternating").generated(recipe(|sim, p| Self::_gen_fixed(sim, p, false)), false, 0),
            RoomVariant::new("short-fangs").generated(recipe(|sim, p| Self::_gen_fixed(sim, p, true)), false, 0),
        ];
        out_.push(stalac);

        let mut hunter = RoomDef::new("hunter", "late", 80);
        hunter.weight = 8;
        hunter.variants = vec![
            // Dart() -> Dart(false, 0, -1) (C# defaults).
            RoomVariant::new("classic").with(vec![mk(|| Dart::new(false, 0, -1).into())]),
            RoomVariant::new("twin")
                .with(vec![mk(|| Self::_hunter(0, 1)), mk(|| Self::_hunter(1, 0))]),
        ];
        out_.push(hunter);

        out_
    }

    pub fn crate_variants(gifts: bool) -> Vec<RoomVariant> {
        let shapes: [(&'static str, bool, bool); 3] = [("classic", false, false), ("wide", true, false), ("pairs", false, true)];
        let mut out_ = Vec::new();
        for (id, wide, pair) in shapes {
            let v = RoomVariant::new(id);
            out_.push(v.generated(
                recipe(move |sim, p| Self::_gen_crates(sim, p, gifts, wide, pair)),
                false,
                FairLanes::ARRIVAL_PATH_TICKS,
            ));
        }
        out_
    }

    fn _gen_crates(sim: &mut GameSim, p: &VariantParams, gifts: bool, wide: bool, pair: bool) {
        let c = p.add(sim, Self::_crates(gifts, wide, pair));
        if p.fallback && p.arriving {
            if let Hz::CrateDrop(cd) = &mut sim.room.hazards[c] {
                if cd.col == CrateDrop::WAIT {
                    cd.wait_warn += FairLanes::ARRIVAL_PATH_TICKS;
                } else {
                    cd.warn_left += FairLanes::ARRIVAL_PATH_TICKS;
                }
            }
        }
    }

    pub const BOTH: i64 = 0;
    pub const FLOOR: i64 = 1;
    pub const CEILING: i64 = 2;

    fn _gen_columns(sim: &mut GameSim, p: &VariantParams, rocks: i64) {
        let entry = Self::_from_entry(sim, Self::ENTRY_X);
        let far = Self::_from_entry(sim, Self::FAR_X);
        let a = if rocks == Self::BOTH { Stalactite::new(entry, false) } else { Self::_fang_at(entry, rocks) };
        p.add(sim, Self::_still(a, sim, p, Self::ENTRY_GAP).into());
        let mut b = if rocks == Self::BOTH { Stalactite::new(far, false) } else { Self::_fang_at(far, rocks) };
        if rocks != Self::FLOOR {
            b.gap = Self::FAR_GAP;
        }
        b.scheduled = true;
        b.start_y = (p.hold_top(sim) + p.hold_bottom(sim)) / 2;
        p.add(sim, b.into());
    }

    fn _from_entry(sim: &GameSim, x: i64) -> i64 {
        if sim.state.started && sim.state.vx < 0 {
            SimConfig::WORLD_W - x
        } else {
            x
        }
    }

    fn _fang_at(x: i64, rocks: i64) -> Stalactite {
        let mut s = Stalactite::new(x, false);
        s.top = rocks == Self::CEILING;
        s.bottom = rocks != Self::CEILING;
        s.gap = if rocks == Self::CEILING { Stalactite::GAP } else { Self::FANG_GAP };
        s
    }

    fn _still(mut s: Stalactite, sim: &GameSim, p: &VariantParams, gap: i64) -> Stalactite {
        let mid = (p.hold_top(sim) + p.hold_bottom(sim)) / 2;
        s.gap = gap;
        s.fixed_lo = mid;
        s.fixed_hi = mid;
        s
    }

    fn _gen_fixed(sim: &mut GameSim, p: &VariantParams, short: bool) {
        for i in 0..3 {
            let mut f = if short { Self::_short(i) } else { Self::_finger(i) };
            f.x = Self::_from_entry(sim, if i < 2 || short { f.x } else { Self::FAR_X });
            if short {
                f = Self::_still(f, sim, p, Self::SHORT_GAP);
            } else {
                f = Self::_still(f, sim, p, Self::ENTRY_GAP);
            }
            p.add(sim, f.into());
        }
    }

    fn _crates(gifts: bool, wide: bool, pair: bool) -> Hz {
        if wide {
            return CrateDrop::new(
                gifts,
                Self::WIDE_COLS,
                Self::WIDE_COL_W,
                Self::WIDE_W,
                Self::WIDE_H,
                Self::WIDE_MAX,
                pair,
            )
            .into();
        }
        CrateDrop::new(
            gifts,
            CrateDrop::COLS,
            CrateDrop::COL_W,
            CrateDrop::CRATE,
            CrateDrop::CRATE,
            CrateDrop::MAX_HEIGHT,
            pair,
        )
        .into()
    }

    fn _hunter(slot: i64, home: i64) -> Hz {
        Dart::new(false, slot, home).into()
    }

    /// Generated Piston Press (_gen_press).
    fn _gen_press(sim: &mut GameSim, p: &VariantParams) {
        let n = Self::PRESS_MIN + if p.score >= Self::PRESS_MORE_AT { 1 } else { 0 };
        let gap = if n == Self::PRESS_MIN { Self::PRESS_ROW_GAP_FEW } else { Self::PRESS_ROW_GAP };
        let slack = Self::PRESS_BOTTOM - Self::PRESS_TOP - (n - 1) * gap;
        let mut offs: Vec<i64> = Vec::new();
        for _i in 0..n {
            offs.push(sim._rng.next_below(slack + 1));
        }
        offs.sort();
        let glow = G::maxi(Piston::GLOW_TICKS, Self::PRESS_GLOW - p.level * Self::PRESS_GLOW_STEP);
        let rhythm = sim._rng.next_below(4);
        let beat = Self::PRESS_BEAT_MIN + sim._rng.next_below(Self::PRESS_BEAT_SPAN + 1);
        let period = Piston::IDLE_TICKS + glow + Piston::EXTEND_TICKS + Piston::HOLD_TICKS + Piston::RETRACT_TICKS;
        let mut rams: Vec<Piston> = Vec::new();
        let mut rights = 0;
        for i in 0..n {
            let mut side = sim._rng.next_below(2);
            if side == 1 && rights >= Self::PRESS_MAX_RIGHT {
                side = 0;
            }
            rights += side;
            let reach = Self::PRESS_REACH_MIN + sim._rng.next_below(Self::PRESS_REACH_STEPS) * Self::PRESS_REACH_STEP;
            let at = sim._rng.next_below(period);
            let mut delay = Self::PRESS_DELAY;
            if rhythm == Self::WAVE_DOWN {
                delay += i * beat;
            } else if rhythm == Self::WAVE_UP {
                delay += (n - 1 - i) * beat;
            } else if rhythm == Self::HALVES {
                delay += (i % 2) * (period / 2);
            } else {
                delay += at;
            }
            rams.push(Piston::new(side, Self::PRESS_TOP + i * gap + offs[i as usize], delay, glow, reach));
        }
        if rights == 0 {
            rams[(n / 2) as usize].side = 1;
        }
        for ram in rams {
            let crosses = ram.y + Piston::HALF_H > p.hold_top(sim) && ram.y - Piston::HALF_H < p.hold_bottom(sim);
            if p.fallback && p.arriving && crosses {
                continue;
            }
            p.add(sim, ram.into());
        }
    }

    /// Generated Beam Gates (_gen_beams).
    fn _gen_beams(sim: &mut GameSim, p: &VariantParams) {
        let exits = Self::_planned_exits(sim);
        let mut rows: Vec<i64> = Vec::new();
        for i in 0..Beam::ROWS {
            let drawn = Beam::BAND_TOP + i * (Beam::SPAN / Beam::ROWS) + sim._rng.next_below(Beam::JITTER + 1);
            let y = Self::_beam_row(drawn, &exits, &rows);
            if y >= 0 {
                rows.push(y);
            }
        }
        let s = &sim.state;
        let mut lanes: Vec<i64> = vec![s.plan_a_y_right];
        if s.plan_a_kind_right != ExitKind::NORMAL {
            lanes.push(s.plan_b_y_right);
        }
        let times = Self::_exit_times(sim);
        let first = sim._rng.next_below(Self::_orders(rows.len() as i64).len() as i64) as usize;
        let best = Self::_beam_beat(&rows, &lanes, times[0], first).0;
        let mut b = Beam::new(rows.len() as i64, Beam::WARN_TICKS, false);
        for i in 0..rows.len() {
            b.rows[i] = rows[i];
            b.delays[i] = best[i];
        }
        b.preset = true;
        b.exit_ys = lanes.clone();
        b.calm_spikes = Self::BEAM_CALM_SPIKES;
        p.add(sim, b.into());
    }

    /// The firing order and place in the beat (from irst in the list of orders) that gets a
    /// bird into every lane quickest after shown, and how many steps that takes.
    fn _beam_beat(rows: &[i64], lanes: &[i64], shown: i64, first: usize) -> (Vec<i64>, i64) {
        let orders = Self::_orders(rows.len() as i64);
        let stagger = Beam::PERIOD / Beam::ROWS;
        let mut best: Vec<i64> = Vec::new();
        let mut best_w = -1;
        for k in 0..orders.len() {
            let order = &orders[(first + k) % orders.len()];
            let mut ph = 0;
            while ph < Beam::PERIOD {
                let mut delays: Vec<i64> = Vec::new();
                for i in 0..rows.len() {
                    delays.push(Beam::START_DELAY + (order[i] * stagger + ph) % Beam::PERIOD);
                }
                let mut w = 0;
                for &e in lanes {
                    w = G::maxi(w, Self::_beam_reach(rows, &delays, shown, e));
                }
                if best_w < 0 || w < best_w {
                    best = delays;
                    best_w = w;
                }
                ph += Self::BEAM_PHASE_STEP;
            }
        }
        (best, best_w)
    }

    fn _beam_reach(rows: &[i64], delays: &[i64], shown: i64, e: i64) -> i64 {
        let mut w = 0;
        let mut y0 = SimConfig::KILL_TOP + SimConfig::BIRD_RADIUS;
        while y0 <= SimConfig::KILL_BOTTOM - SimConfig::BIRD_RADIUS {
            let mut free = true;
            for &r in rows {
                if G::absi(y0 - r) < Beam::HALF_H + SimConfig::BIRD_RADIUS {
                    free = false;
                }
            }
            if free {
                for late in [0, Self::BEAM_LATE] {
                    let to = Beam::reach_time(rows, delays, y0, shown + late, e - Self::BEAM_LANE, e + Self::BEAM_LANE);
                    w = G::maxi(w, late + to);
                }
            }
            y0 += Self::BEAM_START_STEP;
        }
        w
    }
    /// Room steps until the exit preview shows and until the bird reaches the exit wall after it opens.
    fn _exit_times(sim: &GameSim) -> [i64; 2] {
        let heading = if sim.state.vx > 0 { 1 } else { 0 };
        let t1 = sim.steps_to_wall(heading);
        let c = sim.steps_to_wall(1 - heading) - t1;
        let k_open = sim.next_exit_score() - sim.state.score;
        let open_side = if k_open % 2 == 1 { heading } else { 1 - heading };
        let k_arr = if open_side == SimConfig::EXIT_WALL { k_open + 2 } else { k_open + 1 };
        let k_prev = G::maxi(1, k_open - 1);
        [t1 + (k_prev - 1) * c, t1 + (k_arr - 1) * c]
    }

    fn _planned_exits(sim: &mut GameSim) -> Vec<i64> {
        let at = sim.next_exit_score();
        ExitPlanner::plan_room(sim, at);
        let s = &sim.state;
        let mut out_: Vec<i64> = vec![s.plan_a_y_left, s.plan_a_y_right];
        if s.plan_a_kind_left != ExitKind::NORMAL {
            out_.push(s.plan_b_y_left);
        }
        if s.plan_a_kind_right != ExitKind::NORMAL {
            out_.push(s.plan_b_y_right);
        }
        out_
    }

    fn _beam_row(drawn: i64, exits: &[i64], placed: &[i64]) -> i64 {
        let mut d = 0;
        while d <= Self::BEAM_SHIFT {
            for y in [drawn - d, drawn + d] {
                if Self::_beam_row_ok(y, exits, placed) {
                    return y;
                }
            }
            d += Self::BEAM_STEP;
        }
        -1
    }

    fn _beam_row_ok(y: i64, exits: &[i64], placed: &[i64]) -> bool {
        if y < Self::BEAM_TOP || y > Self::BEAM_BOTTOM {
            return false;
        }
        if !placed.is_empty() && y - placed[placed.len() - 1] < Self::BEAM_APART {
            return false;
        }
        for &e in exits {
            if G::absi(y - e) < Self::BEAM_EXIT_CLEAR {
                return false;
            }
        }
        true
    }

    fn _orders(n: i64) -> Vec<Vec<i64>> {
        let mut out_: Vec<Vec<i64>> = Vec::new();
        let mut cur: Vec<i64> = Vec::new();
        Self::_orders_from(n, &mut cur, &mut out_);
        out_
    }

    fn _orders_from(n: i64, cur: &mut Vec<i64>, out_: &mut Vec<Vec<i64>>) {
        if cur.len() as i64 == n {
            out_.push(cur.clone());
            return;
        }
        for v in 0..n {
            if !cur.contains(&v) {
                cur.push(v);
                Self::_orders_from(n, cur, out_);
                cur.pop();
            }
        }
    }

    fn _finger(i: i64) -> Stalactite {
        let mut s = Stalactite::new(Self::TRIO_X[i as usize] * Self::SUB, i > 0);
        s.top = i % 2 == 0;
        s.bottom = i % 2 == 1;
        s.gap = Self::ALT_GAP;
        s.fixed_lo = Self::ALT_LO;
        s.fixed_hi = Self::ALT_HI;
        s
    }

    fn _short(i: i64) -> Stalactite {
        let mut s = Stalactite::new(Self::TRIO_X[i as usize] * Self::SUB, i > 0);
        s.gap = Self::SHORT_GAP;
        s.half_w = Self::SHORT_HALF_W;
        s.fixed_lo = Self::SHORT_Y;
        s.fixed_hi = Self::SHORT_Y;
        s
    }
}
