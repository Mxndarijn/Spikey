//! Flapjaw's own game server (docs/SERVER_MIGRATION.md).
//!
//! A typed HTTP layer over Postgres. The game's rules stay where they were
//! tested: the SQL functions in backend/migrations/ (boards, Daily Run, wallet,
//! prizes, earn status, saves, push alerts), written for Supabase and applied
//! as they are. On top the server does what Supabase and GitHub did around them: sign-in with device
//! keys, the replay check (the Rust sim, with headless Godot confirming
//! rejections), sending the queued push alerts, and phone transfers.

pub mod app;
pub mod auth;
pub mod bot;
pub mod config;
pub mod db;
pub mod duel;
pub mod duel_ws;
pub mod error;
pub mod limits;
pub mod push;
pub mod rpc;
pub mod transfer;
pub mod verify;
