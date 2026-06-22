---
ac: 1
depends_on: none
risk: low
---

## AC spec: Distinguish unviable (source/load error) from caught (test failure) in mutation test runner

### Executable Spec
- **predicate:** Given a temp R package with two R files, each containing a function and a top-level `stopifnot()` guard expression, where the mutation scanner produces both source-error mutants (guard mutations causing `stopifnot(FALSE)` during `source()`) and test-failure mutants (function-body mutations detected by the test suite), when `mutate_test(pkg_path, output_dir = out_dir)` runs, then: (a) the returned data frame has ≥1 row with `outcome == "unviable"` AND ≥1 row with `outcome == "caught"` (proves non-conflation); (b) the unviable rows correspond to guard-expression mutation sites and the caught rows correspond to function-body mutation sites; (c) `json_data$summary$unviable > 0`; (d) the MD report contains a `## Unviable Mutants` detail section; (e) `capture.output()` of the run includes the string `"unviable"`; (f) `json_data$summary$mutation_score == 100` when `missed == 0` (unviable excluded from denominator).
- **probe:**
  ```
  Rscript -e "testthat::test_file('tests/testthat/test-mutate_test.R', filter = 'unviable_source_error')"
  ```
- **negative:** Source-error mutant classified as `"caught"` (the original bug, inflating the score) OR test-failing mutant classified as `"unviable"` (the sneaky-pass, deflating the score) OR JSON/MD/data-frame unviable counts disagree.
- **verification:** code · testthat filtered test run
- **fixture status:** NEW — inline fixture in `tests/testthat/test-mutate_test.R` with two R files (`guard.R`, `mult.R`), each containing a function and a top-level `stopifnot()` guard, producing 2 unviable mutants (guard mutations) and 2 caught mutants (function-body mutations).
- **rubric anchor:** §1.2, §1.5, §5.1, §5.3

### Design Intent
- **Types / interfaces (§1.2):** Add a `source_error` boolean to the `run_tests_in_copy()` return list, consistent with the existing `timeout`/`error` boolean pattern. This makes the source-vs-test phase distinction explicit in the return value. A `phase` enum field ("source"/"test"/"none") would be the ideal sum-type encoding, but R lacks sum types and the existing code already uses mutually-exclusive booleans — `source_error` follows the same idiom with minimal disruption. The four outcomes (`caught`, `missed`, `unviable`, `timeout`) are derivable by ordered dispatch on the result fields.
- **Pure / effectful (§2.1):** `run_tests_in_copy()` remains the thin effectful shell (spawns `callr::r()`). Phase detection happens inside the callr lambda (effectful context). The classification decision in `test_mutation_in_place()` remains a pure dispatch on the returned result list.
- **Boundary cuts (§3):** No new seams. The phase distinction lives at the existing boundary between `run_tests_in_copy` (execution) and `test_mutation_in_place` (classification) — the return value is the seam. Adding `source_error` to it is a representation change at the joint.
- **Module responsibility (§4):** `R/mutate_test.R` owns end-to-end orchestration. Update the `roxygen2` header for `mutate_test()` to state that `"unviable"` covers both missing files and source/load failures. `write_md_report()` gains a new responsibility: listing unviable mutants in a detail section.
- **Function discipline (§5.1, §5.3):** Split the source phase from the test phase inside the `run_tests_in_copy()` callr lambda into two independent `tryCatch` blocks. Keep `test_mutation_in_place()` as a single classification function with ordered dispatch. Test with a real temp package fixture (two files, guards + functions) rather than monkey-patching `callr::r()`.

### Technical Context
- **Files likely touched:**
  - `R/mutate_test.R:273-322` (`run_tests_in_copy` — split inner callr lambda into two tryCatch blocks: source phase and test phase; add `source_error = TRUE/FALSE` to all return paths)
  - `R/mutate_test.R:226-269` (`test_mutation_in_place` — insert `source_error` check in classification dispatch)
  - `R/mutate_test.R:104-156` (`write_md_report` — add `## Unviable Mutants` detail section modeled on `## Missed Mutants` at L131-153)
  - `R/mutate_test.R:14` (roxygen2 `@return` header — note `"unviable"` covers source/load errors)
  - `tests/testthat/test-mutate_test.R` — add new test block with inline fixture

- **Architecture notes:**
  - **Current bug:** `run_tests_in_copy()` wraps both `source()` and `testthat::test_dir()` in a single `tryCatch` (L280-302). Any error — whether from sourcing or from tests — returns `list(passed = FALSE, n_failed = -1L, error_msg = ...)`. The outer handler at L310 sets `error = FALSE`, so the inner error_msg is lost. `test_mutation_in_place()` then maps `!passed` → `"caught"`, conflating source errors with test failures.
  - **Fix:** Inside the callr lambda, wrap the `source()` loop in its own `tryCatch` that returns `list(passed = FALSE, source_error = TRUE, n_failed = NA_integer_)` on error. Wrap `testthat::test_dir()` separately with `source_error = FALSE` on success.
  - **Check ordering in `test_mutation_in_place()` (L254-262):** `source_error` check MUST come AFTER `timeout` and BEFORE `error` and `!passed`:
    ```r
    outcome <- if (test_result$timeout) {
      "timeout"
    } else if (isTRUE(test_result$source_error)) {
      "unviable"
    } else if (isTRUE(test_result$error)) {
      "caught"
    } else if (!test_result$passed) {
      "caught"
    } else {
      "missed"
    }
    ```
  - **Producer-shape propagation — ALL return paths must include `source_error`:**
    - Return path 1 (success, L310): add `source_error = isTRUE(out$source_error)`
    - Return path 2 (callr timeout, L313-314): add `source_error = FALSE`
    - Return path 3 (callr error, L317-318): add `source_error = FALSE`
    - Inside callr lambda, source-success path: set `source_error = FALSE` before proceeding to test phase
    - Inside callr lambda, source-failure path: return `list(passed = FALSE, source_error = TRUE, n_failed = NA_integer_)`
  - **MD report:** Summary table already counts unviable (L125). Add `## Unviable Mutants` detail section (modeled on `## Missed Mutants` at L131-153) listing unviable mutants grouped by file when `unviable > 0`.
  - **JSON report:** Already correct — `unviable` in summary (L81, L91) and full results in `results` field (L95). No changes needed.
  - **Console output:** Already data-driven via `table()` iteration (L59-64). No code change needed, but test must verify it includes "unviable".
  - **Revert safety:** The `writeLines(original_content, r_file)` revert at L252 runs unconditionally after `run_tests_in_copy()` returns. A source error inside the callr process doesn't affect the parent process's ability to revert. This invariant must be preserved.

- **Fixture design (inline in test):**
  ```
  Package structure (temp dir):
    R/
      guard.R    — add <- function(x,y) { x + y }; stopifnot(add(1,2) != 4)
      mult.R     — mult <- function(x,y) { x * y }; stopifnot(mult(2,3) > 0)
    tests/testthat/
      test-math.R — test_that blocks for add() and mult()

  Mutations produced by scanner:
    guard.R:  + → -  (Arithmetic),  != → ==  (Comparison)
    mult.R:   * → /  (Arithmetic),  >  → <=  (Comparison)

  Expected classification after fix:
    +  → -   → source succeeds → tests fail    → "caught"
    != → ==  → stopifnot(FALSE) → source error → "unviable"
    *  → /   → source succeeds → tests fail    → "caught"
    >  → <=  → stopifnot(FALSE) → source error → "unviable"

  Unviable count: 2. Caught count: 2. Missed: 0. Timeout: 0.
  Mutation score: 2/(2+0) = 100%.
  ```
  Two files with guards defend against the sneaky-pass where the implementation hardcodes `"unviable"` for a specific `(original, replacement)` pair. With two distinct source-error-causing mutations in different files, a hardcoded lookup table would need to know both.

### Dependencies
- **Depends on:** none — standalone change to R-side orchestration
- **Blocks:** none — leaf change
- **Conflict set:** `R/mutate_test.R`, `tests/testthat/test-mutate_test.R`
- **Risk level:** low — localized, existing output code already handles unviable count; only classification path and MD detail section change

### Pattern Detectors
No pattern-detector flags raised by either proposer.
