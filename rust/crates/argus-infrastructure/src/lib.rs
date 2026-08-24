//! Concrete Argus technical adapters.
//!
//! SQLite is intentionally kept behind this crate. The public SQLite module
//! exposes bounded, bridge-neutral operations and stable infrastructure
//! failures; callers never receive a `rusqlite` error or transaction value.

pub mod artwork_store;
pub mod content;
pub mod credentials;
pub mod diagnostics;
pub mod local_filesystem;
pub mod providers;
pub mod sqlite;
