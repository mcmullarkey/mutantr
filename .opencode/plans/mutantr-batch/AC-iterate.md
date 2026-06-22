---
ac: iterate
depends_on: none
risk: medium
---

## AC spec: Add `iterate` parameter to `mutate_test()` — skip prior caught/unviable mutants while preserving full corpus in output

### Executable Spec
- **predicate:** given a prior `mutant_results.json` in `output_dir` with ≥1 caught, ≥1 unviable, ≥1 missed, when `mutate_test(pkg_path, output_dir = out_dir, iterate = TRUE)` is called, then ALL hold: (1) SKIP-NOT-RELABEL — after weakening the test that caught a prior `caught` mutant, that mutant's returned outcome is still `"caught"`; (2) RETEST — prior `missed` and `timeout` mutants are re-run; (3) NEW — mutants absent from prior results are tested; (4) ROW-COMPLETENESS — `nrow(results) == nrow(prepared)`; skipped mutants appear with prior outcome; (5) MERGE — JSON and MD contain ALL mutants; AND edge handling: (6) `iterate=TRUE` with `output_dir=NULL` → error before scanning; (7) no prior JSON → warn and run all; (8) malformed JSON → warn and run all; (9) match key coerces `line` type differences.
- **probe:** `Rscript -e 'devtools::test(".", filter = "iterate")'`
- **negative:** Filter-only sneaky-pass (re-test but overwrite with old labels) → caught by weakened-test adversarial probe. Match-on-subset → caught when two mutants share a line. Row-loss → caught by nrow check. JSON-not-updated → caught by merge check.
- **verification:** code · testthat
- **fixture status:** NEW — `tests/testthat/test-iterate.R`
- **rubric anchor:** §1.3, §1.5, §2.1, §5.1

### Design Intent
- **Types (§1):** `iterate` is logical scalar, default FALSE. Match key is 4-tuple (file, line, original, replacement) with line type coercion.
- **Pure/effectful (§2):** Split into `read_prior_results(output_dir)` (effect) and `filter_skipped_mutants(prepared, prior)` (pure). Runners unchanged.
- **Boundary cuts (§3):** Filter logic pure in mutate_test.R. JSON I/O isolated in read_prior_results. No back-edge into runners.
- **Module responsibility (§4):** mutate_test.R header updated for iterate behavior.
- **Function discipline (§5):** read_prior_results does only I/O+validation. filter_skipped_mutants does only pure partition. Merge in orchestrator.

### Technical Context
- **Files:** `R/mutate_test.R:19` (signature), after L24 (read+filter), L48-56 (pass subset to runners), L58-59 (merge skipped+tested), L69-73 (write merged reports), new helpers after L363, `man/mutate_test.Rd`, `tests/testthat/test-iterate.R`
- **Key details:** Match key MUST be (file, line, original, replacement). Line type coercion (integer vs numeric after JSON round-trip). Progress bar reflects filtered count. JSON must be full merge.
- **Conflict set:** `R/mutate_test.R`, `man/mutate_test.Rd`, `tests/testthat/test-iterate.R`