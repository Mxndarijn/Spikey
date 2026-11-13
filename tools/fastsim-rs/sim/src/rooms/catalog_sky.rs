//! Port of sim/rooms/catalog_sky.gd (Sim/Rooms/CatalogSky.cs). Order is part of the rules.
use crate::hazards::drop::Style;
use crate::prelude::*;

pub struct CatalogSky;

impl CatalogSky {
    pub const SUB: i64 = SimConfig::SUB;
    pub const SPIKY_SPREAD: i64 = 230;

    pub fn defs() -> Vec<RoomDef> {
        const SUB: i64 = CatalogSky::SUB;
        let mut out_ = Vec::new();

        let mut updraft = RoomDef::new("updraft", "mid", 60);
        for shape in ["chimney", "twin", "drift", "gust", "updown", "coins"] {
            updraft.variants.push(
                RoomVariant::new(shape).generated(recipe(move |sim, p| Self::_gen_updraft(sim, p, shape)), false, 0),
            );
        }
        out_.push(updraft);

        let mut bubbles = RoomDef::new("bubbles", "mid", 50);
        let mut classic: Vec<Factory> = Vec::new();
        let mut giants: Vec<Factory> = Vec::new();
        let mut coin_bubbles: Vec<Factory> = Vec::new();
        for lane in 0..3i64 {
            let l = lane;
            classic.push(mk(move || Self::_bubble(l)));
            giants.push(mk(move || Self::_giant(l)));
            coin_bubbles.push(if l % 2 == 0 {
                mk(move || Self::_coin_bubble(l))
            } else {
                mk(move || Self::_bubble(l))
            });
        }
        let spiky: Vec<Factory> = vec![
            mk(|| Self::_bubble(0)),
            mk(|| Self::_spiky_bubble(1, 0)),
            mk(|| Self::_bubble(2)),
            mk(|| Self::_spiky_bubble(3, Self::SPIKY_SPREAD)),
        ];
        bubbles.variants = vec![
            RoomVariant::new("classic").generated(recipe(move |sim, p| Self::_gen_bubbles(sim, p, &classic)), true, 0),
            RoomVariant::new("giants").generated(recipe(move |sim, p| Self::_gen_bubbles(sim, p, &giants)), true, 0),
            RoomVariant::new("spiky").generated(recipe(move |sim, p| Self::_gen_bubbles(sim, p, &spiky)), true, 0),
            RoomVariant::new("coin-bubbles")
                .generated(recipe(move |sim, p| Self::_gen_bubbles(sim, p, &coin_bubbles)), true, 0),
        ];
        out_.push(bubbles);

        let mut rain = RoomDef::new("rain", "late", 70);
        rain.weight = 8;
        // Hail's four drops come thick: each is marked a full second.
        let mut hail: Vec<Factory> = Vec::new();
        for d in [30i64, 55, 80, 105] {
            let dd = d;
            hail.push(mk(move || Self::_rain(dd, 10 * SUB, 45, 60, 6 * SUB, Style::PLAIN)));
        }
        let mut sweep: Vec<Factory> = Vec::new();
        for i in 0..4i64 {
            let ii = i;
            sweep.push(mk(move || Self::_sweep(30 + 12 * ii, (45 + 90 * ii) * SUB)));
        }
        let classic_rain: Vec<Factory> = vec![mk(|| Self::_drop(30, 10 * SUB, 25)), mk(|| Self::_drop(70, 10 * SUB, 25))];
        let drizzle: Vec<Factory> = vec![
            mk(|| Self::_rain(30, 6 * SUB, 30, 75, Drop::RADIUS, Style::PLAIN)),
            mk(|| Self::_rain(135, 6 * SUB, 30, 75, Drop::RADIUS, Style::PLAIN)),
        ];
        let shatter: Vec<Factory> = vec![
            mk(|| Self::_rain(30, 10 * SUB, 40, 50, Drop::RADIUS, Style::SHATTER)),
            mk(|| Self::_rain(85, 10 * SUB, 40, 50, Drop::RADIUS, Style::SHATTER)),
        ];
        let wobble: Vec<Factory> = vec![
            mk(|| Self::_rain(30, 7 * SUB, 30, 55, Drop::RADIUS, Style::WOBBLE)),
            mk(|| Self::_rain(90, 7 * SUB, 30, 55, Drop::RADIUS, Style::WOBBLE)),
        ];
        let stake: Vec<Factory> = vec![
            mk(|| Self::_rain(30, 8 * SUB, 30, 60, 13 * SUB, Style::STAKE)),
            mk(|| Self::_rain(140, 8 * SUB, 30, 60, 13 * SUB, Style::STAKE)),
        ];
        let hold = FairLanes::ARRIVAL_PATH_TICKS;
        let sets: Vec<(&'static str, Vec<Factory>, bool)> = vec![
            ("classic", classic_rain, false),
            ("drizzle", drizzle, false),
            ("hail", hail, false),
            ("sweep", sweep, true),
            ("shatter", shatter, false),
            ("wobble", wobble, false),
            ("stake", stake, false),
        ];
        for (id, fs, is_sweep) in sets {
            rain.variants.push(
                RoomVariant::new(id).generated(recipe(move |sim, p| Self::_gen_rain(sim, p, &fs, is_sweep)), false, hold),
            );
        }
        out_.push(rain);

        let mut orchard = RoomDef::new("orchard", "bonus", 30);
        orchard.weight = 4;
        orchard.max_spikes = 2;
        orchard.bounce_coin = false;
        orchard.hazards.push(mk(|| OrchardSpawner::new().into()));
        orchard.hazards.push(mk(|| Self::_drop(90, 6 * SUB, 140)));
        out_.push(orchard);

        let mut keepy = RoomDef::new("keepy", "bonus", 40);
        keepy.weight = 4;
        keepy.max_spikes = 3;
        keepy.variants = vec![
            RoomVariant::new("classic").with(vec![mk(|| KeepyBall::new().into())]),
            RoomVariant::new("two-balls").with(vec![
                mk(|| KeepyBall::new().dropping(0).into()),
                mk(|| KeepyBall::new().dropping(KeepyBall::SECOND_DROP).into()),
            ]),
        ];
        out_.push(keepy);

        out_
    }

    fn _air(x_px: i64, half_px: i64, lift: i64) -> Hz {
        Updraft::new(x_px * Self::SUB, half_px * Self::SUB, lift).into()
    }

    fn _drift(min_px: i64, span_px: i64, half_px: i64) -> Hz {
        Updraft::new(min_px * Self::SUB, half_px * Self::SUB, Updraft::HOVER)
            .drifting(min_px * Self::SUB, span_px * Self::SUB)
            .into()
    }

    fn _gust() -> Hz {
        Updraft::new(SimConfig::WORLD_W / 2, Updraft::HALF_W, Updraft::STRONG).gusty().into()
    }

    /// CoinPickup(x, y): C# default p_appear_at = 0.
    fn _coin(x_px: i64, y_px: i64) -> Hz {
        CoinPickup::new(x_px * Self::SUB, y_px * Self::SUB, 0).into()
    }

    /// Bubble(lane): C# defaults p_radius = RADIUS, p_rise = RISE.
    fn _gen_updraft(sim: &mut GameSim, p: &VariantParams, shape: &str) {
        let cx = 180;
        let mut made = Vec::new();
        match shape {
            "chimney" => made.push(p.add(sim, Self::_air(cx, 50, Updraft::CHIMNEY))),
            "twin" => {
                made.push(p.add(sim, Self::_air(100, 40, Updraft::HOVER)));
                made.push(p.add(sim, Self::_air(260, 40, Updraft::HOVER)));
            }
            "drift" => made.push(p.add(sim, Self::_drift(70, 220, 50))),
            "gust" => {
                let g = p.add(sim, Self::_gust());
                if p.arriving {
                    if let Hz::Updraft(u) = &mut sim.room.hazards[g] {
                        u.phase = 0;
                        u._update();
                    }
                }
                made.push(g);
            }
            "updown" => {
                made.push(p.add(sim, Self::_air(120, 50, Updraft::HOVER)));
                made.push(p.add(sim, Self::_air(240, 50, -Updraft::HOVER)));
            }
            _ => {
                made.push(p.add(sim, Self::_air(cx, 60, Updraft::LIFT)));
                for y_px in [220, 270, 320] {
                    p.add(sim, Self::_coin(cx, y_px));
                }
            }
        }
        if p.arriving && (p.fallback || shape == "updown") {
            for i in made {
                VariantParams::edit(sim, i, |h, sim| {
                    if let Hz::Updraft(u) = h {
                        u.clear_band(sim, p);
                    }
                });
            }
        }
    }

    fn _gen_bubbles(sim: &mut GameSim, p: &VariantParams, factories: &[Factory]) {
        let made = p.add_all(sim, factories);
        if !p.fallback || !p.arriving {
            return;
        }
        for i in made {
            if let Hz::Bubble(b) = &mut sim.room.hazards[i] {
                if !b.spiked {
                    b.y = SimConfig::WORLD_H + b.radius;
                }
            }
        }
    }

    fn _bubble(lane: i64) -> Hz {
        Bubble::new(lane, Bubble::RADIUS, Bubble::RISE).into()
    }

    fn _giant(lane: i64) -> Hz {
        Bubble::new(lane, Bubble::GIANT_RADIUS, Bubble::GIANT_RISE).into()
    }

    fn _spiky_bubble(lane: i64, delay: i64) -> Hz {
        Bubble::new(lane, Bubble::RADIUS, Bubble::RISE).spiky(delay).into()
    }

    fn _coin_bubble(lane: i64) -> Hz {
        Bubble::new(lane, Bubble::RADIUS, Bubble::RISE).with_coin().into()
    }

    /// Drop(delay, speed, gap): C# defaults p_warn = WARN, p_radius = RADIUS,
    /// p_style = Style.PLAIN, p_column = -1.
    fn _drop(delay: i64, speed: i64, gap: i64) -> Hz {
        Drop::new(delay, speed, gap, Drop::WARN, Drop::RADIUS, Style::PLAIN, -1).into()
    }

    fn _rain(delay: i64, speed: i64, gap: i64, warn: i64, radius: i64, style: i64) -> Hz {
        Drop::new(delay, speed, gap, warn, radius, style, -1).into()
    }

    fn _gen_rain(sim: &mut GameSim, p: &VariantParams, factories: &[Factory], sweep: bool) {
        let mut flip = false;
        if sweep && p.arriving && !p.fallback {
            flip = sim._rng.next_below(2) == 1;
        }
        let made = p.add_all(sim, factories);
        for i in made {
            if let Hz::Drop(d) = &mut sim.room.hazards[i] {
                if flip {
                    d.column = SimConfig::WORLD_W - d.column;
                }
                if p.fallback && p.arriving {
                    d.timer += FairLanes::ARRIVAL_PATH_TICKS;
                }
            }
        }
    }

    fn _sweep(delay: i64, column: i64) -> Hz {
        Drop::new(delay, 10 * Self::SUB, 60, Drop::WARN, Drop::RADIUS, Style::PLAIN, column).into()
    }
}
