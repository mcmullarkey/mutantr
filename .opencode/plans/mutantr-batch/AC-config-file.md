---
ac: config-file
depends_on: none
risk: medium
---

## AC spec: `.mutantr.toml` config support via narrow reader wired into `mutate_test()`

### Executable Spec
- **predicate:** Given 6 temp packages (valid, malformed, empty, unknown-key, no-file, type-mismatched .mutantr.toml): (1) read_config on valid returns flat list with timeout=5, workers=3, output_dir="reports", exclude, iterate, in_diff; (2) mutate_test with no explicit args uses config values; (3) explicit args override config (priority: explicit > config > default); (4) malformed TOML → error with filename; (5) empty file → empty list; (6) unknown keys → accepted, no error; (7) no file → empty list; (8) type-mismatched → error.
- **probe:** `Rscript -e 'testthat::test_file("tests/testthat/test-config.R")'`
- **negative:** Silent-swallow on parse failure (tryCatch → empty list). Happy-path passes but malformed input invisible.
- **verification:** code · testthat
- **fixture status:** NEW — `tests/testthat/test-config.R` with 6 temp-package fixtures + extend `test-mutate_test.R`
- **rubric anchor:** §1.3, §1.3.1, §2.1, §2.2, §2.4, §3.3, §4.1, §4.2, §5.1

### Design Intent
- **Types (§1):** Config is flat named list with typed values. read_config refuses malformed TOML and type-mismatched values at boundary.
- **Pure/effectful (§2):** read_config is effectful (read_* verb). Setting application/merging is pure.
- **Boundary cuts (§3):** R/config.R is narrow reader — parses one file, validates syntax, returns flat list. Does NOT traverse parent dirs, merge sources, or apply settings.
- **Module responsibility (§4):** R/config.R header: reads .mutantr.toml, does NOT validate semantics, does NOT apply settings, does NOT search parent dirs.
- **Function discipline (§5):** read_config does one thing — read, parse, syntax-validate one file.

### Technical Context
- **Files:** NEW `R/config.R`, `R/mutate_test.R:19` (wire read_config + merge), `DESCRIPTION` (add configr to Imports), `NAMESPACE` (keep internal), NEW `tests/testthat/test-config.R`, extend `tests/testthat/test-mutate_test.R`
- **Key details:** configr::read.config(file, format="toml"). Transitive deps: RcppTOML, yaml. Config keys: timeout, workers, output_dir, exclude, iterate, in_diff (forward-compatible). Case-sensitive filename. read_config internal via :::.
- **Conflict set:** `R/mutate_test.R`, `DESCRIPTION`, `NAMESPACE`