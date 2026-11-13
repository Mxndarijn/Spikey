//! Checks.BlindSeeds (HonestyCheck.cs) and the seed scan of Honesty.cs (Honesty.seedscan): a
//! blind copy carries no true random state. Every SimRng, every *seed* / *salt* field and every
//! raw draw found in the sim's state must be replaced or dropped by BlindPlanner::blind_copy.
//! The scan itself is tested too: with the boss seed left in, it must say so.
//!
//! C# finds the fields by reflection; Rust has none, so `seed_fields` walks every field of
//! GameSim, SimState, RoomRuntime and each hazard by hand, under its C# name and with the C#
//! rules (long, long[], List<long>, SimRng; links to other hazards, strings, bools, ints, the
//! catalog skipped). A new field or hazard must be added here by hand.
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::sync::atomic::Ordering as AtomicOrdering;

use serde_json::{json, Value};
use sim::prelude::*;
use sim::rooms::room_runtime::RoomRuntime;

use super::{culture_cmp, result, Check};
use crate::bots::blind_planner::{BlindPlanner, BOSS_BLIND};
use crate::bots::SimBots;

pub struct BlindSeeds;

impl Check for BlindSeeds {
    fn name(&self) -> &'static str {
        "blind_seeds"
    }
    fn test(&self) -> &'static str {
        "tools/fastsim-rs/fastsim/src/checks/honesty.rs"
    }
    fn count(&self) -> usize {
        1
    }
    fn exclusive(&self) -> bool {
        true
    }

    fn run(&self, _n: usize) -> Value {
        let mut fails: Vec<String> = Vec::new();
        let mut lines: Vec<String> = Vec::new();
        let boss = BOSS_BLIND.load(AtomicOrdering::Relaxed);
        BOSS_BLIND.store(true, AtomicOrdering::Relaxed);
        if Honesty::seedscan(1, 600, &mut lines) > 0 {
            fails.extend(lines.iter().filter(|l| l.contains("UNCHANGED")).map(|l| l.trim().to_string()));
        }
        let mut open: Vec<String> = Vec::new();
        BOSS_BLIND.store(false, AtomicOrdering::Relaxed);
        Honesty::seedscan(1, 600, &mut open);
        if !open.iter().any(|l| l.contains("UNCHANGED") && l.contains("Boss")) {
            fails.push("the seed scan does not notice a boss seed left in the blind copy".to_string());
        }
        BOSS_BLIND.store(boss, AtomicOrdering::Relaxed);
        result(fails, json!({ "scan": lines.first().cloned().unwrap_or_default() }))
    }

    fn summary(&self, results: &[Value]) -> String {
        let scan = results.first().map(|r| crate::yardstick::node_str(&r["scan"])).unwrap_or_default();
        format!("blind copies carry no true seed ({})", scan)
    }
}

/// The seed-scan part of Honesty.cs.
pub struct Honesty;

/// Collects the seed-bearing values of one object (C# `seed_fields(root, path, out_, seen)`).
struct Scan<'a> {
    out_: &'a mut HashMap<String, i64>,
    path: String,
}

impl<'a> Scan<'a> {
    fn at(&self, name: &str) -> String {
        if self.path.is_empty() {
            name.to_string()
        } else {
            format!("{}.{}", self.path, name)
        }
    }

    fn number_at(&mut self, field: &str, where_: String, n: i64) {
        let name = field.to_lowercase();
        if name.contains("seed") || name.contains("salt") || n.unsigned_abs() >= Honesty::RAW as u64 {
            self.out_.insert(where_, n);
        }
    }

    /// `case long n`.
    fn n(&mut self, field: &str, n: i64) {
        let at = self.at(field);
        self.number_at(field, at, n);
    }

    /// `case long[] arr` and `case List<long> list`.
    fn list(&mut self, field: &str, xs: &[i64]) {
        let at = self.at(field);
        for (i, &x) in xs.iter().enumerate() {
            self.number_at(field, format!("{}[{}]", at, i), x);
        }
    }

    /// `case SimRng rng`.
    fn rng(&mut self, field: &str, r: &SimRng) {
        let at = self.at(field);
        self.out_.insert(at, r.state_checksum());
    }

    fn sub(&mut self, field: &str) -> Scan<'_> {
        let path = self.at(field);
        Scan { out_: &mut *self.out_, path }
    }
}

impl Honesty {
    /// Seed-bearing values that may stay as they are in a blind copy, each with the reason.
    pub const SEEDS_SHOWN: [(&'static str, &'static str); 3] = [
        ("room.tide_salt", "the phase of the tide spikes: their motion is on screen"),
        ("state.deck_lo", "the rooms drawn from the room bag (a bitmask): every one was on screen"),
        ("state.deck_hi", "the rooms drawn from the room bag (a bitmask): every one was on screen"),
    ];

    pub const RAW: i64 = 1 << 24;

    fn state_fields(s: &mut Scan, st: &SimState) {
        s.n("tick", st.tick);
        s.n("death_cause", st.death_cause);
        s.n("x", st.x);
        s.n("y", st.y);
        s.n("vx", st.vx);
        s.n("vy", st.vy);
        s.n("score", st.score);
        s.n("room_index", st.room_index);
        s.n("room_kind", st.room_kind);
        s.n("left_spikes", st.left_spikes);
        s.n("right_spikes", st.right_spikes);
        s.n("coin_x", st.coin_x);
        s.n("coin_y", st.coin_y);
        s.n("coins", st.coins);
        s.n("flaps", st.flaps);
        s.n("exit_side", st.exit_side);
        s.n("exit_a_y", st.exit_a_y);
        s.n("exit_a_kind", st.exit_a_kind);
        s.n("exit_b_y", st.exit_b_y);
        s.n("exit_b_kind", st.exit_b_kind);
        s.n("route", st.route);
        s.n("bosses_met", st.bosses_met);
        s.n("deck_lo", st.deck_lo);
        s.n("deck_hi", st.deck_hi);
        s.n("pickup_x", st.pickup_x);
        s.n("pickup_y", st.pickup_y);
        s.n("arrival_hold", st.arrival_hold);
        s.n("revives", st.revives);
        s.n("anchor_y", st.anchor_y);
        s.n("plan_a_y_left", st.plan_a_y_left);
        s.n("plan_a_kind_left", st.plan_a_kind_left);
        s.n("plan_b_y_left", st.plan_b_y_left);
        s.n("plan_a_y_right", st.plan_a_y_right);
        s.n("plan_a_kind_right", st.plan_a_kind_right);
        s.n("plan_b_y_right", st.plan_b_y_right);
        s.n("plan_at", st.plan_at);
    }

    fn room_fields(s: &mut Scan, r: &RoomRuntime) {
        // def: the catalog (skipped).
        s.n("index", r.index);
        s.n("t", r.t);
        s.n("ticks", r.ticks);
        s.n("points", r.points);
        s.n("variant", r.variant);
        for (i, h) in r.hazards.iter().enumerate() {
            let field = format!("hazards[{}:{}]", i, hz_name(h));
            let mut hs = s.sub(&field);
            Self::hazard_fields(&mut hs, h);
        }
        s.n("tide_left", r.tide_left);
        s.n("tide_right", r.tide_right);
        s.n("tide_salt", r.tide_salt);
        s.n("blink_left", r.blink_left);
        s.n("blink_right", r.blink_right);
        s.n("gravity", r.gravity);
        s.n("rng_seed", r.rng_seed);
        s.n("walls", r.walls);
        s.n("entry_score", r.entry_score);
    }

    fn base_fields(s: &mut Scan, b: &Base) {
        // kind (string), alive (bool).
        s.n("t", b.t);
    }

    fn boss_fields(s: &mut Scan, b: &Boss) {
        s.n("tier", b.tier);
        s.n("phase", b.phase);
        s.n("phase_start", b.phase_start);
        s.n("down_at", b.down_at);
        s.n("seed", b.seed);
        Self::base_fields(s, &b.base);
    }

    fn bouncer_fields(s: &mut Scan, b: &Bouncer) {
        s.n("radius", b.radius);
        s.n("lane", b.lane);
        s.n("x", b.x);
        s.n("y", b.y);
        s.n("vx", b.vx);
        s.n("vy", b.vy);
        Self::base_fields(s, &b.base);
    }

    fn coin_fields(s: &mut Scan, c: &CoinPickup) {
        s.n("x", c.x);
        s.n("y", c.y);
        s.n("appear_at", c.appear_at);
        s.n("vy", c.vy);
        s.n("beside_band", c.beside_band);
        s.n("value", c.value);
        s.n("drift", c.drift);
        s.n("home_x", c.home_x);
        Self::base_fields(s, &c.base);
    }

    /// Every long / long[] / List<long> / SimRng field of the hazard and its C# base classes.
    /// Links to other hazards (Gate.partner, Piston.leader, Stalactite.partner,
    /// SplittingBouncer.other) are skipped, as in C#.
    fn hazard_fields(s: &mut Scan, h: &Hz) {
        match h {
            Hz::Taken => {}
            Hz::Beam(x) => {
                s.list("rows", &x.rows);
                s.list("delays", &x.delays);
                s.n("warn_ticks", x.warn_ticks);
                s.list("skip", &x.skip);
                Self::base_fields(s, &x.base);
            }
            Hz::Belt(x) => {
                s.n("mode", x.mode);
                s.n("left_dir", x.left_dir);
                s.n("right_dir", x.right_dir);
                s.n("left_shift", x.left_shift);
                s.n("right_shift", x.right_shift);
                Self::base_fields(s, &x.base);
            }
            Hz::Block(x) => {
                s.n("x0", x.x0);
                s.n("y0", x.y0);
                s.n("x1", x.x1);
                s.n("y1", x.y1);
                s.n("fade_period", x.fade_period);
                s.n("solid_ticks", x.solid_ticks);
                s.n("phase", x.phase);
                s.n("base_phase", x.base_phase);
                s.n("band", x.band);
                s.n("drift", x.drift);
                s.n("home_x", x.home_x);
                Self::base_fields(s, &x.base);
            }
            Hz::BossCrusher(x) => {
                s.n("press_y", x.press_y);
                s.n("plate_y", x.plate_y);
                s.n("slam_y", x.slam_y);
                s.n("lane_from", x.lane_from);
                s.n("lane_to", x.lane_to);
                s.list("crate_x", &x.crate_x);
                s.list("crate_y", &x.crate_y);
                s.list("crate", &x.crate_);
                s.n("_k", x._k);
                Self::boss_fields(s, &x.boss);
            }
            Hz::BossSaw(x) => {
                s.n("king_y", x.king_y);
                s.n("from_y", x.from_y);
                s.n("to_y", x.to_y);
                s.n("ring", x.ring);
                s.n("angle", x.angle);
                s.n("blades", x.blades);
                s.list("blade_x", &x.blade_x);
                s.list("blade_y", &x.blade_y);
                s.n("_k", x._k);
                Self::boss_fields(s, &x.boss);
            }
            Hz::BossWatcher(x) => {
                s.n("lit", x.lit);
                s.n("beam", x.beam);
                s.n("beam_t", x.beam_t);
                s.n("dart", x.dart);
                s.n("dart_lane", x.dart_lane);
                s.n("dart_side", x.dart_side);
                s.n("dart_x", x.dart_x);
                s.n("dart_t", x.dart_t);
                s.n("_lit_k", x._lit_k);
                Self::boss_fields(s, &x.boss);
            }
            Hz::Bouncer(x) => Self::bouncer_fields(s, x),
            Hz::Bubble(x) => {
                s.n("x", x.x);
                s.n("y", x.y);
                s.n("vy", x.vy);
                s.n("next_x", x.next_x);
                s.n("lane", x.lane);
                s.n("cooldown", x.cooldown);
                s.n("since_pop", x.since_pop);
                s.n("radius", x.radius);
                s.n("wait", x.wait);
                s.n("delay", x.delay);
                Self::base_fields(s, &x.base);
            }
            Hz::Bumper(x) => {
                s.n("radius", x.radius);
                s.n("loop_rx", x.loop_rx);
                s.n("loop_ry", x.loop_ry);
                s.n("period", x.period);
                s.n("x", x.x);
                s.n("y", x.y);
                s.n("phase", x.phase);
                s.n("dir", x.dir);
                Self::base_fields(s, &x.base);
            }
            Hz::CoinPickup(x) => Self::coin_fields(s, x),
            Hz::CrateDrop(x) => {
                s.n("cols", x.cols);
                s.n("col_w", x.col_w);
                s.n("col_x0", x.col_x0);
                s.n("crate_w", x.crate_w);
                s.n("crate_h", x.crate_h);
                s.n("max_height", x.max_height);
                s.n("col", x.col);
                s.n("y", x.y);
                s.n("vy", x.vy);
                s.n("col_b", x.col_b);
                s.n("y_b", x.y_b);
                s.n("vy_b", x.vy_b);
                s.n("warn_left", x.warn_left);
                s.n("drops", x.drops);
                s.n("salt", x.salt);
                s.list("heights", &x.heights);
                s.list("coins", &x.coins);
                Self::base_fields(s, &x.base);
            }
            Hz::Crawler(x) => {
                s.n("lane", x.lane);
                s.n("start", x.start);
                s.n("segments", x.segments);
                s.n("seg_radius", x.seg_radius);
                s.n("spacing", x.spacing);
                s.n("speed", x.speed);
                s.n("reserve", x.reserve);
                s.list("xs", &x.xs);
                s.list("ys", &x.ys);
                Self::base_fields(s, &x.base);
            }
            Hz::CuriousBouncer(x) => {
                s.n("look", x.look);
                Self::bouncer_fields(s, &x.b);
            }
            Hz::Dart(x) => {
                s.n("lane_count", x.lane_count);
                s.n("lane_min", x.lane_min);
                s.n("lane_max", x.lane_max);
                s.n("lanes_speed", x.lanes_speed);
                s.n("lanes_flash", x.lanes_flash);
                s.n("lane2_y", x.lane2_y);
                s.n("slot", x.slot);
                s.n("home", x.home);
                s.n("state", x.state);
                s.n("since", x.since);
                s.n("wait", x.wait);
                s.n("side", x.side);
                s.n("lane_y", x.lane_y);
                s.n("x", x.x);
                s.n("shots", x.shots);
                s.n("salt", x.salt);
                Self::base_fields(s, &x.base);
            }
            Hz::Drop(x) => {
                s.n("x", x.x);
                s.n("y", x.y);
                s.n("phase", x.phase);
                s.n("timer", x.timer);
                s.n("speed", x.speed);
                s.n("gap", x.gap);
                s.n("delay", x.delay);
                s.n("warn", x.warn);
                s.n("radius", x.radius);
                s.n("style", x.style);
                s.n("column", x.column);
                s.n("base_x", x.base_x);
                s.n("fall_t", x.fall_t);
                s.n("shard_t", x.shard_t);
                s.n("shard_x", x.shard_x);
                s.n("shard_dx", x.shard_dx);
                s.n("shard_y", x.shard_y);
                s.n("shard_vy", x.shard_vy);
                s.rng("_rng", &x._rng);
                Self::base_fields(s, &x.base);
            }
            Hz::Echo(x) => {
                s.n("mode", x.mode);
                s.n("x", x.x);
                s.n("y", x.y);
                s.n("facing", x.facing);
                s.list("xs", &x.xs);
                s.list("ys", &x.ys);
                s.n("head", x.head);
                Self::base_fields(s, &x.base);
            }
            Hz::ButtonPair(x) => {
                s.n("width", x.width);
                s.n("top_x0", x.top_x0);
                s.n("bottom_x0", x.bottom_x0);
                s.n("presses", x.presses);
                s.n("since_press", x.since_press);
                s.n("since_wrong", x.since_wrong);
                Self::base_fields(s, &x.base);
            }
            Hz::CrowdFill(x) => {
                s.n("seats_left", x.seats_left);
                s.n("seats_right", x.seats_right);
                s.n("coming_left", x.coming_left);
                s.n("coming_right", x.coming_right);
                s.n("since_pick", x.since_pick);
                s.n("start_seats", x.start_seats);
                s.n("newcomers", x.newcomers);
                s.n("last_run", x.last_run);
                s.n("keep_run", x.keep_run);
                s.n("_seed", x._seed);
                s.rng("_rng", &x._rng);
                Self::base_fields(s, &x.base);
            }
            Hz::ExitKey(x) => {
                s.n("mode", x.mode);
                s.n("count", x.count);
                s.n("got", x.got);
                s.n("taken_mask", x.taken_mask);
                s.list("kx", &x.kx);
                s.list("ky", &x.ky);
                s.list("born", &x.born);
                s.list("chain_off", &x.chain_off);
                s.list("chain_d", &x.chain_d);
                s.n("locked_bounces", x.locked_bounces);
                s.n("walls_left", x.walls_left);
                s.n("walls_right", x.walls_right);
                s.n("door_side", x.door_side);
                s.n("door_a_y", x.door_a_y);
                s.n("door_b_y", x.door_b_y);
                Self::base_fields(s, &x.base);
            }
            Hz::Firework(x) => {
                s.n("x", x.x);
                s.n("y", x.y);
                s.n("burst_y", x.burst_y);
                s.n("phase", x.phase);
                s.n("timer", x.timer);
                s.n("spread", x.spread);
                s.n("delay", x.delay);
                s.n("style", x.style);
                s.n("spent", x.spent);
                s.rng("_rng", &x._rng);
                Self::base_fields(s, &x.base);
            }
            Hz::Gate(x) => {
                s.n("x", x.x);
                s.n("period", x.period);
                s.n("phase", x.phase);
                s.n("gap_y", x.gap_y);
                s.n("gap_size", x.gap_size);
                Self::base_fields(s, &x.base);
            }
            Hz::HeavyBouncer(x) => {
                s.n("bounces", x.bounces);
                Self::bouncer_fields(s, &x.b);
            }
            Hz::KeepyBall(x) => {
                s.n("gravity", x.gravity);
                s.n("kick_vy", x.kick_vy);
                s.n("waiting", x.waiting);
                s.n("redrop", x.redrop);
                s.n("x", x.x);
                s.n("y", x.y);
                s.n("vx", x.vx);
                s.n("vy", x.vy);
                s.n("cooldown", x.cooldown);
                s.n("bumps", x.bumps);
                Self::base_fields(s, &x.base);
            }
            Hz::Lava(x) => {
                s.n("mode", x.mode);
                s.n("line", x.line);
                s.n("rises", x.rises);
                s.n("counted", x.counted);
                s.n("stone_x", x.stone_x);
                s.n("stone_y", x.stone_y);
                s.n("ice_side", x.ice_side);
                s.n("ice_slot", x.ice_slot);
                // raft_on: bool[] (skipped).
                s.list("raft_x", &x.raft_x);
                s.list("raft_dir", &x.raft_dir);
                s.list("raft_age", &x.raft_age);
                s.n("raft_points", x.raft_points);
                Self::base_fields(s, &x.base);
            }
            Hz::Mover(x) => {
                s.n("count", x.count);
                s.n("loop_w", x.loop_w);
                s.n("loop_h", x.loop_h);
                s.n("loop_period", x.loop_period);
                s.n("phase", x.phase);
                s.list("xs", &x.xs);
                s.list("ys", &x.ys);
                s.list("facing", &x.facing);
                Self::base_fields(s, &x.base);
            }
            Hz::OrbitCoin(x) => {
                s.n("cx", x.cx);
                s.n("cy", x.cy);
                s.n("radius", x.radius);
                s.n("phase", x.phase);
                Self::coin_fields(s, &x.c);
            }
            Hz::OrchardSpawner(x) => {
                s.list("xs", &x.xs);
                s.list("ys", &x.ys);
                // live: List<bool> (skipped).
                s.rng("_rng", &x._rng);
                Self::base_fields(s, &x.base);
            }
            Hz::Pendulum(x) => {
                s.n("pivot_x", x.pivot_x);
                s.n("pivot_y", x.pivot_y);
                s.n("length", x.length);
                s.n("radius", x.radius);
                s.n("amplitude", x.amplitude);
                s.n("period", x.period);
                s.n("gust", x.gust);
                s.n("gust_period", x.gust_period);
                s.n("winch", x.winch);
                s.n("winch_period", x.winch_period);
                s.n("twin_x", x.twin_x);
                s.n("twin_length", x.twin_length);
                s.n("phase", x.phase);
                s.n("angle", x.angle);
                s.n("chain", x.chain);
                s.n("x", x.x);
                s.n("y", x.y);
                s.n("x2", x.x2);
                s.n("y2", x.y2);
                Self::base_fields(s, &x.base);
            }
            Hz::Piston(x) => {
                s.n("side", x.side);
                s.n("y", x.y);
                s.n("delay", x.delay);
                s.n("half", x.half);
                s.n("glow_ticks", x.glow_ticks);
                s.n("y_lo", x.y_lo);
                s.n("y_hi", x.y_hi);
                s.n("reach", x.reach);
                s.n("fixed_y", x.fixed_y);
                Self::base_fields(s, &x.base);
            }
            Hz::RevvingBouncer(x) => {
                s.n("level", x.level);
                Self::bouncer_fields(s, &x.b);
            }
            Hz::Rotor(x) => {
                s.n("blades", x.blades);
                s.n("blade_max", x.blade_max);
                s.n("blade_min", x.blade_min);
                s.n("half_w", x.half_w);
                s.n("hub_radius", x.hub_radius);
                s.n("period", x.period);
                s.n("spin", x.spin);
                s.n("hubs", x.hubs);
                s.n("spread_x", x.spread_x);
                s.n("spread_y", x.spread_y);
                s.n("lean", x.lean);
                s.n("center_x", x.center_x);
                s.n("center_y", x.center_y);
                s.n("phase", x.phase);
                s.n("dir", x.dir);
                s.n("angle", x.angle);
                s.n("blade_length", x.blade_length);
                Self::base_fields(s, &x.base);
            }
            Hz::SawRing(x) => {
                s.n("center_x", x.center_x);
                s.n("ring_min", x.ring_min);
                s.n("ring_max", x.ring_max);
                s.n("saw_radius", x.saw_radius);
                s.n("period", x.period);
                s.n("fixed_count", x.fixed_count);
                s.n("ry_num", x.ry_num);
                s.n("ry_den", x.ry_den);
                s.n("inner_count", x.inner_count);
                s.n("inner_min", x.inner_min);
                s.n("inner_max", x.inner_max);
                s.n("inner_saw", x.inner_saw);
                s.n("center_y", x.center_y);
                s.n("count", x.count);
                s.n("phase", x.phase);
                s.n("dir", x.dir);
                s.n("radius", x.radius);
                s.n("inner_radius", x.inner_radius);
                s.n("angle", x.angle);
                s.list("xs", &x.xs);
                s.list("ys", &x.ys);
                Self::base_fields(s, &x.base);
            }
            Hz::SpikeBall(x) => {
                s.n("x", x.x);
                s.n("y", x.y);
                s.list("spots", &x.spots);
                Self::base_fields(s, &x.base);
            }
            Hz::SplittingBouncer(x) => {
                s.n("warn", x.warn);
                // other: a Bouncer (a hazard link, skipped).
                Self::bouncer_fields(s, &x.b);
            }
            Hz::Stalactite(x) => {
                s.n("x", x.x);
                s.n("gap_y", x.gap_y);
                s.n("target_y", x.target_y);
                s.n("gap", x.gap);
                s.n("half_w", x.half_w);
                s.n("fixed_lo", x.fixed_lo);
                s.n("fixed_hi", x.fixed_hi);
                s.list("schedule", &x.schedule);
                s.n("slides", x.slides);
                Self::base_fields(s, &x.base);
            }
            Hz::CaveRock(x) => {
                s.list("top_x", &x.top_x);
                s.list("top_y", &x.top_y);
                s.list("bot_x", &x.bot_x);
                s.list("bot_y", &x.bot_y);
                s.list("isle_x", &x.isle_x);
                s.list("isle_top", &x.isle_top);
                s.list("isle_bot", &x.isle_bot);
                Self::base_fields(s, &x.base);
            }
            Hz::CaveDrip(x) => {
                s.n("x", x.x);
                s.n("tip_y", x.tip_y);
                s.n("floor_y", x.floor_y);
                s.n("first", x.first);
                s.n("every", x.every);
                s.n("y", x.y);
                s.n("eta", x.eta);
                Self::base_fields(s, &x.base);
            }
            Hz::Peg(x) => {
                s.n("x", x.x);
                s.n("base_y", x.base_y);
                s.n("bob", x.bob);
                s.n("phase", x.phase);
                s.n("y", x.y);
                Self::base_fields(s, &x.base);
            }
            Hz::Stalker(x) => {
                s.n("side", x.side);
                s.n("y", x.y);
                s.n("x", x.x);
                Self::base_fields(s, &x.base);
            }
            Hz::Updraft(x) => {
                s.n("x0", x.x0);
                s.n("x1", x.x1);
                s.n("half_w", x.half_w);
                s.n("lift", x.lift);
                s.n("drift_min", x.drift_min);
                s.n("drift_span", x.drift_span);
                s.n("gust", x.gust);
                s.n("phase", x.phase);
                Self::base_fields(s, &x.base);
            }
            Hz::Wind(x) => {
                s.n("mode", x.mode);
                s.n("a_y0", x.a_y0);
                s.n("a_y1", x.a_y1);
                s.n("a_dir", x.a_dir);
                s.n("b_y0", x.b_y0);
                s.n("b_y1", x.b_y1);
                s.n("b_dir", x.b_dir);
                Self::base_fields(s, &x.base);
            }
        }
    }

    /// Every value of the sim that holds raw random state: a SimRng, a number whose field is
    /// named *seed* / *salt*, or any number too big to be a position, a time or a count (a raw draw).
    fn seed_fields(sim: &GameSim) -> HashMap<String, i64> {
        let mut out_: HashMap<String, i64> = HashMap::new();
        let mut s = Scan { out_: &mut out_, path: String::new() };
        s.n("seed_value", sim.seed_value);
        s.n("season", sim.season);
        s.n("practice_room", sim.practice_room);
        Self::state_fields(&mut s.sub("state"), &sim.state);
        Self::room_fields(&mut s.sub("room"), &sim.room);
        s.rng("_rng", &sim._rng);
        s.rng("_spine", &sim._spine);
        s.n("_arrival_unpin", sim._arrival_unpin as i64);
        s.n("_free_lo", sim._free_lo);
        s.n("_free_hi", sim._free_hi);
        // C# null: the four entry fields are taken (and dropped) together.
        if let Some(r) = &sim._entry_room {
            Self::room_fields(&mut s.sub("_entry_room"), r);
        }
        if let Some(st) = &sim._entry_state {
            Self::state_fields(&mut s.sub("_entry_state"), st);
        }
        if sim._entry_room.is_some() {
            s.rng("_entry_rng", &sim._entry_rng);
            s.rng("_entry_spine", &sim._entry_spine);
        }
        s.n("_points_override", sim._points_override);
        s.n("_points_also", sim._points_also);
        out_
    }

    /// "room.hazards[3:Dart].salt" -> "room.hazards[Dart].salt", "x.delays[2]" -> "x.delays[i]".
    fn seed_name(path: &str) -> String {
        let p: Vec<char> = path.chars().collect();
        let mut sb = String::new();
        let mut i = 0;
        while i < p.len() {
            sb.push(p[i]);
            if p[i] == '[' {
                let mut j = i + 1;
                while j < p.len() && p[j].is_ascii_digit() {
                    j += 1;
                }
                if j < p.len() && p[j] == ':' {
                    i = j;
                } else if j < p.len() && p[j] == ']' {
                    sb.push('i');
                    i = j - 1;
                }
            }
            i += 1;
        }
        sb
    }

    /// The seed scan: every room and variant is played for `cap` ticks (and full runs for 8 x
    /// `cap`); every 50 ticks the state gets a blind copy, and every seed-bearing value found in
    /// the state must be gone or replaced in the copy. Returns how many kinds came through unchanged.
    pub fn seedscan(seeds: i64, cap: i64, lines: &mut Vec<String>) -> usize {
        // C# SortedDictionary / SortedSet<string>: culture order.
        let mut bad: BTreeMap<SortKey, (i64, String)> = BTreeMap::new();
        let mut all: BTreeSet<SortKey> = BTreeSet::new();
        let mut states: i64 = 0;
        let defs = RoomCatalog::all();
        let mut runs: Vec<(i64, i64, &'static str)> = Vec::new();
        for seed in 1..=seeds {
            runs.push((seed, -1, ""));
            for r in 0..defs.len() {
                if defs[r].variants.is_empty() {
                    runs.push((seed, r as i64, ""));
                }
                for v in &defs[r].variants {
                    runs.push((seed, r as i64, v.id));
                }
            }
        }
        for (seed, room, variant) in runs {
            let mut sim = GameSim::with(seed, Seasons::NONE, room, variant);
            let mut rng = SimRng::new(seed);
            // C# passes one `own` to every blind_copy and it moves on with each; the Rust
            // blind_copy takes its RNG by value, so `own` is stepped once per copy instead.
            let mut own = SimRng::new(seed * 131 + 7);
            let ticks = if room < 0 { cap * 8 } else { cap };
            for t in 0..ticks {
                if sim.is_over() {
                    // Practice runs cannot revive: start the room again with another seed.
                    if sim.can_revive() {
                        sim.revive();
                    } else if room >= 0 {
                        sim = GameSim::with(seed * 1000 + t, Seasons::NONE, room, variant);
                    } else {
                        break;
                    }
                }
                if t % 50 == 7 {
                    states += 1;
                    let before = Self::seed_fields(&sim);
                    let copy = BlindPlanner::blind_copy(&sim, own, -1, 0, -1, false, false);
                    own.next_u32();
                    let after = Self::seed_fields(&copy);
                    for (path, &value) in &before {
                        let name = Self::seed_name(path);
                        all.insert(SortKey(name.clone()));
                        if value == 0 || Self::SEEDS_SHOWN.iter().any(|s| s.0 == name) {
                            continue;
                        }
                        match after.get(path) {
                            Some(&now) if now == value => {}
                            _ => continue,
                        }
                        let where_ = format!("{}/{}", sim.room.def().id, sim.room.variant_id());
                        let e = bad.entry(SortKey(name)).or_insert((0, String::new()));
                        e.0 += 1;
                        e.1 = where_;
                    }
                }
                let tap = SimBots::gap_seeker(&sim, &mut rng);
                sim.step(tap);
            }
        }
        lines.push(format!(
            "seed scan: {} states over {} rooms and their variants, {} kinds of seed-bearing value:",
            states,
            defs.len(),
            all.len()
        ));
        lines.push(format!("  {}", all.iter().map(|k| k.0.as_str()).collect::<Vec<_>>().join(", ")));
        for (name, why) in Self::SEEDS_SHOWN {
            lines.push(format!("  allowed to stay: {} ({})", name, why));
        }
        for (name, (n, where_)) in &bad {
            lines.push(format!("  UNCHANGED in the blind copy: {}, {} states (for example in {})", name.0, n, where_));
        }
        if bad.is_empty() {
            lines.push("  every one is replaced or dropped by blind_copy".to_string());
        }
        bad.len()
    }
}

/// A string ordered as C# `Comparer<string>.Default` orders it.
#[derive(PartialEq, Eq)]
struct SortKey(String);

impl PartialOrd for SortKey {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for SortKey {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        culture_cmp(&self.0, &other.0)
    }
}

/// C# `hz.GetType().Name`.
pub fn hz_name(h: &Hz) -> &'static str {
    match h {
        Hz::Taken => "Taken",
        Hz::Beam(_) => "Beam",
        Hz::Belt(_) => "Belt",
        Hz::Block(_) => "Block",
        Hz::BossCrusher(_) => "BossCrusher",
        Hz::BossSaw(_) => "BossSaw",
        Hz::BossWatcher(_) => "BossWatcher",
        Hz::Bouncer(_) => "Bouncer",
        Hz::Bubble(_) => "Bubble",
        Hz::Bumper(_) => "Bumper",
        Hz::CaveDrip(_) => "CaveDrip",
        Hz::CaveRock(_) => "CaveRock",
        Hz::ButtonPair(_) => "ButtonPair",
        Hz::CoinPickup(_) => "CoinPickup",
        Hz::CrateDrop(_) => "CrateDrop",
        Hz::Crawler(_) => "Crawler",
        Hz::CrowdFill(_) => "CrowdFill",
        Hz::CuriousBouncer(_) => "CuriousBouncer",
        Hz::Dart(_) => "Dart",
        Hz::Drop(_) => "Drop",
        Hz::Echo(_) => "Echo",
        Hz::ExitKey(_) => "ExitKey",
        Hz::Firework(_) => "Firework",
        Hz::Gate(_) => "Gate",
        Hz::HeavyBouncer(_) => "HeavyBouncer",
        Hz::KeepyBall(_) => "KeepyBall",
        Hz::Lava(_) => "Lava",
        Hz::Mover(_) => "Mover",
        Hz::OrbitCoin(_) => "OrbitCoin",
        Hz::OrchardSpawner(_) => "OrchardSpawner",
        Hz::Peg(_) => "Peg",
        Hz::Pendulum(_) => "Pendulum",
        Hz::Piston(_) => "Piston",
        Hz::RevvingBouncer(_) => "RevvingBouncer",
        Hz::Rotor(_) => "Rotor",
        Hz::SawRing(_) => "SawRing",
        Hz::SpikeBall(_) => "SpikeBall",
        Hz::SplittingBouncer(_) => "SplittingBouncer",
        Hz::Stalactite(_) => "Stalactite",
        Hz::Stalker(_) => "Stalker",
        Hz::Updraft(_) => "Updraft",
        Hz::Wind(_) => "Wind",
    }
}
