# measure/gen: the leak check's generated tables

Rust has no reflection, so the leak check (`fastsim-rs measure leak`, `measure visibility`)
reads two generated tables next to this folder:

- `fields.rs` (by `rs_fields.py`): every field of SimState, RoomRuntime and each `Hz` hazard,
  in C# `GetFields` order (own fields, then the parent's, `base: Base` = kind, alive, t last),
  with getters, setters and the hand-kept `METHODS` table (what visible.tsv may name).
- `methods.rs` (by `rs_methods.py`): the no-argument, non-void public methods of each state
  type, inherited ones included.

Both read the Rust sim (`tools/fastsim-rs/sim/src`). Python 3, stdlib only:

    cd tools/fastsim-rs
    python fastsim/src/measure/gen/rs_fields.py sim/src fastsim/src/measure/fields.rs
    python fastsim/src/measure/gen/rs_methods.py sim/src fastsim/src/measure/methods.rs
    cargo check

Run them when a sim type gains or loses a field or a no-argument method, or a hazard type is
added (then also add it to `hazard_enum!`). Then `fastsim-rs measure check` tells whether
`data/visible.tsv` needs `measure visibility --write`.

Overrides (things the Rust code cannot show):

- `rs_fields.py` `RUST_ONLY`: `Base.idx` (the port's own hazard index) is left out.
- `rs_methods.py` `EXTRA`: `clone_deep` on every hazard (Rust uses Clone),
  `Bouncer.straight_path` (folded into `near_row` in Rust), and `RoomRuntime.inset` /
  `spike_bonus` (optional `side` parameter in the sim, required in Rust).
- A Rust-only accessor is not a method: one named like a field (`def` for `def_`) or returning
  a reference to a hazard parent (`base`, `base_mut`, `boss_mut`, `coin`).
- A new field type needs a line in `rs_fields.py` `TY` (the script stops on an unknown one).
