//! Port of sim/rooms/catalog_twists.gd (Sim/Rooms/CatalogTwists.cs). Order is part of the rules.
use crate::prelude::*;

pub struct CatalogTwists;

impl CatalogTwists {
    pub const SUB: i64 = SimConfig::SUB;

    pub fn defs() -> Vec<RoomDef> {
        const SUB: i64 = CatalogTwists::SUB;
        let mut out_ = Vec::new();

        // Wind(), Belt(), ExitKey(), Echo(): C# default p_mode = -1.
        let mut wind = RoomDef::new("crosswind", "starter", 10);
        wind.hazards.push(mk(|| Wind::new(-1).into()));
        wind.variants = vec![
            RoomVariant::new("steady"),
            RoomVariant::new("split"),
            RoomVariant::new("gusty"),
        ];
        out_.push(wind);

        let mut belt = RoomDef::new("belt", "starter", 20);
        belt.hazards.push(mk(|| Belt::new(-1).into()));
        belt.variants = vec![
            RoomVariant::new("up"),
            RoomVariant::new("counter"),
            RoomVariant::new("switchback"),
        ];
        out_.push(belt);

        let mut lock_ = RoomDef::new("lockexit", "mid", 40);
        lock_.hazards.push(mk(|| ExitKey::new(-1).into()));
        lock_.variants = vec![
            RoomVariant::new("trio").sized(1, 1, 1),
            RoomVariant::new("quad").sized(1, 1, 1),
            RoomVariant::new("chain").sized(1, 1, 1),
        ];
        out_.push(lock_);

        let mut lava = RoomDef::new("lava", "mid", 50);
        lava.max_spikes = 6;
        lava.hazards.push(mk(|| Lava::new().into()));
        lava.variants =
            vec![RoomVariant::new("lava"), RoomVariant::new("cold"), RoomVariant::new("rafts")];
        out_.push(lava);

        let mut echo = RoomDef::new("echo", "late", 80);
        echo.weight = 8;
        echo.variants = vec![
            RoomVariant::new("echo").with(vec![mk(|| Echo::new(crate::hazards::echo::Mode::ECHO).into())]),
            RoomVariant::new("mirror").generated(recipe(|sim, p| Self::_gen_mirror(sim, p)), false, 0),
        ];
        out_.push(echo);

        out_
    }

    fn _gen_mirror(sim: &mut GameSim, p: &VariantParams) {
        let e = p.add(sim, Echo::new(crate::hazards::echo::Mode::MIRROR).into());
        VariantParams::edit(sim, e, |h, sim| {
            if let Hz::Echo(e) = h {
                e.place_pivot(sim, p);
            }
        });
    }
}
