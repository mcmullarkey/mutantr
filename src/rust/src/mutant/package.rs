use std::path::Path;

use serde::{Deserialize, Serialize};

use super::error::MutantError;
use super::mutate::apply_mutation;
use super::scanner::scan_source;
use super::types::{Mutation, MutationSite};

/// Scan a single R file for mutation sites.
pub fn scan_file(path: &str) -> Result<Vec<MutationSite>, MutantError> {
    let path = Path::new(path);
    if !path.exists() {
        return Err(MutantError::FileNotFound(path.to_path_buf()));
    }
    let source = std::fs::read_to_string(path).map_err(|e| MutantError::ReadError {
        path: path.to_path_buf(),
        source: e,
    })?;
    let file_name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown");
    Ok(scan_source(&source, file_name))
}

/// Scan all `.R` files in a package's `R/` directory.
pub fn scan_package(package_path: &str) -> Result<Vec<MutationSite>, MutantError> {
    let r_dir = Path::new(package_path).join("R");
    if !r_dir.exists() {
        return Err(MutantError::FileNotFound(r_dir.to_path_buf()));
    }

    let mut all_sites = Vec::new();
    let entries = std::fs::read_dir(&r_dir).map_err(|e| MutantError::ReadError {
        path: r_dir.to_path_buf(),
        source: e,
    })?;

    for entry in entries {
        let entry = entry.map_err(|e| MutantError::ReadError {
            path: r_dir.to_path_buf(),
            source: e,
        })?;
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) == Some("R") {
            let sites = scan_file(path.to_str().unwrap_or(""))?;
            all_sites.extend(sites);
        }
    }

    Ok(all_sites)
}

/// A mutation with its pre-applied content, ready for testing.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PreparedMutation {
    pub file: String,
    pub line: usize,
    pub col: usize,
    pub span_start: usize,
    pub span_end: usize,
    pub original: String,
    pub replacement: String,
    pub mutated_content: String,
}

/// Scan a package, generate all mutations, and return pre-applied content for each.
pub fn prepare_all(package_path: &str) -> Result<Vec<PreparedMutation>, MutantError> {
    let r_dir = Path::new(package_path).join("R");
    if !r_dir.exists() {
        return Err(MutantError::FileNotFound(r_dir.to_path_buf()));
    }

    let mut prepared = Vec::new();
    let entries = std::fs::read_dir(&r_dir).map_err(|e| MutantError::ReadError {
        path: r_dir.to_path_buf(),
        source: e,
    })?;

    for entry in entries {
        let entry = entry.map_err(|e| MutantError::ReadError {
            path: r_dir.to_path_buf(),
            source: e,
        })?;
        let file_path = entry.path();
        if file_path.extension().and_then(|e| e.to_str()) != Some("R") {
            continue;
        }

        let file_name = file_path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("unknown")
            .to_string();

        let source = std::fs::read_to_string(&file_path).map_err(|e| MutantError::ReadError {
            path: file_path.to_path_buf(),
            source: e,
        })?;

        let sites = scan_source(&source, &file_name);

        for site in &sites {
            for replacement in &site.replacements {
                let mutation = Mutation {
                    site: site.clone(),
                    replacement: replacement.clone(),
                };
                if let Ok(result) = apply_mutation(&source, &mutation) {
                    prepared.push(PreparedMutation {
                        file: file_name.clone(),
                        line: site.location.line,
                        col: site.location.col,
                        span_start: site.location.span.start,
                        span_end: site.location.span.end,
                        original: site.original.clone(),
                        replacement: replacement.clone(),
                        mutated_content: result.text,
                    });
                }
            }
        }
    }

    Ok(prepared)
}

/// Prepare all mutations and return as JSON.
pub fn prepare_all_json(package_path: &str) -> Result<String, MutantError> {
    let prepared = prepare_all(package_path)?;
    serde_json::to_string(&prepared).map_err(|e| MutantError::ReadError {
        path: std::path::PathBuf::from(package_path),
        source: std::io::Error::new(std::io::ErrorKind::Other, e),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scan_file_reads_and_scans() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("test.R");
        std::fs::write(&path, "x == y").unwrap();

        let sites = scan_file(path.to_str().unwrap()).unwrap();
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].original, "==");
        assert_eq!(sites[0].location.file, "test.R");
    }

    #[test]
    fn scan_file_not_found() {
        let result = scan_file("/nonexistent/path/test.R");
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), MutantError::FileNotFound(_)));
    }

    #[test]
    fn scan_package_finds_r_files() {
        let dir = tempfile::tempdir().unwrap();
        let r_dir = dir.path().join("R");
        std::fs::create_dir(&r_dir).unwrap();
        std::fs::write(r_dir.join("a.R"), "x + y").unwrap();
        std::fs::write(r_dir.join("b.R"), "TRUE").unwrap();
        // Non-R file should be ignored
        std::fs::write(r_dir.join("notes.txt"), "x == y").unwrap();

        let sites = scan_package(dir.path().to_str().unwrap()).unwrap();
        assert_eq!(sites.len(), 2); // + from a.R, TRUE from b.R
    }

    #[test]
    fn scan_package_missing_r_dir() {
        let dir = tempfile::tempdir().unwrap();
        let result = scan_package(dir.path().to_str().unwrap());
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), MutantError::FileNotFound(_)));
    }
}
