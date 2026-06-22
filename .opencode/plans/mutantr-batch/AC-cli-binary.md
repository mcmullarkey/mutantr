---
ac: cli-binary
depends_on: none
risk: low
---

## AC spec: `mutantr` CLI wrapper with CI exit codes (0/1/2)

### Executable Spec
- **predicate:** (a) exit 0: fixture catching all mutants → status 0, stdout has "Mutation Testing Results" and "0 missed"; (b) exit 1: fixture with no tests → status 1, stdout has missed > 0, output differs from (a); (c) exit 2 pre-flight: non-existent path, unknown flag (message contains flag name), missing --pkg, non-numeric --timeout; (d) exit 2 runtime: mutate_test error (baseline fails) → status 2 NOT 1 (inversion guard); both --pkg=path and --pkg path forms accepted.
- **probe:** testthat system2() integration test invoking installed CLI
- **negative:** Cheap shim hardcoding "0 missed" and always exit 0. Shim letting R's stop() propagate (exit 1) on bad paths.
- **verification:** code · testthat system2() integration
- **fixture status:** NEW — `tests/testthat/test-cli.R` with inline tempfile() packages
- **rubric anchor:** §1.2, §1.3, §1.5, §2.1, §2.3, §3.1, §4.1, §4.2, §5.1, §5.3

### Design Intent
- **Types (§1):** Exit code is 3-valued contract (0/1/2) encoded by pure compute_exit_code(results, error).
- **Pure/effectful (§2):** parse_args, validate_args, compute_exit_code, find_rscript are pure/read-only. cli_main is effectful. Pure helpers in R/cli.R for unit testing.
- **Boundary cuts (§3):** CLI is distinct entry point (inst/bin/mutantr). Pre-flight validation layer between arg parsing and mutate_test.
- **Module responsibility (§4):** inst/bin/mutantr: parse args, validate, locate Rscript, invoke, map exit codes. Does NOT do mutation scanning or test execution.
- **Function discipline (§5):** parse_args, validate_args, compute_exit_code, find_rscript, cli_main — each one job.

### Technical Context
- **Files:** NEW `inst/bin/mutantr` (#!/usr/bin/env Rscript shebang, calls mutantr:::cli_main), NEW `R/cli.R` (parse_args, validate_args, compute_exit_code, find_rscript, cli_main), NEW `tests/testthat/test-cli.R`
- **Key details:** Critical inversion guard: mutate_test's normalizePath stop() exits 1 at Rscript level — CLI must pre-flight validate AND tryCatch. Rscript location: Sys.which first, fallback R.home("bin"). --iterate/--in-diff: accept with warning, don't forward yet. --help/--version: exit-0 fast paths. shQuote for path quoting.
- **Conflict set:** NEW `inst/bin/mutantr`, NEW `R/cli.R`, NEW `tests/testthat/test-cli.R`