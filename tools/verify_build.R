# Verify R package build end-to-end after consolidation
# Usage: Rscript tools/verify_build.R

library(mutantr)

exit_code <- 0L

# --- AC 1: All 6 exports callable ---
cat("=== AC 1: Check all 6 NAMESPACE exports are callable ===\n")
funcs <- c("mutant_apply", "mutant_prepare_all", "mutant_scan_file",
           "mutant_scan_package", "mutant_scan_source", "mutate_test")
for (f in funcs) {
  ok <- exists(f, where = "package:mutantr", mode = "function")
  cat(sprintf("  %s: %s\n", f, if (ok) "OK" else "MISSING"))
  if (!ok) exit_code <- 1L
}

# --- AC 2: mutant_scan_source returns valid JSON ---
cat("\n=== AC 2: mutant_scan_source returns valid JSON ===\n")
result <- mutant_scan_source("x > 0", "test.R")
parsed <- tryCatch(jsonlite::fromJSON(result), error = function(e) NULL)
if (is.list(parsed)) {
  cat("  OK - valid JSON\n")
} else {
  cat("  FAIL - invalid JSON:", result, "\n")
  exit_code <- 1L
}

# --- AC 3: mutant_scan_file returns valid JSON ---
cat("\n=== AC 3: mutant_scan_file returns valid JSON ===\n")
tmpfile <- tempfile(fileext = ".R")
writeLines("is_positive <- function(x) { if (x > 0) TRUE else FALSE }", tmpfile)
result2 <- mutant_scan_file(tmpfile)
parsed2 <- tryCatch(jsonlite::fromJSON(result2), error = function(e) NULL)
if (is.list(parsed2)) {
  cat("  OK - valid JSON\n")
} else {
  cat("  FAIL - invalid JSON:", result2, "\n")
  exit_code <- 1L
}
unlink(tmpfile)

# --- AC 4: mutant_prepare_all returns valid JSON with mutations ---
cat("\n=== AC 4: mutant_prepare_all returns valid JSON ===\n")
pkg_dir <- tempfile("testpkg")
dir.create(pkg_dir)
dir.create(file.path(pkg_dir, "R"))
writeLines(c(
  "Package: testpkg", "Title: Test Package", "Version: 0.0.1",
  "Description: A test package.", "License: MIT", "Encoding: UTF-8"
), file.path(pkg_dir, "DESCRIPTION"))
writeLines('exportPattern("^[[:alpha:]]+")', file.path(pkg_dir, "NAMESPACE"))
writeLines(c(
  "is_positive <- function(x) {",
  "  if (x > 0) {",
  "    return(TRUE)",
  "  }",
  "  FALSE",
  "}"
), file.path(pkg_dir, "R", "math.R"))
result3 <- mutant_prepare_all(pkg_dir)
parsed3 <- tryCatch(jsonlite::fromJSON(result3), error = function(e) NULL)
if (is.data.frame(parsed3) && nrow(parsed3) > 0) {
  cat("  OK -", nrow(parsed3), "mutations found\n")
} else {
  cat("  FAIL - unexpected result:", result3, "\n")
  exit_code <- 1L
}

# --- AC 5: mutant_apply works ---
cat("\n=== AC 5: mutant_apply works ===\n")
src <- "x > 0"
applied <- mutant_apply(src, 2, 3, ">", "<=")
cat("  Applied mutation:", applied, "\n")
if (applied == "x <= 0") {
  cat("  OK\n")
} else {
  cat("  FAIL - expected 'x <= 0'\n")
  exit_code <- 1L
}

# --- AC 6: mutate_test() on test package returns data.frame ---
cat("\n=== AC 6: mutate_test() on test package ===\n")

# Create a proper test package
pkg_dir2 <- tempfile("testpkg")
dir.create(pkg_dir2)
dir.create(file.path(pkg_dir2, "R"))
dir.create(file.path(pkg_dir2, "tests", "testthat"), recursive = TRUE)

writeLines(c(
  "Package: testpkg2",
  "Title: Test Package",
  "Version: 0.0.1",
  "Description: A test package.",
  "License: MIT",
  "Encoding: UTF-8"
), file.path(pkg_dir2, "DESCRIPTION"))

writeLines('exportPattern("^[[:alpha:]]+")', file.path(pkg_dir2, "NAMESPACE"))

# A simple function with an == operator
writeLines(c(
  "is_positive <- function(x) {",
  "  if (x > 0) {",
  "    return(TRUE)",
  "  }",
  "  FALSE",
  "}"
), file.path(pkg_dir2, "R", "math.R"))

# A test that should catch mutations
writeLines(c(
  'test_that("is_positive works", {',
  '  expect_true(is_positive(1))',
  '  expect_false(is_positive(-1))',
  '  expect_false(is_positive(0))',
  '})'
), file.path(pkg_dir2, "tests", "testthat", "test-math.R"))

writeLines(c(
  'library(testthat)',
  'library(testpkg2)',
  'test_check("testpkg2")'
), file.path(pkg_dir2, "tests", "testthat.R"))

# Run mutation testing
capture.output(
  { results <- mutate_test(pkg_dir2) },
  type = "message"
)

# Verify data frame properties
is_df <- is.data.frame(results)
has_outcome <- "outcome" %in% names(results)
has_file <- "file" %in% names(results)
has_original <- "original" %in% names(results)
has_replacement <- "replacement" %in% names(results)
has_line <- "line" %in% names(results)
nrows <- nrow(results)
valid_outcomes <- all(results$outcome %in% c("caught", "missed", "unviable", "timeout"))
n_caught <- sum(results$outcome == "caught")

cat(sprintf("  data.frame: %s\n", if (is_df) "OK" else "FAIL"))
cat(sprintf("  nrow > 0: %s (%d)\n", if (nrows > 0) "OK" else "FAIL", nrows))
cat(sprintf("  outcome column: %s\n", if (has_outcome) "OK" else "FAIL"))
cat(sprintf("  all valid outcomes: %s\n", if (valid_outcomes) "OK" else "FAIL"))
cat(sprintf("  n_caught > 0: %s (%d)\n", if (n_caught > 0) "OK" else "FAIL", n_caught))

if (!is_df || !has_outcome || nrows == 0 || !valid_outcomes || n_caught == 0) {
  cat("  DETAILS:\n")
  print(table(results$outcome))
  exit_code <- 1L
}

unlink(pkg_dir, recursive = TRUE)
unlink(pkg_dir2, recursive = TRUE)

cat("\n=== SUMMARY ===\n")
if (exit_code == 0L) {
  cat("All verifications PASSED\n")
} else {
  cat("Some verifications FAILED\n")
}

quit(save = "no", status = exit_code)
