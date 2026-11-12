//! Port of sim/rooms/catalog_combo.gd (Sim/Rooms/CatalogCombo.cs). Order is part of the rules.
use crate::prelude::*;

pub struct CatalogCombo;

impl CatalogCombo {
    pub const SUB: i64 = SimConfig::SUB;
    pub const COMBO_WARN: i64 = SimConfig::ARRIVAL_BLIND;

    pub fn defs() -> Vec<RoomDef> {
        const SUB: i64 = CatalogCombo::SUB;
        let mut out_ = Vec::new();

        let mut double_ = RoomDef::new("double", "late", 120);
        double_.weight = 6;
        double_.max_spikes = 6;
        double_.variants = vec![
            RoomVariant::new("pinwheel_piston").with(vec![
                // Rotor() -> Rotor(80 * SUB, 8 * SUB, 16 * SUB) (C# defaults).
                mk(|| Rotor::new(80 * SUB, 8 * SUB, 16 * SUB).into()),
                mk(|| Self::_piston(0, 0, 30)),
            ]),
            RoomVariant::new("swing_rain")
                .with(vec![
                    // Pendulum() -> C# defaults PIVOT_X, LENGTH, RADIUS, AMPLITUDE, PERIOD.
                    mk(|| {
                        Pendulum::new(
                            Pendulum::PIVOT_X,
                            Pendulum::LENGTH,
                            Pendulum::RADIUS,
                            Pendulum::AMPLITUDE,
                            Pendulum::PERIOD,
                        )
                        .into()
                    }),
                    mk(|| Self::_drop(60)),
                ])
                .skipping(vec![318 * SUB, 368 * SUB]),
            RoomVariant::new("bramble_beams").with(vec![
                mk(|| Bouncer::new(Bouncer::RADIUS, Lane::ANY).into()),
                mk(|| Beam::new(3, Self::COMBO_WARN, true).into()),
            ]),
            RoomVariant::new("saw_rain").with(vec![
                mk(|| SawRing::new().into()),
                mk(|| Self::_drop(60)),
            ]),
        ];
        out_.push(double_);

        out_
    }

    fn _piston(side: i64, half: i64, delay: i64) -> Hz {
        Piston::new(side, half, delay, Self::COMBO_WARN, true).into()
    }

    fn _drop(delay: i64) -> Hz {
        // C# defaults for the rest: p_radius = Drop.RADIUS, p_style = Style.PLAIN, p_column = -1.
        Drop::new(delay, 10 * Self::SUB, 25, Self::COMBO_WARN, Drop::RADIUS, Style::PLAIN, -1).into()
    }
}

use crate::hazards::bouncer::Lane;
use crate::hazards::drop::Style;
