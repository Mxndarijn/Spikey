//! Port of sim/rooms/catalog_puzzles.gd. Order is part of the rules.
use crate::prelude::*;

pub struct CatalogPuzzles;

impl CatalogPuzzles {
    pub fn defs() -> Vec<RoomDef> {
        let mut out_ = Vec::new();
        // Buttons: press the lit button, top and bottom in turn; only presses score.
        let mut buttons = RoomDef::new("buttons", "mid", 30);
        buttons.bounce_points = false;
        buttons.max_spikes = 5;
        buttons.hazards.push(mk(|| ButtonPair::new().into()));
        buttons.variants = vec![RoomVariant::new("classic"), RoomVariant::new("slim"), RoomVariant::new("apart")];
        out_.push(buttons);
        out_
    }
}
