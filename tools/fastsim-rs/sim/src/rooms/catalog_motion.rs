//! Port of sim/rooms/catalog_motion.gd (Sim/Rooms/CatalogMotion.cs). Order is part of the rules.
use crate::hazards::rotor::Spin;
use crate::prelude::*;

pub struct CatalogMotion;

impl CatalogMotion {
    pub const SUB: i64 = SimConfig::SUB;
    pub const PINWHEELS: [&'static str; 6] = ["trim", "three", "twin", "rock", "lean", "breathe"];
    pub const SAW_RINGS: [&'static str; 5] = ["classic", "two-rings", "off-centre", "oval", "pair"];

    pub fn defs() -> Vec<RoomDef> {
        const SUB: i64 = CatalogMotion::SUB;
        let mut out_ = Vec::new();

        // Bumper() -> Bumper(false) (C# default p_follows = false).
        let mut cloud = RoomDef::new("cloud", "starter", 10);
        cloud.hazards.push(mk(|| Bumper::new(false).into()));
        cloud.variants = vec![
            RoomVariant::new("one"),
            RoomVariant::new("two").with(vec![mk(|| Bumper::new(true).into())]),
        ];
        out_.push(cloud);

        let mut gates = RoomDef::new("gates", "starter", 20);
        gates.max_spikes = 6;
        gates.variants = vec![
            RoomVariant::new("classic").generated(recipe(|sim, p| Self::_gen_gates(sim, p, false)), false, 0),
            RoomVariant::new("single-small").generated(recipe(|sim, p| Self::_gen_gates(sim, p, true)), false, 0),
        ];
        out_.push(gates);

        let mut crawl = RoomDef::new("crawl", "starter", 30);
        crawl.variants = Self::crawl_variants();
        out_.push(crawl);

        let mut swing = RoomDef::new("swing", "mid", 30);
        swing.variants = vec![
            RoomVariant::new("big")
                .with(vec![mk(|| Self::_big_lantern())])
                .skipping(Self::_px_range(362, 428)),
            RoomVariant::new("twin")
                .with(vec![mk(|| Self::_twin_lanterns())])
                .skipping(Self::_px_range(226, 380)),
            RoomVariant::new("chimes")
                .with(vec![
                    mk(|| Self::_chime(0)),
                    mk(|| Self::_chime(1)),
                    mk(|| Self::_chime(2)),
                ])
                .skipping(Self::_px_range(192, 324)),
            RoomVariant::new("gusty")
                .with(vec![mk(|| Self::_gusty_lantern())])
                .skipping(Self::_px_range(336, 392)),
            RoomVariant::new("winch")
                .with(vec![mk(|| Self::_winch_lantern())])
                .skipping(Self::_px_range(240, 310)),
        ];
        out_.push(swing);

        let mut stalker = RoomDef::new("stalker", "mid", 40);
        stalker.max_spikes = 6;
        stalker.hazards.push(mk(|| Stalker::new().into()));
        out_.push(stalker);

        let mut pinwheel = RoomDef::new("pinwheel", "mid", 40);
        for shape in Self::PINWHEELS {
            pinwheel
                .variants
                .push(RoomVariant::new(shape).with(vec![mk(move || Self::_pinwheel(shape))]));
        }
        out_.push(pinwheel);

        let mut sawring = RoomDef::new("sawring", "late", 80);
        sawring.weight = 8;
        sawring.max_spikes = 6;
        for shape in Self::SAW_RINGS {
            sawring
                .variants
                .push(RoomVariant::new(shape).with(vec![mk(move || Self::_saw_ring(shape))]));
        }
        out_.push(sawring);

        out_
    }

    fn _saw_ring(shape: &str) -> Hz {
        let mut ring = SawRing::new();
        match shape {
            "two-rings" => {
                ring.fixed_count = 3;
                ring.ring_min = 60 * Self::SUB;
                ring.inner_count = 2;
                ring.inner_min = 20 * Self::SUB;
                ring.inner_max = 34 * Self::SUB;
                ring.inner_saw = 13 * Self::SUB;
            }
            "off-centre" => {
                ring.fixed_count = 3;
                ring.center_x = 136 * Self::SUB;
                ring.ring_min = 28 * Self::SUB;
                ring.ring_max = 48 * Self::SUB;
            }
            "oval" => {
                ring.fixed_count = 4;
                ring.ry_num = 1;
                ring.ry_den = 2;
            }
            "pair" => {
                ring.fixed_count = 2;
                ring.period = 180;
            }
            _ => {}
        }
        ring.into()
    }

    fn _pinwheel(shape: &str) -> Hz {
        const SUB: i64 = CatalogMotion::SUB;
        match shape {
            "twin" => {
                let mut pair = Rotor::new(42 * SUB, 6 * SUB, 11 * SUB);
                pair.hubs = 2;
                pair.spread_x = 60 * SUB;
                pair.spread_y = 72 * SUB;
                pair.period = 300;
                return pair.into();
            }
            "lean" => {
                let mut side = Rotor::new(52 * SUB, 6 * SUB, 12 * SUB);
                side.lean = 52 * SUB;
                return side.into();
            }
            "breathe" => {
                let mut lung = Rotor::new(72 * SUB, 7 * SUB, 14 * SUB);
                lung.spin = Spin::BREATHE;
                lung.blade_min = 40 * SUB;
                return lung.into();
            }
            _ => {}
        }
        let mut r = Rotor::new(64 * SUB, 7 * SUB, 14 * SUB);
        if shape == "three" {
            r.blades = 3;
        } else if shape == "rock" {
            r.spin = Spin::ROCK;
        }
        r.into()
    }

    /// Gate(x, period, follows): C# default p_gap = Gate.GAP.
    fn _gate(x: i64, period: i64, follows: bool) -> Hz {
        Gate::new(x, period, follows, Gate::GAP).into()
    }

    pub fn crawl_variants() -> Vec<RoomVariant> {
        vec![
            RoomVariant::new("classic").generated(recipe(|sim, p| Self::_gen_crawl(sim, p, "classic")), false, 0),
            RoomVariant::new("swarm").generated(recipe(|sim, p| Self::_gen_crawl(sim, p, "swarm")), false, 0),
            RoomVariant::new("sprinters").generated(recipe(|sim, p| Self::_gen_crawl(sim, p, "sprinters")), false, 0),
        ]
    }

    fn _gen_crawl(sim: &mut GameSim, p: &VariantParams, shape: &str) {
        let mut made = Vec::new();
        match shape {
            "swarm" => {
                made.push(p.add(sim, Self::_swarm(0, false)));
                made.push(p.add(sim, Self::_swarm(0, true)));
                made.push(p.add(sim, Self::_swarm(1, false)));
                made.push(p.add(sim, Self::_swarm(1, true)));
            }
            "sprinters" => {
                made.push(p.add(sim, Self::_sprinter(0)));
                made.push(p.add(sim, Self::_sprinter(1)));
            }
            _ => {
                made.push(p.add(sim, Self::_crawler(0)));
                made.push(p.add(sim, Self::_crawler(1)));
            }
        }
        if !p.fallback || !p.arriving {
            return;
        }
        let away = if p.entry_y < SimConfig::WORLD_H / 2 { 1 } else { 0 };
        for i in made {
            if let Hz::Crawler(c) = &mut sim.room.hazards[i] {
                if c.lane != away {
                    c.start = G::posmod(c.start + Crawler::W + Crawler::H, Crawler::PERIMETER);
                    c._place();
                }
            }
        }
    }

    fn _gen_gates(sim: &mut GameSim, p: &VariantParams, small: bool) {
        let mut made = Vec::new();
        if small {
            made.push(p.add(sim, Self::_small_gate()));
        } else {
            made.push(p.add(sim, Self::_gate(130 * Self::SUB, 760, false)));
            made.push(p.add(sim, Self::_gate(230 * Self::SUB, 760, true)));
        }
        for i in made {
            VariantParams::edit(sim, i, |h, sim| {
                if let Hz::Gate(g) = h {
                    g.open_for_arrival(sim, p);
                }
            });
        }
    }

    fn _small_gate() -> Hz {
        Gate::new(180 * Self::SUB, 760, false, Gate::SMALL_GAP).into()
    }

    fn _crawler(lane: i64) -> Hz {
        Crawler::new(lane).into()
    }

    fn _swarm(lane: i64, trails: bool) -> Hz {
        if trails {
            Crawler::new(lane).trailing().into()
        } else {
            Crawler::new(lane).swarm().into()
        }
    }

    fn _sprinter(lane: i64) -> Hz {
        Crawler::new(lane).sprinter().into()
    }

    fn _big_lantern() -> Hz {
        const SUB: i64 = CatalogMotion::SUB;
        Pendulum::new(180 * SUB, 330 * SUB, 28 * SUB, 56, 210).into()
    }

    fn _twin_lanterns() -> Hz {
        const SUB: i64 = CatalogMotion::SUB;
        Pendulum::new(130 * SUB, 200 * SUB, 20 * SUB, 45, 180).with_twin(218 * SUB, 290 * SUB).into()
    }

    fn _chime(i: i64) -> Hz {
        const SUB: i64 = CatalogMotion::SUB;
        let xs: [i64; 3] = [95, 180, 265];
        let lengths: [i64; 3] = [150, 240, 150];
        let periods: [i64; 3] = [150, 180, 210];
        let i = i as usize;
        Pendulum::new(xs[i] * SUB, lengths[i] * SUB, 15 * SUB, 40, periods[i]).into()
    }

    fn _gusty_lantern() -> Hz {
        const SUB: i64 = CatalogMotion::SUB;
        Pendulum::new(180 * SUB, 300 * SUB, 24 * SUB, 41, 180).gusting(18, 600).into()
    }

    fn _winch_lantern() -> Hz {
        const SUB: i64 = CatalogMotion::SUB;
        Pendulum::new(180 * SUB, 265 * SUB, 24 * SUB, 50, 180).winding(65 * SUB, 420).into()
    }

    fn _px_range(from_px: i64, to_px: i64) -> Vec<i64> {
        vec![from_px * Self::SUB, to_px * Self::SUB]
    }
}
