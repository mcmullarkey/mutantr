# Feature: mutantr Improvement Batch

## Goal
Implement 6 improvements to mutantr (mutation testing tool for R) identified from cargo-mutants gap analysis: --iterate, --in-diff, numeric constant mutation, function-body replacement, config file, and CLI binary.

## Dependencies
- No hard dependencies between features
- File conflicts determine batching:
  - R/mutate_test.R: touched by --iterate, --in-diff, config file
  - mutant/src/*.rs: touched by numeric constant, function-body replacement
  - New files only: CLI binary

## Acceptance Criteria

### AC-iterate: Add `iterate` parameter to skip prior caught/unviable mutants
- **Depends on:** none
- **Risk:** medium
- **Conflict set:** R/mutate_test.R, man/mutate_test.Rd, tests/testthat/test-iterate.R
- See AC-iterate.md for full spec

### AC-in-diff: Add `in_diff` parameter for PR-incremental filtering
- **Depends on:** none
- **Risk:** low
- **Conflict set:** R/mutate_test.R, NEW R/diff_filter.R
- See AC-in-diff.md for full spec

### AC-numeric-constant: Add numeric literal mutation to Rust scanner
- **Depends on:** none
- **Risk:** medium
- **Conflict set:** mutant/src/scanner.rs, types.rs, tests/integration.rs
- See AC-numeric-constant.md for full spec

### AC-function-body: Detect function definitions and replace bodies with return(NULL)
- **Depends on:** none
- **Risk:** high
- **Conflict set:** mutant/src/types.rs, scanner.rs, tests/integration.rs
- See AC-function-body.md for full spec

### AC-config-file: Add .mutantr.toml config file support
- **Depends on:** none
- **Risk:** medium
- **Conflict set:** R/mutate_test.R, DESCRIPTION, NAMESPACE, NEW R/config.R
- See AC-config-file.md for full spec

### AC-cli-binary: Add CLI wrapper with CI exit codes
- **Depends on:** none
- **Risk:** low
- **Conflict set:** NEW inst/bin/mutantr, NEW R/cli.R, NEW tests/testthat/test-cli.R
- See AC-cli-binary.md for full spec

## Implementation Schedule

Batch 1 (parallel, no file conflicts):
  - AC-numeric-constant (mutant/src/)
  - AC-cli-binary (new files only)

Batch 2 (sequential, all touch R/mutate_test.R):
  - AC-config-file (new R/config.R + minimal mutate_test.R change)
  - AC-iterate (mutate_test.R filtering logic)
  - AC-in-diff (mutate_test.R + new R/diff_filter.R)

Batch 3 (sequential, touches mutant/src/, high risk):
  - AC-function-body (mutant/src/ major changes)

## Open Questions
None — all speculator disagreements resolved by resolvers without needing user clarification.