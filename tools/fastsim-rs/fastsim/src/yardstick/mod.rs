//! Yardstick/ (docs/YARDSTICK.md): one measure for every bot. STUB: being ported.
pub mod bots;

use crate::speed::Opts;

/// `fastsim yardstick run|compare|list|humans` (YardstickMain.run).
pub fn run(_pos: &[String], _opts: &Opts) -> i32 {
    eprintln!("yardstick: not ported yet");
    2
}
