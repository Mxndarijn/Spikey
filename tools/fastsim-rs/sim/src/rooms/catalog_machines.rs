//! Port of sim/rooms/catalog_machines.gd (Sim/Rooms/CatalogMachines.cs). Order is part of the rules.
use crate::prelude::*;

pub struct CatalogMachines;

impl CatalogMachines {
    pub const SUB: i64 = SimConfig::SUB;

    pub const SLAM_REACH: i64 = 150 * Self::SUB;
    pub const SLAM_GLOW: i64 = 60;
    pub const LADDER_Y: [i64; 3] = [170 * Self::SUB, 300 * Self::SUB, 430 * Self::SUB];
    pub const LADDER_REACH: i64 = 140 * Self::SUB;
    pub const LADDER_BEAT: i64 = 36;
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
    pub const ALT_ARRIVAL_LO: i64 = 270 * Self::SUB;
    pub const ALT_ARRIVAL_HI: i64 = 430 * Self::SUB;
    pub const SHORT_GAP: i64 = 300 * Self::SUB;
    pub const SHORT_Y: i64 = 320 * Self::SUB;
    pub const SHORT_HALF_W: i64 = 18 * Self::SUB;
    pub const SHORT_ARRIVAL_LO: i64 = 256 * Self::SUB;
    pub const SHORT_ARRIVAL_HI: i64 = 448 * Self::SUB;

    pub fn defs() -> Vec<RoomDef> {
        const SUB: i64 = CatalogMachines::SUB;
        let mut out_ = Vec::new();

        let mut piston = RoomDef::new("piston", "mid", 30);
        piston.max_spikes = 6;
        piston.variants = vec![
            RoomVariant::new("classic").with(vec![
                mk(|| Self::_piston(0, 0, 30)),
                mk(|| Self::_piston(1, 1, 30 + Piston::PERIOD / 2)),
            ]),
            RoomVariant::new("double-slam")
                .with(vec![mk(|| Self::_slam(0)), mk(|| Self::_slam(1))]),
            RoomVariant::new("ladder").with(vec![
                mk(|| Self::_rung(0)),
                mk(|| Self::_rung(1)),
                mk(|| Self::_rung(2)),
            ]),
        ];
        out_.push(piston);

        let mut court = RoomDef::new("court", "mid", 40);
        court.hazards.push(mk(|| Self::_pad(true, 300)));
        court.hazards.push(mk(|| Self::_pad(false, 240)));
        court.variants = vec![
            RoomVariant::new("classic"),
            RoomVariant::new("goal-pad").with(vec![mk(|| PadCoin::new(false).into())]),
        ];
        out_.push(court);

        let mut crates = RoomDef::new("crates", "mid", 60);
        crates.max_spikes = 6;
        crates.variants = Self::crate_variants(false);
        out_.push(crates);

        let mut beams = RoomDef::new("beams", "mid", 50);
        beams.max_spikes = 5;
        // Beam() -> Beam(ROWS, WARN_TICKS, false) (C# defaults).
        beams.hazards.push(mk(|| Beam::new(Beam::ROWS, Beam::WARN_TICKS, false).into()));
        out_.push(beams);

        let mut stalac = RoomDef::new("stalac", "mid", 30);
        stalac.max_spikes = 4;
        stalac.arrival_skip = vec![0, RoomDef::CEILING_ARRIVAL];
        stalac.variants = vec![
            RoomVariant::new("classic").with(vec![
                mk(|| Self::_stalactite(130 * SUB, false)),
                mk(|| Self::_stalactite(230 * SUB, true)),
            ]),
            RoomVariant::new("floor").with(vec![
                mk(|| Self::_fang(130, false, false)),
                mk(|| Self::_fang(230, true, false)),
            ]),
            RoomVariant::new("ceiling-only").with(vec![
                mk(|| Self::_fang(130, false, true)),
                mk(|| Self::_fang(230, true, true)),
            ]),
            RoomVariant::new("alternating")
                .with(vec![
                    mk(|| Self::_finger(0)),
                    mk(|| Self::_finger(1)),
                    mk(|| Self::_finger(2)),
                ])
                .skipping(vec![0, Self::ALT_ARRIVAL_LO, Self::ALT_ARRIVAL_HI, SimConfig::WORLD_H]),
            RoomVariant::new("short-fangs")
                .with(vec![
                    mk(|| Self::_short(0)),
                    mk(|| Self::_short(1)),
                    mk(|| Self::_short(2)),
                ])
                .skipping(vec![
                    0,
                    Self::SHORT_ARRIVAL_LO,
                    Self::SHORT_ARRIVAL_HI,
                    SimConfig::WORLD_H,
                ]),
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
        vec![
            RoomVariant::new("classic").with(vec![mk(move || Self::_crates(gifts, false, false))]),
            RoomVariant::new("wide").with(vec![mk(move || Self::_crates(gifts, true, false))]),
            RoomVariant::new("pairs").with(vec![mk(move || Self::_crates(gifts, false, true))]),
        ]
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

    /// Piston(side, half, delay): C# defaults p_glow = GLOW_TICKS, p_share_band = false.
    fn _piston(side: i64, half: i64, delay: i64) -> Hz {
        Piston::new(side, half, delay, Piston::GLOW_TICKS, false).into()
    }

    fn _hunter(slot: i64, home: i64) -> Hz {
        Dart::new(false, slot, home).into()
    }

    fn _slam(side: i64) -> Hz {
        let mut p = Piston::new(side, Piston::HALF_ALL, 30, Self::SLAM_GLOW, false);
        p.reach = Self::SLAM_REACH;
        p.follows = side == 1;
        p.into()
    }

    fn _rung(i: i64) -> Hz {
        let mut p = Piston::new(1, 0, 30 + i * Self::LADDER_BEAT, Piston::GLOW_TICKS, false);
        p.reach = Self::LADDER_REACH;
        p.fixed_y = Self::LADDER_Y[i as usize];
        p.into()
    }

    fn _pad(top: bool, period: i64) -> Hz {
        EdgePad::new(top, period).into()
    }

    fn _stalactite(x: i64, follows: bool) -> Hz {
        Stalactite::new(x, follows).into()
    }

    fn _fang(x_px: i64, follows: bool, ceiling: bool) -> Hz {
        let mut s = Stalactite::new(x_px * Self::SUB, follows);
        s.top = ceiling;
        s.bottom = !ceiling;
        s.gap = if ceiling { Stalactite::GAP } else { Self::FANG_GAP };
        s.into()
    }

    fn _finger(i: i64) -> Hz {
        let mut s = Stalactite::new(Self::TRIO_X[i as usize] * Self::SUB, i > 0);
        s.top = i % 2 == 0;
        s.bottom = i % 2 == 1;
        s.gap = Self::ALT_GAP;
        s.fixed_lo = Self::ALT_LO;
        s.fixed_hi = Self::ALT_HI;
        s.into()
    }

    fn _short(i: i64) -> Hz {
        let mut s = Stalactite::new(Self::TRIO_X[i as usize] * Self::SUB, i > 0);
        s.gap = Self::SHORT_GAP;
        s.half_w = Self::SHORT_HALF_W;
        s.fixed_lo = Self::SHORT_Y;
        s.fixed_hi = Self::SHORT_Y;
        s.into()
    }
}
