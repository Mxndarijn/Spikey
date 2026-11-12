//! Port of sim/rooms/catalog_core.gd (Sim/Rooms/CatalogCore.cs). Order is part of the rules.
use crate::hazards::bouncer::Lane;
use crate::prelude::*;

pub struct CatalogCore;

impl CatalogCore {
    pub const SUB: i64 = SimConfig::SUB;
    pub const GARDEN_CX: i64 = 180 * Self::SUB;
    pub const GARDEN_CY: i64 = 320 * Self::SUB;
    pub const ORBIT_RADIUS: i64 = 95 * Self::SUB;

    pub fn defs() -> Vec<RoomDef> {
        const SUB: i64 = CatalogCore::SUB;
        let mut out_ = Vec::new();

        out_.push(RoomDef::new("open", "starter", 0));

        let mut crowded = RoomDef::new("crowded", "starter", 10);
        crowded.extra_spikes = 1;
        crowded.variants = vec![
            RoomVariant::new("classic"),
            RoomVariant::new("lopsided").leaning(2),
            RoomVariant::new("storm").sized(1, 1, 2),
        ];
        out_.push(crowded);

        let mut narrow = RoomDef::new("narrow", "starter", 10);
        narrow.inset = 50 * SUB;
        narrow.reach = 100 * SUB;
        out_.push(narrow);

        let mut tide = RoomDef::new("tide", "starter", 10);
        tide.wall_mode = WallMode::TIDE;
        tide.variants = vec![
            RoomVariant::new("normal"),
            RoomVariant::new("big").sized(3, 2, -1),
            RoomVariant::new("small").sized(2, 3, 3),
        ];
        out_.push(tide);

        let mut isles = RoomDef::new("isles", "starter", 10);
        isles.max_spikes = 6;
        let still = Self::islands(0);
        let drifting = Self::islands(Block::DRIFT);
        let big_rock: Vec<Factory> = vec![mk(|| Self::_big_rock())];
        isles.variants = vec![
            RoomVariant::new("classic").generated(recipe(move |sim, p| Self::_gen_isles(sim, p, &still)), false, 0),
            RoomVariant::new("drifting").generated(recipe(move |sim, p| Self::_gen_isles(sim, p, &drifting)), false, 0),
            RoomVariant::new("one-big").generated(recipe(move |sim, p| Self::_gen_isles(sim, p, &big_rock)), false, 0),
        ];
        out_.push(isles);

        let mut garden = RoomDef::new("garden", "bonus", 20);
        garden.weight = 4;
        garden.max_spikes = 3;
        garden.bounce_coin_stacks = true;
        let diamond: [[i64; 2]; 4] = [[180, 220], [120, 320], [240, 320], [180, 420]];
        // C# builds `still` once and copies it into `decoy`; a factory is not
        // Clone, so the same list is built twice (same factories, same order).
        let make_still = || -> Vec<Factory> {
            let mut still: Vec<Factory> = Vec::new();
            for p in diamond.iter() {
                let cx = p[0] * SUB;
                let cy = p[1] * SUB;
                still.push(mk(move || Self::_coin(cx, cy, 0)));
            }
            still
        };
        let still = make_still();
        let mut spots: Vec<i64> = Vec::new();
        for p in diamond.iter() {
            spots.push(p[0] * SUB);
            spots.push(p[1] * SUB);
        }
        let mut orbit: Vec<Factory> = Vec::new();
        for i in 0..4i64 {
            let ph = i * SimTrig::TURN / 4;
            orbit.push(mk(move || Self::_orbit_coin(ph)));
        }
        let mut decoy = make_still();
        decoy.push(mk(move || Self::_decoy(spots.clone())));
        garden.variants = vec![
            RoomVariant::new("classic").with(still),
            RoomVariant::new("orbit").with(orbit),
            RoomVariant::new("decoy").with(decoy),
        ];
        out_.push(garden);

        let mut bramble = RoomDef::new("bramble", "mid", 40);
        bramble.variants = vec![
            RoomVariant::new("classic")
                .with(vec![mk(|| Bouncer::new(Bouncer::RADIUS, Lane::ANY).into())]),
            RoomVariant::new("twin")
                .with(vec![mk(|| Self::_twin(Lane::UPPER)), mk(|| Self::_twin(Lane::LOWER))]),
            RoomVariant::new("split").with(vec![mk(|| SplittingBouncer::new().into())]),
            RoomVariant::new("revup").with(vec![mk(|| RevvingBouncer::new().into())]),
            RoomVariant::new("curious").with(vec![mk(|| CuriousBouncer::new().into())]),
            RoomVariant::new("heavy").with(vec![mk(|| HeavyBouncer::new().into())]),
        ];
        out_.push(bramble);

        let mut squeeze = RoomDef::new("squeeze", "mid", 50);
        squeeze.squeeze = true;
        squeeze.variants = vec![
            RoomVariant::new("classic"),
            RoomVariant::new("left-only").squeezing(Squeeze::LEFT),
            RoomVariant::new("breathing").squeezing(Squeeze::BREATHE),
        ];
        out_.push(squeeze);

        let mut slowmo = RoomDef::new("slowmo", "bonus", 60);
        slowmo.weight = 4;
        slowmo.speed = Speed::SLOW;
        slowmo.max_spikes = 2;
        let arc: [i64; 5] = [0, 60, 80, 60, 0];
        let mut arc_coins: Vec<Factory> = Vec::new();
        let mut zigzag: Vec<Factory> = Vec::new();
        for i in 0..5i64 {
            let x = (90 + i * 45) * SUB;
            let y = (330 - arc[i as usize]) * SUB;
            let zy = (if i % 2 == 1 { 380 } else { 280 }) * SUB;
            arc_coins.push(mk(move || Self::_coin(x, y, 0)));
            zigzag.push(mk(move || Self::_coin(x, zy, 0)));
        }
        slowmo.variants = vec![
            RoomVariant::new("classic").with(arc_coins),
            RoomVariant::new("zigzag").with(zigzag),
        ];
        out_.push(slowmo);

        let mut blink = RoomDef::new("blink", "late", 80);
        blink.weight = 8;
        blink.wall_mode = WallMode::BLINK;
        blink.variants = vec![
            RoomVariant::new("classic"),
            RoomVariant::new("fast").blinking(RoomRuntime::BLINK_PERIOD / 2),
        ];
        out_.push(blink);

        let mut flip = RoomDef::new("flip", "late", 90);
        flip.weight = 8;
        flip.gravity_sign = -1;
        flip.variants = vec![RoomVariant::new("classic"), RoomVariant::new("flip-flop").flipping()];
        out_.push(flip);

        let mut midnight = RoomDef::new("midnight", "late", 100);
        midnight.weight = 8;
        midnight.speed = Speed::FAST;
        midnight.extra_spikes = 2;
        midnight.variants = vec![
            RoomVariant::new("classic"),
            RoomVariant::new("lantern"),
            RoomVariant::new("flicker"),
        ];
        out_.push(midnight);

        out_
    }

    pub fn islands(drift: i64) -> Vec<Factory> {
        let mut out_: Vec<Factory> = Vec::new();
        for i in 0..4i64 {
            let bi = i;
            out_.push(mk(move || Self::_island(bi, drift)));
        }
        out_
    }

    /// Block() -> Block(0, 0, 0, 0) (C# defaults).
    fn _island(band: i64, drift: i64) -> Hz {
        let mut b = Block::new(0, 0, 0, 0);
        b.band = band;
        b.drift = drift;
        b.into()
    }

    fn _gen_isles(sim: &mut GameSim, p: &VariantParams, factories: &[Factory]) {
        let made = p.add_all(sim, factories);
        if !p.fallback || !p.arriving {
            return;
        }
        let reach = VariantCheck::HOLD_STEPS * SimConfig::SPEED_X + 2 * SimConfig::BIRD_RADIUS;
        let (top, bottom) = (p.hold_top(sim), p.hold_bottom(sim));
        let (wl, wr, vx) = (sim.room.wall_left(), sim.room.wall_right(), sim.state.vx);
        for i in made {
            if let Hz::Block(b) = &mut sim.room.hazards[i] {
                let x0 = b.x0 - b.drift;
                let x1 = b.x1 + b.drift;
                let near = if vx > 0 { x0 < wl + reach } else { x1 > wr - reach };
                if near && b.y1 > top && b.y0 < bottom {
                    b.base.alive = false;
                }
            }
        }
    }

    fn _big_rock() -> Hz {
        let mut b = Block::new(0, 0, 0, 0);
        b.band = 0;
        b.big = true;
        b.into()
    }

    fn _twin(lane: i64) -> Hz {
        Bouncer::new(Bouncer::TWIN_RADIUS, lane).into()
    }

    fn _coin(x: i64, y: i64, appear_at: i64) -> Hz {
        CoinPickup::new(x, y, appear_at).into()
    }

    fn _orbit_coin(phase: i64) -> Hz {
        OrbitCoin::new(Self::GARDEN_CX, Self::GARDEN_CY, Self::ORBIT_RADIUS, phase).into()
    }

    /// C# passes one shared List to every SpikeBall; SpikeBall only reads it,
    /// so a copy per hazard behaves the same.
    fn _decoy(spots: Vec<i64>) -> Hz {
        SpikeBall::new(spots).into()
    }
}
