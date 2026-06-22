---
ac: 1
depends_on: "#1 (merged)"
risk: low
---

## AC spec: Extract `render_outcome_section(df, title, intro_lines)` helper from `write_md_report()`

### Executable Spec

- **predicate:** (4-part, all must hold)
  1. **(Unit — helper correctness)** Direct call to `render_outcome_section(df, title, intro_lines)` with a synthetic 3-row data frame (2 files, multiple rows per file) produces a character vector **byte-identical** to the expected markdown: `title`, blank, `intro_lines` lines, blank, then for each file in `unique(df$file)` order: `` ### `file` ``, blank, `| Line | Original | Mutated To |`, `|------|----------|------------|`, one `| line | `original` | `replacement` |` row per mutant in original row order, closing blank. The helper does NOT emit a leading blank line separator (caller's responsibility) and does NOT guard for `nrow(df)==0` (caller guards with `if (outcome_count > 0)`).
  2. **(Integration — both call sites)** Call `write_md_report(results_df, tmp_dir)` with a synthetic `results_df` containing 2 unviable rows (file `guard.R`) and 1 missed row (file `math.R`). Read the written `.md` file. Assert: (a) `## Unviable Mutants` appears BEFORE `## Missed Mutants`; (b) each section's intro text matches the original distinct text (`"package loading"` in unviable, `"not detected by the test suite"` in missed); (c) per-file grouping works (`` ### `guard.R` ``, `` ### `math.R` ``); (d) at least one full table row within each section is byte-exact (e.g., `| 2 | `!=` | `==` |` for unviable, `| 10 | `>` | `<=` |` for missed); (e) `| Line | Original | Mutated To |` appears exactly twice (once per section).
  3. **(Structural — no inline loop remains)** In `R/mutate_test.R` source: `for (f in unique(` appears exactly **once** (inside the helper definition); `| Line | Original | Mutated To |` appears exactly **once** (inside the helper); `render_outcome_section(` appears **≥3 times** (1 definition + 2 calls). Both call sites retain `if (... > 0)` guards and pass `df`, `title`, `intro_lines` in matching signature order.
  4. **(Regression — all existing tests pass)** `testthat::test_file('tests/testthat/test-mutate_test.R')` exits 0 with all tests passing, including the unviable_source_error check for `` ### `guard.R` `` / `` ### `mult.R` `` headings (L290-293) and the report-output test's conditional `## Missed Mutants` check (L175).

- **probe:**
  ```r
  # Save as /tmp/ac_probe.R and run: Rscript /tmp/ac_probe.R
  # (heredoc avoids backtick escaping issues in shell)
  pkgload::load_all()

  # --- (3) Structural check: helper extracted, no inline loops remain ---
  src <- readLines('R/mutate_test.R')
  loop_count <- sum(grepl('for (f in unique(', src, fixed = TRUE))
  hdr_count  <- sum(grepl('| Line | Original | Mutated To |', src, fixed = TRUE))
  call_count <- sum(grepl('render_outcome_section(', src, fixed = TRUE))
  stopifnot(loop_count == 1L, hdr_count == 1L, call_count >= 3L)

  # --- (1) Unit test: helper produces byte-identical markdown ---
  df <- data.frame(
    file = c('a.R', 'a.R', 'b.R'),
    line = c(10L, 20L, 5L),
    original = c('>', 'TRUE', '+'),
    replacement = c('<=', 'FALSE', '-'),
    stringsAsFactors = FALSE
  )
  result <- render_outcome_section(df, '## Missed Mutants',
                                   c('Intro line 1.', 'Intro line 2.'))
  expected <- c(
    '## Missed Mutants', '',
    'Intro line 1.', 'Intro line 2.', '',
    '### `a.R`', '',
    '| Line | Original | Mutated To |',
    '|------|----------|------------|',
    '| 10 | `>` | `<=` |',
    '| 20 | `TRUE` | `FALSE` |', '',
    '### `b.R`', '',
    '| Line | Original | Mutated To |',
    '|------|----------|------------|',
    '| 5 | `+` | `-` |', ''
  )
  stopifnot(identical(as.character(result), expected))

  # --- (2) Integration test: both sections via shared helper ---
  results_df <- data.frame(
    file = c('guard.R', 'guard.R', 'math.R'),
    line = c(2L, 4L, 10L),
    original = c('!=', '>', '>'),
    replacement = c('==', '<=', '<='),
    outcome = c('unviable', 'unviable', 'missed'),
    stringsAsFactors = FALSE
  )
  tmp <- tempfile('mdtest_'); dir.create(tmp)
  write_md_report(results_df, tmp)
  md <- paste(readLines(file.path(tmp, 'mutant_results.md')), collapse = '\n')
  uv_pos <- regexpr('## Unviable Mutants', md, fixed = TRUE)[1]
  ms_pos <- regexpr('## Missed Mutants', md, fixed = TRUE)[1]
  stopifnot(uv_pos > 0, ms_pos > uv_pos)                      # (a) ordering
  stopifnot(grepl('package loading', md, fixed = TRUE))       # (b) unviable intro
  stopifnot(grepl('not detected by the test suite', md, fixed = TRUE))  # (b) missed intro
  stopifnot(grepl('### `guard.R`', md, fixed = TRUE))         # (c) per-file grouping
  stopifnot(grepl('### `math.R`', md, fixed = TRUE))
  stopifnot(grepl('| 2 | `!=` | `==` |', md, fixed = TRUE))   # (d) exact unviable row
  stopifnot(grepl('| 10 | `>` | `<=` |', md, fixed = TRUE))   # (d) exact missed row
  hdr_matches <- gregexpr('| Line | Original | Mutated To |', md, fixed = TRUE)[[1]]
  stopifnot(length(hdr_matches) == 2L && hdr_matches[1] > 0)  # (e) header x2
  unlink(tmp, recursive = TRUE)

  # --- (4) Regression: all existing tests pass ---
  testthat::test_file('tests/testthat/test-mutate_test.R')
  cat('ALL CHECKS PASSED\n')
  ```

- **negative:** Sneaky-passes that must be rejected (all defended by the predicate above):

  | # | Sneaky-pass | Defense |
  |---|------------|---------|
  | N1 | Helper called from only ONE section (half-extraction) | Structural predicate (3): `for (f in unique(` count == 1 forces both inline loops removed |
  | N2 | `title` parameter ignored; helper hardcodes `"## Missed Mutants"` | Unit test (1): heading matches passed `title`; integration (2): both headings differ |
  | N3 | `intro_lines` ignored; helper uses hardcoded text | Integration (2): assert `"package loading"` in unviable, `"not detected"` in missed |
  | N4 | Table column header changed (e.g., `"Replacement"` instead of `"Mutated To"`) | Unit test (1): exact match on header string |
  | N5 | Separator dash-count drift | Unit test (1): exact match on separator string |
  | N6 | Row format changed (missing backticks, column reorder, trailing spaces) | Unit test (1): exact per-row match |
  | N7 | Per-file heading loses backticks (`` ### guard.R `` vs `` ### `guard.R` ``) | Unit test (1) + integration (2): exact/grepl match |
  | N8 | Section ordering reversed (Missed before Unviable) | Integration (2): `uv_pos < ms_pos` |
  | N9 | Section rendered when df is empty (0 rows) | Caller must guard with `nrow(df) > 0` — structural check confirms guards remain |
  | N10 | Dead-code helper (defined but never called; both sites keep inline loop) | Structural predicate (3): `for (f in unique(` count == 1 proves inline loops gone |
  | N11 | Helper defined in test file only, not in `R/mutate_test.R` | `pkgload::load_all()` makes `render_outcome_section` accessible — proves definition in package namespace |
  | N12 | Existing unviable tests break because MD format changed | Regression predicate (4): all existing tests pass |
  | N13 | Mutant rows sorted by line number instead of preserving original row order | Unit test (1): a.R rows are 10 then 20 (original order), not 20 then 10 |

- **verification:** code · `Rscript` probe (unit + integration + structural + regression) — strongest medium the AC demands; no manual inspection needed
- **fixture status:** NEW — unit test fixture (inline 3-row data frame, no temp package needed) + integration test fixture (inline 3-row, 2-outcome, 2-file data frame); builder should add both as `test_that()` blocks to `tests/testthat/test-mutate_test.R`. Existing fixtures must continue passing: `tests/testthat/test-mutate_test.R:118` (markdown report test), `:182` (unviable classification test with MD assertions at L274, L290-293).
- **rubric anchor:** §3.3 (single-responsibility helpers), §5.2 (concise by default — removes duplicated loop), §5.3 (testable without patches — helper is pure, unit-testable with `expect_equal`)

### Design Intent

- **Types / interfaces (§1):** Helper signature `render_outcome_section(df, title, intro_lines)` makes the section-differentiation data explicit: `title` and `intro_lines` are parameters, not hardcoded branches. A single function handles both outcomes. The returned character vector has no hidden state. In R, the contract is enforced by docstring and test assertions rather than a static type checker.
- **Pure / effectful (§2):** `render_outcome_section` is a **pure function**: `data.frame` + strings in → `character` vector out. No I/O, no file access, no global state. `write_md_report` remains the thin effectful shell that computes summary stats, guards each section, and calls `writeLines()`.
- **Boundary cuts (§3):** The seam is the per-outcome section rendering. Before: two nearly-identical blocks at L134–156 and L158–180. After: one helper, two call sites. The joint is at the `if (outcome_count > 0)` guard — the caller filters and guards, the helper renders. The helper does NOT know which outcome it's rendering (no `if outcome == "missed"` branching inside it). The helper does NOT emit the leading blank line separator — the call site does `lines <- c(lines, "", render_outcome_section(...))`.
- **Module responsibility (§4):** `render_outcome_section` header docstring states: "Renders a markdown detail section for one mutation outcome. Does NOT filter — the caller must pass a pre-filtered data frame. Does NOT write to disk — returns a character vector." The `write_md_report` header updates to note that section rendering is delegated.
- **Function discipline (§5):** §5.1 — helper does exactly one thing (render a single outcome section); §5.2 — removes the duplicated per-file grouping loop (~23 lines × 2), replacing with ~12-line helper + 2 call sites; §5.3 — pure function, testable with `expect_equal()` without patches or temp files.

### Technical Context

- **Files likely touched:**
  - `R/mutate_test.R` — **primary**: add `render_outcome_section()` definition (between `write_json_report` L103 and `write_md_report` L107, or after `write_md_report` L183). Replace duplicated loops at L134–156 and L158–180 with two guarded calls.
  - `tests/testthat/test-mutate_test.R` — add 2 new `test_that()` blocks (helper unit test + integration test proving both sections use the helper)
  - No other files touched (pure refactor, no API change)

- **Architecture notes — exact duplicated loop structure (verified against source):**

  **Block 1 (Unviable, L134–156):** Guard `if (unviable > 0)`; filter `unviable_df`; prefix `lines <- c(lines, "", "## Unviable Mutants", "", intro_lines..., "")`; loop `for (f in unique(unviable_df$file))` emits `sprintf("### \`%s\`", f)`, `""`, table header, separator, rows, `""`.

  **Block 2 (Missed, L158–180):** Structurally identical except guard variable, local df name, heading text, intro text. **The per-file inner loop is byte-identical.**

  **Call site transformation (expected):**
  ```r
  # Before (Unviable, L134-156): inline loop
  # After:
  if (unviable > 0) {
    unviable_df <- results_df[results_df$outcome == "unviable", ]
    lines <- c(lines, "", render_outcome_section(unviable_df,
      "## Unviable Mutants",
      c("These mutations caused errors during package loading (source/load",
        "failure) and could not be tested. Common causes include modified",
        "guard expressions, broken R syntax, or missing files.")))
  }
  # Missed analogous with "## Missed Mutants" and its distinct intro text
  ```

  **Load-bearing detail:** The leading `""` (blank line before section) is emitted at the call site via `c(lines, "", render_outcome_section(...))`, NOT inside the helper. The guard `if (outcome_count > 0)` stays at the call site. The helper is only called when the subset is non-empty.

### Dependencies

- **Depends on:** #1 (merged — unviable classification code is on `main`)
- **Blocks:** none — leaf cleanup refactor
- **Conflict set:** `R/mutate_test.R` (both sections refactored), `tests/testthat/test-mutate_test.R` (new tests added)
- **Risk level:** low — behavior-preserving; helper is pure and trivially testable

### Pattern Detectors

- **Rodney-feasibility:** Not triggered.
- **Bidirectional-contract:** Triggered — markdown output must be byte-identical before/after. Both render-side (unit test on helper return) and parser-side (integration test reads written `.md`) verified.
- **Route-existence:** Not triggered.
- **Cross-file verification:** Triggered — structural predicate requires reading `R/mutate_test.R` as text and counting loop/header occurrences. Probe uses `readLines()` + `grepl(fixed=TRUE)`.
- **Refusal-arm enumeration:** No `stop()`/`warning()` in `write_md_report`. Pre-existing weakness: missing columns produce NULL silently. Unit test uses exact expected columns. Additional arms: df with 0 rows (caller guards), extra columns (helper ignores), factors vs strings (must be character), empty `intro_lines`.
- **Producer-shape change:** Triggered — helper consumes `results_df` shape (`file`, `line`, `original`, `replacement`). Propagation surface: `test_mutation_in_place` → `run_mutations_serial/parallel` → `mutate_test` → `write_md_report` → `render_outcome_section`. Mitigated by unit test with exact column names + integration test with exact row format.

<!-- resolver: disagreement=minor | rationale: A said existing fixtures only / R/mutate_test.R only; B correctly requires NEW tests + test file edits. Resolved in favor of B — existing grepl tests can't distinguish helper-call from inline-loop (N1/N10 sneaky-pass). No ambiguity. -->
