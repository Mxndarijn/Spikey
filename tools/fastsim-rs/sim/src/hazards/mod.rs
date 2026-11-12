//! The hazards (sim/hazards/*.gd, Sim/Hazards/*.cs), one file each, and `Hz`,
//! the enum the room keeps them in.
use crate::game_sim::GameSim;
use crate::rooms::hazard::{Base, Hazard};
use crate::sim_rng::SimRng;

pub mod beam;
pub mod belt;
pub mod block;
pub mod boss;
pub mod boss_crusher;
pub mod boss_saw;
pub mod boss_watcher;
pub mod bouncer;
pub mod bubble;
pub mod bumper;
pub mod coin_pickup;
pub mod crate_drop;
pub mod crawler;
pub mod curious_bouncer;
pub mod dart;
pub mod drop;
pub mod echo;
pub mod edge_pad;
pub mod exit_key;
pub mod firework;
pub mod gate;
pub mod heavy_bouncer;
pub mod keepy_ball;
pub mod lava;
pub mod mover;
pub mod orbit_coin;
pub mod orchard_spawner;
pub mod pad_coin;
pub mod pendulum;
pub mod piston;
pub mod revving_bouncer;
pub mod rotor;
pub mod saw_ring;
pub mod spike_ball;
pub mod splitting_bouncer;
pub mod stalactite;
pub mod stalker;
pub mod updraft;
pub mod wind;

pub use beam::Beam;
pub use belt::Belt;
pub use block::Block;
pub use boss::Boss;
pub use boss_crusher::BossCrusher;
pub use boss_saw::BossSaw;
pub use boss_watcher::BossWatcher;
pub use bouncer::Bouncer;
pub use bubble::Bubble;
pub use bumper::Bumper;
pub use coin_pickup::CoinPickup;
pub use crate_drop::CrateDrop;
pub use crawler::Crawler;
pub use curious_bouncer::CuriousBouncer;
pub use dart::Dart;
pub use drop::Drop;
pub use echo::Echo;
pub use edge_pad::EdgePad;
pub use exit_key::ExitKey;
pub use firework::Firework;
pub use gate::Gate;
pub use heavy_bouncer::HeavyBouncer;
pub use keepy_ball::KeepyBall;
pub use lava::Lava;
pub use mover::Mover;
pub use orbit_coin::OrbitCoin;
pub use orchard_spawner::OrchardSpawner;
pub use pad_coin::PadCoin;
pub use pendulum::Pendulum;
pub use piston::Piston;
pub use revving_bouncer::RevvingBouncer;
pub use rotor::Rotor;
pub use saw_ring::SawRing;
pub use spike_ball::SpikeBall;
pub use splitting_bouncer::SplittingBouncer;
pub use stalactite::Stalactite;
pub use stalker::Stalker;
pub use updraft::Updraft;
pub use wind::Wind;

#[cold]
#[inline(never)]
fn taken() -> ! {
    panic!("a hazard was used while its own method runs (Hz::Taken); see rooms/hazard.rs")
}

macro_rules! hazard_enum {
    ($($v:ident),* $(,)?) => {
        /// Every hazard type by value. `Taken` fills the slot of a hazard whose
        /// method is running (GameSim::with_hazard).
        #[derive(Clone)]
        pub enum Hz {
            Taken,
            $($v($v),)*
        }

        $(impl From<$v> for Hz {
            #[inline]
            fn from(h: $v) -> Hz { Hz::$v(h) }
        })*

        impl Hz {
            #[inline]
            pub fn base(&self) -> &Base {
                match self { $(Hz::$v(h) => h.base(),)* Hz::Taken => taken() }
            }
            #[inline]
            pub fn base_mut(&mut self) -> &mut Base {
                match self { $(Hz::$v(h) => h.base_mut(),)* Hz::Taken => taken() }
            }
            #[inline]
            pub fn is_taken(&self) -> bool { matches!(self, Hz::Taken) }
            #[inline]
            pub fn alive(&self) -> bool { self.base().alive }
            #[inline]
            pub fn kind(&self) -> &'static str { self.base().kind }
            pub fn setup(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
                match self { $(Hz::$v(h) => h.setup(sim, rng),)* Hz::Taken => taken() }
            }
            #[inline]
            pub fn step(&mut self, sim: &mut GameSim) {
                match self { $(Hz::$v(h) => h.step(sim),)* Hz::Taken => taken() }
            }
            #[inline]
            pub fn kills(&self, sim: &GameSim) -> bool {
                match self { $(Hz::$v(h) => h.kills(sim),)* Hz::Taken => taken() }
            }
            #[inline]
            pub fn touch(&mut self, sim: &mut GameSim) {
                match self { $(Hz::$v(h) => h.touch(sim),)* Hz::Taken => taken() }
            }
            pub fn adjust_wall(&mut self, sim: &mut GameSim, side: i64, mask: i64) -> i64 {
                match self { $(Hz::$v(h) => h.adjust_wall(sim, side, mask),)* Hz::Taken => taken() }
            }
            pub fn on_bounce(&mut self, sim: &mut GameSim, rng: &mut SimRng) {
                match self { $(Hz::$v(h) => h.on_bounce(sim, rng),)* Hz::Taken => taken() }
            }
            pub fn on_flap(&mut self, sim: &mut GameSim) {
                match self { $(Hz::$v(h) => h.on_flap(sim),)* Hz::Taken => taken() }
            }
            pub fn blocks_exit(&self, sim: &GameSim, side: i64, y: i64) -> bool {
                match self { $(Hz::$v(h) => h.blocks_exit(sim, side, y),)* Hz::Taken => taken() }
            }
            #[inline]
            pub fn guards_edge(&self, sim: &GameSim, top: bool) -> bool {
                match self { $(Hz::$v(h) => h.guards_edge(sim, top),)* Hz::Taken => taken() }
            }
            pub fn band_top(&self) -> i64 {
                match self { $(Hz::$v(h) => h.band_top(),)* Hz::Taken => taken() }
            }
            pub fn band_bottom(&self) -> i64 {
                match self { $(Hz::$v(h) => h.band_bottom(),)* Hz::Taken => taken() }
            }
            pub fn near_row(&self, sim: &GameSim, y: i64, half: i64, from: i64, to: i64) -> bool {
                match self { $(Hz::$v(h) => h.near_row(sim, y, half, from, to),)* Hz::Taken => taken() }
            }
            #[inline]
            pub fn wall_shift(&self, sim: &GameSim, side: i64) -> i64 {
                match self { $(Hz::$v(h) => h.wall_shift(sim, side),)* Hz::Taken => taken() }
            }
            #[inline]
            pub fn locks_exit(&self, sim: &GameSim) -> bool {
                match self { $(Hz::$v(h) => h.locks_exit(sim),)* Hz::Taken => taken() }
            }
            pub fn checksum(&self, h0: i64) -> i64 {
                match self { $(Hz::$v(h) => h.checksum(h0),)* Hz::Taken => taken() }
            }
        }
    };
}

hazard_enum!(
    Beam,
    Belt,
    Block,
    BossCrusher,
    BossSaw,
    BossWatcher,
    Bouncer,
    Bubble,
    Bumper,
    CoinPickup,
    CrateDrop,
    Crawler,
    CuriousBouncer,
    Dart,
    Drop,
    Echo,
    EdgePad,
    ExitKey,
    Firework,
    Gate,
    HeavyBouncer,
    KeepyBall,
    Lava,
    Mover,
    OrbitCoin,
    OrchardSpawner,
    PadCoin,
    Pendulum,
    Piston,
    RevvingBouncer,
    Rotor,
    SawRing,
    SpikeBall,
    SplittingBouncer,
    Stalactite,
    Stalker,
    Updraft,
    Wind,
);

impl Hz {
    /// C# `h is CoinPickup c` (CoinPickup and its subclasses).
    pub fn as_coin_pickup(&self) -> Option<&CoinPickup> {
        match self {
            Hz::CoinPickup(c) => Some(c),
            Hz::OrbitCoin(o) => Some(o.coin()),
            Hz::PadCoin(p) => Some(p.coin()),
            _ => None,
        }
    }

    pub fn as_coin_pickup_mut(&mut self) -> Option<&mut CoinPickup> {
        match self {
            Hz::CoinPickup(c) => Some(c),
            Hz::OrbitCoin(o) => Some(o.coin_mut()),
            Hz::PadCoin(p) => Some(p.coin_mut()),
            _ => None,
        }
    }

    /// C# `h is Boss b` (BossCrusher, BossSaw, BossWatcher).
    pub fn as_boss(&self) -> Option<&Boss> {
        match self {
            Hz::BossCrusher(b) => Some(b.boss()),
            Hz::BossSaw(b) => Some(b.boss()),
            Hz::BossWatcher(b) => Some(b.boss()),
            _ => None,
        }
    }

    pub fn as_boss_mut(&mut self) -> Option<&mut Boss> {
        match self {
            Hz::BossCrusher(b) => Some(b.boss_mut()),
            Hz::BossSaw(b) => Some(b.boss_mut()),
            Hz::BossWatcher(b) => Some(b.boss_mut()),
            _ => None,
        }
    }

    /// C# `h is Bouncer b` (Bouncer and its subclasses).
    pub fn as_bouncer(&self) -> Option<&Bouncer> {
        match self {
            Hz::Bouncer(b) => Some(b),
            Hz::CuriousBouncer(h) => Some(&h.b),
            Hz::HeavyBouncer(h) => Some(&h.b),
            Hz::RevvingBouncer(h) => Some(&h.b),
            Hz::SplittingBouncer(h) => Some(&h.b),
            _ => None,
        }
    }
}

/// Which hazard types override a mutating method (the rest keep the trait's
/// no-op), so GameSim can skip taking them out of the room for nothing. Keep in
/// step with the hazard files: a missing entry silently skips that method (the
/// parity check catches it); an extra entry only costs time.
impl Hz {
    #[inline]
    pub fn has_step(&self) -> bool {
        !matches!(self, Hz::SpikeBall(_) | Hz::Wind(_))
    }
    #[inline]
    pub fn has_touch(&self) -> bool {
        matches!(
            self,
            Hz::Bubble(_)
                | Hz::Bumper(_)
                | Hz::CoinPickup(_)
                | Hz::CrateDrop(_)
                | Hz::ExitKey(_)
                | Hz::KeepyBall(_)
                | Hz::Lava(_)
                | Hz::OrbitCoin(_)
                | Hz::OrchardSpawner(_)
                | Hz::PadCoin(_)
                | Hz::Updraft(_)
                | Hz::Wind(_)
        )
    }
    #[inline]
    pub fn has_on_flap(&self) -> bool {
        matches!(self, Hz::Bubble(_))
    }
    #[inline]
    pub fn has_on_bounce(&self) -> bool {
        matches!(self, Hz::Belt(_) | Hz::Bubble(_) | Hz::ExitKey(_) | Hz::Lava(_) | Hz::Piston(_) | Hz::Stalactite(_))
    }
    #[inline]
    pub fn has_adjust_wall(&self) -> bool {
        matches!(
            self,
            Hz::BossCrusher(_) | Hz::BossSaw(_) | Hz::BossWatcher(_) | Hz::Crawler(_) | Hz::ExitKey(_) | Hz::Gate(_) | Hz::Lava(_)
        )
    }
}

impl Hz {
    /// Whether this type's code reads `sim.room.hazards` (other hazards). The
    /// others run with the whole list lent out instead of being taken out of it
    /// (GameSim::with_hazard). Every type that names `room.hazards` must be here.
    #[inline]
    pub fn needs_room(&self) -> bool {
        matches!(
            self,
            Hz::Taken
                | Hz::Beam(_)
                | Hz::Block(_)
                | Hz::Bubble(_)
                | Hz::Bumper(_)
                | Hz::CoinPickup(_)
                | Hz::Crawler(_)
                | Hz::Gate(_)
                | Hz::PadCoin(_)
                | Hz::Piston(_)
                | Hz::SpikeBall(_)
                | Hz::Stalactite(_)
        )
    }
}
