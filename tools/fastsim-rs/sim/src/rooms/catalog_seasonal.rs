//! Port of sim/rooms/catalog_seasonal.gd (Sim/Rooms/CatalogSeasonal.cs). Order is part of the rules.
use crate::hazards::bouncer::Lane;
use crate::hazards::drop::Style as DropStyle;
use crate::hazards::firework::Style;
use crate::prelude::*;
use crate::rooms::catalog_machines::CatalogMachines;
use crate::rooms::catalog_motion::CatalogMotion;

pub struct CatalogSeasonal;

impl CatalogSeasonal {
    pub const SUB: i64 = SimConfig::SUB;
    pub const WEIGHT: i64 = 12;
    pub const ROW_Y: i64 = 400;
    pub const ROW_W: i64 = 60;
    pub const ROW_H: i64 = 34;
    pub const ROW_PERIOD: i64 = 240;
    pub const ROW_SOLID: i64 = 160;
    pub const ROW_SKIP: [i64; 2] = [380 * SimConfig::SUB, 516 * SimConfig::SUB];
    pub const FLICKER_PERIOD: i64 = 150;
    pub const FLICKER_SOLID: i64 = 60;
    pub const FLICKER_ROW_STEP: i64 = 50;
    pub const FLICKER_COL_STEP: i64 = 20;

    pub fn defs() -> Vec<RoomDef> {
        const SUB: i64 = CatalogSeasonal::SUB;
        let mut out_ = Vec::new();

        // Halloween
        let mut pumpkin = Self::_room("pumpkin", Seasons::HALLOWEEN, 40);
        pumpkin.variants = vec![
            RoomVariant::new("classic")
                .with(vec![mk(|| Bouncer::new(Bouncer::RADIUS, Lane::ANY).into())]),
            RoomVariant::new("twin")
                .with(vec![mk(|| Self::_twin(Lane::UPPER)), mk(|| Self::_twin(Lane::LOWER))]),
            RoomVariant::new("splitting").with(vec![mk(|| SplittingBouncer::new().into())]),
        ];
        out_.push(pumpkin);

        let mut ghosts = Self::_room("ghostdoors", Seasons::HALLOWEEN, 30);
        ghosts.max_spikes = 6;
        let mut grid: Vec<Factory> = Vec::new();
        let mut flicker: Vec<Factory> = Vec::new();
        for i in 0..6i64 {
            let gi = i;
            grid.push(mk(move || Self::_ghost_door(gi).into()));
            flicker.push(mk(move || Self::_flicker_door(gi)));
        }
        let mut row: Vec<Factory> = Vec::new();
        for i in 0..3i64 {
            let ri = i;
            row.push(mk(move || Self::_row_door(ri)));
        }
        ghosts.variants = vec![
            RoomVariant::new("classic").with(grid),
            RoomVariant::new("row").with(row).skipping(Self::ROW_SKIP.to_vec()),
            RoomVariant::new("flicker").with(flicker),
        ];
        out_.push(ghosts);

        let mut bats = Self::_room("bats", Seasons::HALLOWEEN, 40);
        for shape in ["classic", "wide", "pair"] {
            bats.variants
                .push(RoomVariant::new(shape).with(vec![mk(move || Self::_bats(shape))]));
        }
        out_.push(bats);

        // Winter
        // Drop(delay, speed, gap): C# defaults p_warn = WARN, p_radius = RADIUS,
        // p_style = Style.PLAIN, p_column = -1.
        let mut icicles = Self::_room("icicle", Seasons::WINTER, 50);
        icicles.hazards.push(mk(|| {
            Drop::new(30, 10 * SUB, 25, Drop::WARN, Drop::RADIUS, DropStyle::PLAIN, -1).into()
        }));
        icicles.hazards.push(mk(|| {
            Drop::new(70, 10 * SUB, 25, Drop::WARN, Drop::RADIUS, DropStyle::PLAIN, -1).into()
        }));
        out_.push(icicles);

        let mut gifts = Self::_room("gifts", Seasons::WINTER, 60);
        gifts.arrival_skip = vec![0, RoomDef::CEILING_ARRIVAL];
        gifts.variants = CatalogMachines::crate_variants(true);
        out_.push(gifts);

        // Valentine's
        // Bumper() -> Bumper(false) (C# default p_follows = false).
        let mut hearts = Self::_room("hearts", Seasons::VALENTINE, 10);
        hearts.variants = vec![
            RoomVariant::new("classic").with(vec![
                mk(|| Bumper::new(false).into()),
                mk(|| Bumper::new(true).into()),
            ]),
            RoomVariant::new("one-big").with(vec![mk(|| Bumper::new(false).big().into())]),
            RoomVariant::new("orbit").with(vec![
                mk(|| Bumper::new(false).orbit().into()),
                mk(|| Bumper::new(true).orbit().into()),
            ]),
        ];
        out_.push(hearts);

        let mut cupid = Self::_room("cupid", Seasons::VALENTINE, 40);
        for shape in ["classic", "double", "slow-volley"] {
            cupid.variants.push(RoomVariant::new(shape).with(vec![
                mk(move || Self::_cupid(shape, 0)),
                mk(move || Self::_cupid(shape, 1)),
            ]));
        }
        out_.push(cupid);

        // Spring
        let mut eggs = Self::_room("eggs", Seasons::SPRING, 20);
        eggs.max_spikes = 6;
        eggs.variants = vec![
            RoomVariant::new("classic").with(Self::_egg_isles(0, false)),
            RoomVariant::new("drifting").with(Self::_egg_isles(Block::DRIFT, false)),
            RoomVariant::new("golden").with(Self::_egg_isles(0, true)),
        ];
        out_.push(eggs);

        let mut bees = Self::_room("bees", Seasons::SPRING, 30);
        bees.hazards.push(mk(|| Mover::new("wave", 4).into()));
        bees.arrival_skip = vec![295 * SUB, 405 * SUB];
        out_.push(bees);

        // Summer
        let mut beach = Self::_room("beachball", Seasons::SUMMER, 40);
        beach.group = "bonus";
        beach.max_spikes = 3;
        beach.variants = vec![
            RoomVariant::new("classic").with(vec![mk(|| KeepyBall::new().into())]),
            RoomVariant::new("two").with(vec![
                mk(|| KeepyBall::new().dropping(0).into()),
                mk(|| KeepyBall::new().dropping(KeepyBall::SECOND_DROP).into()),
            ]),
            RoomVariant::new("heavy").with(vec![mk(|| KeepyBall::new().heavy().into())]),
        ];
        out_.push(beach);

        let mut crabs = Self::_room("crabs", Seasons::SUMMER, 30);
        crabs.arrival_skip = vec![0, RoomDef::CEILING_ARRIVAL];
        crabs.variants = CatalogMotion::crawl_variants();
        out_.push(crabs);

        // New Year
        let mut fireworks = Self::_room("fireworks", Seasons::NEW_YEAR, 50);
        let styles: [(&'static str, i64); 3] =
            [("classic", Style::RING), ("double", Style::DOUBLE), ("cross", Style::CROSS)];
        for (shape, style) in styles {
            let mut rockets: Vec<Factory> = Vec::new();
            let delays: Vec<i64> =
                if style == Style::DOUBLE { vec![0, 75] } else { vec![0, 50, 100] };
            for delay in delays {
                let d = delay;
                let st = style;
                rockets.push(mk(move || Self::_firework(d, st)));
            }
            fireworks.variants.push(RoomVariant::new(shape).with(rockets));
        }
        out_.push(fireworks);

        let mut countdown = Self::_room("countdown", Seasons::NEW_YEAR, 20);
        countdown.group = "bonus";
        countdown.max_spikes = 2;
        for i in 0..10i64 {
            let angle = i * SimTrig::TURN / 10;
            let x = 180 * SUB + 100 * SUB * SimTrig::cos_t(angle) / SimTrig::ONE;
            let y = 320 * SUB + 130 * SUB * SimTrig::sin_t(angle) / SimTrig::ONE;
            let appear_at = i * SimConfig::TICKS_PER_SECOND;
            countdown.hazards.push(mk(move || Self::_coin(x, y, appear_at)));
        }
        out_.push(countdown);

        out_
    }

    fn _room(id: &'static str, season: i64, from: i64) -> RoomDef {
        let mut def = RoomDef::new(id, "seasonal", from);
        def.season = season;
        def.weight = Self::WEIGHT;
        def
    }

    fn _twin(lane: i64) -> Hz {
        Bouncer::new(Bouncer::TWIN_RADIUS, lane).into()
    }

    /// Returns the Block itself (C# returns Hazard and _flicker_door casts it back).
    fn _ghost_door(i: i64) -> Block {
        const SUB: i64 = CatalogSeasonal::SUB;
        let col = i % 2;
        let row = i / 2;
        let x0 = (90 + col * 120) * SUB;
        let y0 = (190 + row * 130) * SUB;
        let mut b = Block::new(x0, y0, x0 + 60 * SUB, y0 + 34 * SUB);
        b.fade_period = 240;
        b.solid_ticks = 140;
        b.phase = i * 40;
        b
    }

    fn _row_door(i: i64) -> Hz {
        const SUB: i64 = CatalogSeasonal::SUB;
        let x0 = (60 + i * 90) * SUB;
        let y0 = Self::ROW_Y * SUB;
        let mut b = Block::new(x0, y0, x0 + Self::ROW_W * SUB, y0 + Self::ROW_H * SUB);
        b.fade_period = Self::ROW_PERIOD;
        b.solid_ticks = Self::ROW_SOLID;
        b.phase = G::posmod(
            Self::ROW_SOLID - i * (Self::ROW_PERIOD - Self::ROW_SOLID),
            Self::ROW_PERIOD,
        );
        b.guards_exit = true;
        b.into()
    }

    fn _flicker_door(i: i64) -> Hz {
        let mut b = Self::_ghost_door(i);
        b.fade_period = Self::FLICKER_PERIOD;
        b.solid_ticks = Self::FLICKER_SOLID;
        b.phase = ((i / 2) * Self::FLICKER_ROW_STEP + (i % 2) * Self::FLICKER_COL_STEP)
            % Self::FLICKER_PERIOD;
        b.into()
    }

    fn _egg_isles(drift: i64, golden: bool) -> Vec<Factory> {
        let mut out_: Vec<Factory> = Vec::new();
        for band in 0..4i64 {
            let b = band;
            let g = golden && band == 3;
            out_.push(mk(move || Self::_island(b, drift)));
            out_.push(mk(move || Self::_egg(b, g)));
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

    /// An egg next to the island of the same band (CoinPickup.beside_band: it
    /// finds the island, built and placed just before it, in setup()).
    /// CoinPickup() -> CoinPickup(0, 0, 0) (C# defaults).
    fn _egg(band: i64, golden: bool) -> Hz {
        let mut egg = CoinPickup::new(0, 0, 0);
        egg.beside_band = band;
        if golden {
            egg.value = CoinPickup::GOLD_VALUE;
            egg.behind = true;
        }
        egg.into()
    }

    fn _coin(x: i64, y: i64, appear_at: i64) -> Hz {
        CoinPickup::new(x, y, appear_at).into()
    }

    fn _firework(delay: i64, style: i64) -> Hz {
        Firework::new(delay, style).into()
    }

    fn _bats(shape: &str) -> Hz {
        const SUB: i64 = CatalogSeasonal::SUB;
        match shape {
            "wide" => {
                let mut wide = Mover::new("figure8", 3);
                wide.loop_w = 104 * SUB;
                wide.loop_h = 112 * SUB;
                wide.loop_period = 380;
                return wide.into();
            }
            "pair" => {
                let mut pair = Mover::new("figure8", 2);
                pair.loop_period = 400;
                pair.chase = true;
                return pair.into();
            }
            _ => {}
        }
        Mover::new("figure8", 3).into()
    }

    /// Dart(true, slot): C# default p_home = -1.
    fn _cupid(shape: &str, slot: i64) -> Hz {
        const SUB: i64 = CatalogSeasonal::SUB;
        let mut d = Dart::new(true, slot, -1);
        match shape {
            "double" => {
                d.lane_count = 5;
                d.lane_min = 110 * SUB;
                d.lane_max = 470 * SUB;
                d.pair = true;
            }
            "slow-volley" => {
                d.lanes_speed = 3 * SUB;
                d.lanes_flash = 84;
            }
            _ => {}
        }
        d.into()
    }
}
