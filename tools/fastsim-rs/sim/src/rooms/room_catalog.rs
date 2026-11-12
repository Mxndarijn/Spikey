//! Port of sim/rooms/room_catalog.gd (Sim/Rooms/RoomCatalog.cs).
use std::sync::OnceLock;

use crate::rooms::room_def::RoomDef;
use crate::rooms::seasons::Seasons;
use crate::rooms::{
    catalog_boss::CatalogBoss, catalog_core::CatalogCore,
    catalog_machines::CatalogMachines, catalog_motion::CatalogMotion, catalog_seasonal::CatalogSeasonal,
    catalog_sky::CatalogSky, catalog_twists::CatalogTwists,
};
use crate::sim_config::SimConfig;
use crate::sim_rng::SimRng;

pub struct RoomCatalog;

static ALL: OnceLock<Vec<RoomDef>> = OnceLock::new();
static BOSSES: OnceLock<Vec<i64>> = OnceLock::new();
static FIRST: OnceLock<i64> = OnceLock::new();

impl RoomCatalog {
    pub fn bosses() -> &'static Vec<i64> {
        BOSSES.get_or_init(|| {
            let list = Self::all();
            let mut out_ = Vec::new();
            for i in 0..list.len() {
                if list[i].boss {
                    out_.push(i as i64);
                }
            }
            out_
        })
    }

    pub fn pick_boss(rng: &mut SimRng, met: i64) -> i64 {
        let list = Self::bosses();
        let mut open = Vec::new();
        for i in 0..list.len() as i64 {
            if ((met >> i) & 1) == 0 {
                open.push(i);
            }
        }
        if open.is_empty() {
            for i in 0..list.len() as i64 {
                open.push(i);
            }
        }
        list[open[rng.next_below(open.len() as i64) as usize] as usize]
    }

    pub fn boss_bit(index: i64) -> i64 {
        match Self::bosses().iter().position(|&b| b == index) {
            Some(i) => 1i64 << i,
            None => 0,
        }
    }

    pub fn all() -> &'static Vec<RoomDef> {
        ALL.get_or_init(|| {
            let mut list = Vec::new();
            list.extend(CatalogCore::defs());
            list.extend(CatalogMotion::defs());
            list.extend(CatalogMachines::defs());
            list.extend(CatalogSky::defs());
            list.extend(CatalogSeasonal::defs());
            list.extend(CatalogTwists::defs());
            list.extend(CatalogBoss::defs());
            list
        })
    }

    pub fn first_index() -> i64 {
        *FIRST.get_or_init(|| Self::index_of("open"))
    }

    pub fn index_of(id: &str) -> i64 {
        let list = Self::all();
        for i in 0..list.len() {
            if list[i].id == id {
                return i as i64;
            }
        }
        -1
    }

    pub fn find(id: &str) -> Option<&'static RoomDef> {
        let i = Self::index_of(id);
        if i >= 0 { Some(&Self::all()[i as usize]) } else { None }
    }

    pub fn allowed(def: &RoomDef, score: i64, season: i64) -> bool {
        if def.from_score > score {
            return false;
        }
        def.season == Seasons::NONE || def.season == season
    }

    /// GDScript default: arrival_y = SimConfig.WORLD_H.
    pub fn pick_next(rng: &mut SimRng, current: i64, score: i64, season: i64, arrival_y: i64) -> i64 {
        let list = Self::all();
        let start = Self::first_index();
        let mut weights = [0i64; 128];
        assert!(list.len() <= weights.len());
        let mut total = 0;
        for i in 0..list.len() {
            let mut w = 0;
            let fits = list[i].fits_arrival(arrival_y);
            let ii = i as i64;
            if ii != current && ii != start && fits && !list[i].boss && Self::allowed(&list[i], score, season) {
                w = list[i].weight;
            }
            weights[i] = w;
            total += w;
        }
        if total == 0 {
            return current;
        }
        let mut r = rng.next_below(total);
        for i in 0..list.len() {
            r -= weights[i];
            if r < 0 && weights[i] > 0 {
                return i as i64;
            }
        }
        current
    }

    pub const DEFAULT_ARRIVAL_Y: i64 = SimConfig::WORLD_H;
}
