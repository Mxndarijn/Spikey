//! Port of Yardstick/Bots.cs: the bots the yardstick knows.
use std::sync::Arc;

use sim::prelude::*;

/// A fresh decide function for one run: called once per tick, before sim.step(), it returns
/// whether to tap. It must not step or change the sim (clone it to look ahead).
pub type Decide = Box<dyn FnMut(&GameSim) -> bool + Send>;
/// `make(seed)`.
pub type Make = Arc<dyn Fn(i64) -> Decide + Send + Sync>;

/// C# record BotSpec(name, about, copies, make).
#[derive(Clone)]
pub struct BotSpec {
    pub name: String,
    pub about: String,
    pub copies: &'static str,
    pub make: Make,
}

impl BotSpec {
    pub fn peeks(&self) -> bool {
        self.copies == Copies::REAL
    }
}

pub struct Copies;
impl Copies {
    pub const REAL: &'static str = "real";
    pub const SCRAMBLED: &'static str = "scrambled";
    pub const NONE: &'static str = "none";
    /// Scrambled copies that still leak some hidden draws.
    pub const LEAKY: &'static str = "scrambled (leaky)";
}
