//! Mutation engine for R source code.
//!
//! Nested module of the `rmutant` staticlib — inlined from the former
//! standalone `mutant` crate. Scans R files for mutation sites and applies
//! operator-based mutations.
//!
//! This module is NOT an external crate and is NOT R-facing; extendr
//! wrapper glue lives in `lib.rs`.

pub mod error;
pub mod mutate;
pub mod operators;
pub mod package;
pub mod scanner;
pub mod types;

pub use error::MutantError;
pub use mutate::apply_mutation;
pub use package::{prepare_all, prepare_all_json, scan_file, scan_package, PreparedMutation};
pub use scanner::scan_source;

/// Scan a single R file and return mutation sites as JSON.
pub fn scan_file_json(path: &str) -> Result<String, MutantError> {
    let sites = scan_file(path)?;
    serde_json::to_string(&sites).map_err(|e| MutantError::ReadError {
        path: std::path::PathBuf::from(path),
        source: std::io::Error::new(std::io::ErrorKind::Other, e),
    })
}

/// Scan all R files in a package and return mutation sites as JSON.
pub fn scan_package_json(path: &str) -> Result<String, MutantError> {
    let sites = scan_package(path)?;
    serde_json::to_string(&sites).map_err(|e| MutantError::ReadError {
        path: std::path::PathBuf::from(path),
        source: std::io::Error::new(std::io::ErrorKind::Other, e),
    })
}
