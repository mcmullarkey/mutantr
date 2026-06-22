---
ac: in-diff
depends_on: none
risk: low
---

## AC spec: `in_diff` parameter filters mutations to changed line ranges via new `R/diff_filter.R` module

### Executable Spec
- **predicate:** (a) `parse_diff_ranges(diff_path)` returns data.frame(file, line_start, line_end), one row per hunk, file normalized to basename. (b) `filter_mutations_by_diff(prepared, ranges)` subsets prepared to rows intersecting ranges. (c) `mutate_test(pkg_path, in_diff=diff_path)` with 3-file fixture and diff changing only a.R line 2 and all b.R lines: includes a.R line-2 and all b.R, excludes a.R lines 1,3 and all c.R — proving line-level filtering. (d) strict subset. (e) in_diff=NULL backward compatible. (f) non-existent path errors before baseline. (g) fixture includes omitted-count hunk and multi-hunk file.
- **probe:** `Rscript -e "testthat::test_file('tests/testthat/test-diff_filter.R')"`
- **negative:** File-level-only filter (includes all lines from changed files, ignores hunk ranges).
- **verification:** code · testthat
- **fixture status:** NEW — `tests/testthat/test-diff_filter.R` with 3-file package + multi-hunk diff
- **rubric anchor:** §1.5, §2.1, §2.2, §4.1, §5.1, §5.3

### Design Intent
- **Types (§1):** parse_diff_ranges → data.frame(file, line_start, line_end). filter_mutations_by_diff → subset of prepared.
- **Pure/effectful (§2):** parse is effectful (reads file). filter is pure (takes two data.frames).
- **Boundary cuts (§3):** New R/diff_filter.R module. One-directional import: mutate_test → diff_filter.
- **Module responsibility (§4):** R/diff_filter.R parses diffs and filters mutations. Does NOT run tests or scan R files.
- **Function discipline (§5):** Two functions, each one job. Both testable in isolation.

### Technical Context
- **Files:** NEW `R/diff_filter.R`, `R/mutate_test.R:19` (add param), L23-43 (reorder: prepare → validate in_diff → baseline → filter → empty-check), `man/mutate_test.Rd`, NEW `tests/testthat/test-diff_filter.R`
- **Key details:** prepared$file is basename. Diff paths normalized to basename. Baseline always runs. Filter before empty-check. Helpers internal via :::.
- **Conflict set:** `R/mutate_test.R`, NEW `R/diff_filter.R`