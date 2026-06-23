pub mod mutant;

use extendr_api::prelude::*;

/// Scan a single R file for mutation sites. Returns JSON string.
/// @export
/// @param path Path to an R file
/// @return JSON string of mutation sites
#[extendr]
fn mutant_scan_file(path: &str) -> String {
    match mutant::scan_file_json(path) {
        Ok(json) => json,
        Err(e) => format!("{{\"error\": \"{}\"}}", e),
    }
}

/// Scan all R files in a package's R/ directory. Returns JSON string.
/// @export
/// @param path Path to the package root directory
/// @return JSON string of mutation sites
#[extendr]
fn mutant_scan_package(path: &str) -> String {
    match mutant::scan_package_json(path) {
        Ok(json) => json,
        Err(e) => format!("{{\"error\": \"{}\"}}", e),
    }
}

/// Scan R source text directly. Returns JSON string of mutation sites.
/// @export
/// @param source R source code as a string
/// @param file_name Name to use for the file in results
/// @return JSON string of mutation sites
#[extendr]
fn mutant_scan_source(source: &str, file_name: &str) -> String {
    let sites = mutant::scan_source(source, file_name);
    serde_json::to_string(&sites).unwrap_or_else(|e| format!("{{\"error\": \"{}\"}}", e))
}

/// Apply a mutation to source text.
/// @export
/// @param source Original R source code
/// @param span_start Byte offset start of the token to replace
/// @param span_end Byte offset end of the token to replace
/// @param original The original token text
/// @param replacement The replacement text
/// @return Mutated source text, or error string
#[extendr]
fn mutant_apply(
    source: &str,
    span_start: i32,
    span_end: i32,
    original: &str,
    replacement: &str,
) -> String {
    let mutation = mutant::types::Mutation {
        site: mutant::types::MutationSite {
            location: mutant::types::Location {
                file: "input".to_string(),
                line: 0,
                col: 0,
                span: mutant::types::Span {
                    start: span_start as usize,
                    end: span_end as usize,
                },
            },
            original: original.to_string(),
            kind: mutant::types::MutationKind::Comparison, // kind doesn't affect mutation
            replacements: vec![replacement.to_string()],
        },
        replacement: replacement.to_string(),
    };

    match mutant::apply_mutation(source, &mutation) {
        Ok(result) => result.text,
        Err(e) => format!("Error: {}", e),
    }
}

/// Batch-prepare all mutations for a package in one call.
///
/// Reads all R/ files, scans for mutation sites, and pre-generates
/// the mutated file content for every possible mutation. Returns JSON.
/// @export
/// @param path Path to the package root directory
/// @return JSON string with all mutations and their pre-applied content
#[extendr]
fn mutant_prepare_all(path: &str) -> String {
    match mutant::prepare_all_json(path) {
        Ok(json) => json,
        Err(e) => format!("{{\"error\": \"{}\"}}", e),
    }
}

/// Classify a mutation test outcome from R-side test result signals.
///
/// Accepts R-side argument order (timeout, source_error, error, passed)
/// and calls `mutant::types::classify` which uses Rust-side order.
/// Returns a lowercase string for direct use by R consumers.
/// @export
/// @param timeout Logical: did the test time out?
/// @param source_error Logical: was there a source/load error?
/// @param error Logical: was there a test runner error?
/// @param passed Logical: did the tests pass?
/// @return Lowercase outcome string: "timeout", "unviable", "caught", or "missed"
#[extendr]
fn mutant_classify_outcome(timeout: bool, source_error: bool, error: bool, passed: bool) -> String {
    match mutant::types::classify(source_error, passed, timeout, error) {
        mutant::types::Outcome::Caught => "caught".to_string(),
        mutant::types::Outcome::Missed => "missed".to_string(),
        mutant::types::Outcome::Unviable => "unviable".to_string(),
        mutant::types::Outcome::Timeout => "timeout".to_string(),
    }
}

extendr_module! {
    mod mutantr;
    fn mutant_scan_file;
    fn mutant_scan_package;
    fn mutant_scan_source;
    fn mutant_apply;
    fn mutant_prepare_all;
    fn mutant_classify_outcome;
}
