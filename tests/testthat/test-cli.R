# Integration tests for mutantr CLI (inst/bin/mutantr)
#
# Tests invoke the CLI via system2() and check exit codes and stdout.
# Test packages are created inline via make_inline_pkg() helper.
#
# Exit code contract:
#   0 — all mutants caught
#   1 — at least one missed mutant
#   2 — error (pre-flight validation or runtime)

# Defensive null-coalesce (avoids rlang dependency)
`%||%` <- function(x, y) if (is.null(x)) y else x

# Helper: create a minimal inline R package for CLI testing
make_inline_pkg <- function(with_tests = TRUE, tests_fail = FALSE) {
  pkg_dir <- tempfile("cli_testpkg")
  dir.create(pkg_dir)
  dir.create(file.path(pkg_dir, "R"))
  if (with_tests) {
    dir.create(file.path(pkg_dir, "tests", "testthat"), recursive = TRUE)
  }

  writeLines(c(
    "Package: clitestpkg",
    "Title: CLI Test Package",
    "Version: 0.0.1",
    "Description: A test package for CLI integration tests.",
    "License: MIT",
    "Encoding: UTF-8"
  ), file.path(pkg_dir, "DESCRIPTION"))

  writeLines(
    'exportPattern("^[[:alpha:]]+")',
    file.path(pkg_dir, "NAMESPACE")
  )

  # Simple function with mutable operators
  writeLines(c(
    "is_positive <- function(x) {",
    "  if (x > 0) {",
    "    return(TRUE)",
    "  }",
    "  FALSE",
    "}"
  ), file.path(pkg_dir, "R", "math.R"))

  if (with_tests) {
    if (tests_fail) {
      # A test that FAILS on the unmutated package
      writeLines(c(
        'test_that("is_positive works", {',
        '  expect_true(is_positive(1))',
        '  expect_false(is_positive(-1))',
        '  expect_true(is_positive(0))  # intentionally wrong: 0 is not positive',
        '})'
      ), file.path(pkg_dir, "tests", "testthat", "test-math.R"))
    } else {
      # Tests that should catch mutations to >, TRUE, FALSE
      writeLines(c(
        'test_that("is_positive works", {',
        '  expect_true(is_positive(1))',
        '  expect_false(is_positive(-1))',
        '  expect_false(is_positive(0))',
        '})'
      ), file.path(pkg_dir, "tests", "testthat", "test-math.R"))
    }

    writeLines(c(
      'library(testthat)',
      'library(clitestpkg)',
      'test_check("clitestpkg")'
    ), file.path(pkg_dir, "tests", "testthat.R"))
  }

  pkg_dir
}

test_that("(a) exit 0: catching fixture returns status 0 and reports 0 missed", {
  skip_if_not_installed("mutantr")
  cli_path <- system.file("bin", "mutantr", package = "mutantr")
  expect_true(cli_path != "", "CLI script not found — install package first")

  pkg_dir <- make_inline_pkg(with_tests = TRUE)
  on.exit(unlink(pkg_dir, recursive = TRUE), add = TRUE)

  result <- system2("Rscript", c(shQuote(cli_path), "--pkg", shQuote(pkg_dir)),
                    stdout = TRUE, stderr = TRUE, wait = TRUE)

  status <- attr(result, "status") %||% 0
  expect_equal(status, 0, info = sprintf("Expected exit 0 for catching fixture, got %d", status))
  stdout_combined <- paste(result, collapse = "\n")
  expect_true(grepl("Mutation Testing Results", stdout_combined))
  # All mutants caught — no mutant should show as missed
  expect_false(grepl("missed", stdout_combined),
               info = "No mutants should be missed when all are caught")
})

test_that("(b) exit 1: no-tests fixture returns status 1 and reports missed > 0", {
  skip_if_not_installed("mutantr")
  cli_path <- system.file("bin", "mutantr", package = "mutantr")
  expect_true(cli_path != "", "CLI script not found — install package first")

  pkg_dir <- make_inline_pkg(with_tests = FALSE)
  on.exit(unlink(pkg_dir, recursive = TRUE), add = TRUE)

  result <- system2("Rscript", c(shQuote(cli_path), "--pkg", shQuote(pkg_dir)),
                    stdout = TRUE, stderr = TRUE, wait = TRUE)

  expect_equal(attr(result, "status") %||% 0, 1)
  stdout_combined <- paste(result, collapse = "\n")
  expect_true(grepl("missed", stdout_combined))
  # Should mention number of missed mutants > 0
  expect_true(grepl("[1-9] missed", stdout_combined))
})

test_that("(c1) exit 2: non-existent path", {
  skip_if_not_installed("mutantr")
  cli_path <- system.file("bin", "mutantr", package = "mutantr")
  expect_true(cli_path != "", "CLI script not found — install package first")

  result <- system2("Rscript", c(shQuote(cli_path), "--pkg", "/nonexistent/path"),
                    stdout = TRUE, stderr = TRUE, wait = TRUE)

  expect_equal(attr(result, "status") %||% 0, 2)
})

test_that("(c2) exit 2: unknown flag includes flag name in message", {
  skip_if_not_installed("mutantr")
  cli_path <- system.file("bin", "mutantr", package = "mutantr")
  expect_true(cli_path != "", "CLI script not found — install package first")

  result <- system2("Rscript", c(shQuote(cli_path), "--pkg", "/tmp", "--bogus=1"),
                    stdout = TRUE, stderr = TRUE, wait = TRUE)

  expect_equal(attr(result, "status") %||% 0, 2)
  stdout_combined <- paste(result, collapse = "\n")
  expect_true(grepl("--bogus", stdout_combined),
              info = "Unknown flag name should appear in error message")
})

test_that("(c3) exit 2: missing --pkg flag", {
  skip_if_not_installed("mutantr")
  cli_path <- system.file("bin", "mutantr", package = "mutantr")
  expect_true(cli_path != "", "CLI script not found — install package first")

  result <- system2("Rscript", c(shQuote(cli_path), "--timeout", "30"),
                    stdout = TRUE, stderr = TRUE, wait = TRUE)

  expect_equal(attr(result, "status") %||% 0, 2)
})

test_that("(c4) exit 2: non-numeric --timeout", {
  skip_if_not_installed("mutantr")
  cli_path <- system.file("bin", "mutantr", package = "mutantr")
  expect_true(cli_path != "", "CLI script not found — install package first")

  pkg_dir <- make_inline_pkg(with_tests = TRUE)
  on.exit(unlink(pkg_dir, recursive = TRUE), add = TRUE)

  result <- system2("Rscript", c(shQuote(cli_path), "--pkg", shQuote(pkg_dir),
                                 "--timeout", "abc"),
                    stdout = TRUE, stderr = TRUE, wait = TRUE)

  expect_equal(attr(result, "status") %||% 0, 2)
})

test_that("(d) exit 2 runtime: failing baseline tests yields status 2 NOT 1", {
  skip_if_not_installed("mutantr")
  cli_path <- system.file("bin", "mutantr", package = "mutantr")
  expect_true(cli_path != "", "CLI script not found — install package first")

  # Package whose baseline tests fail (test says 0 is positive)
  pkg_dir <- make_inline_pkg(with_tests = TRUE, tests_fail = TRUE)
  on.exit(unlink(pkg_dir, recursive = TRUE), add = TRUE)

  result <- system2("Rscript", c(shQuote(cli_path), "--pkg", shQuote(pkg_dir)),
                    stdout = TRUE, stderr = TRUE, wait = TRUE)

  # Must be exit 2 (error), NOT exit 1 (missed mutants)
  status <- attr(result, "status") %||% 0
  expect_equal(status, 2, info = sprintf("Expected exit 2, got %d. Inversion guard failed.", status))
})

test_that("(f) greedy parse: --pkg --timeout 30 errors with 'requires a value'", {
  skip_if_not_installed("mutantr")
  cli_path <- system.file("bin", "mutantr", package = "mutantr")
  expect_true(cli_path != "", "CLI script not found — install package first")

  result <- system2("Rscript",
                    c(shQuote(cli_path), "--pkg", "--timeout", "30"),
                    stdout = TRUE, stderr = TRUE, wait = TRUE)

  expect_equal(attr(result, "status") %||% 0, 2)
  stdout_combined <- paste(result, collapse = "\n")
  expect_true(grepl("--pkg requires a value", stdout_combined),
              info = "Should mention '--pkg requires a value'")
})

test_that("(g) exit 2: --timeout 0 is rejected", {
  skip_if_not_installed("mutantr")
  cli_path <- system.file("bin", "mutantr", package = "mutantr")
  expect_true(cli_path != "", "CLI script not found — install package first")

  pkg_dir <- make_inline_pkg(with_tests = TRUE)
  on.exit(unlink(pkg_dir, recursive = TRUE), add = TRUE)

  result <- system2("Rscript",
                    c(shQuote(cli_path), "--pkg", shQuote(pkg_dir),
                      "--timeout", "0"),
                    stdout = TRUE, stderr = TRUE, wait = TRUE)

  expect_equal(attr(result, "status") %||% 0, 2)
})

test_that("(h) exit 2: --workers -1 is rejected", {
  skip_if_not_installed("mutantr")
  cli_path <- system.file("bin", "mutantr", package = "mutantr")
  expect_true(cli_path != "", "CLI script not found — install package first")

  pkg_dir <- make_inline_pkg(with_tests = TRUE)
  on.exit(unlink(pkg_dir, recursive = TRUE), add = TRUE)

  result <- system2("Rscript",
                    c(shQuote(cli_path), "--pkg", shQuote(pkg_dir),
                      "--workers", "-1"),
                    stdout = TRUE, stderr = TRUE, wait = TRUE)

  expect_equal(attr(result, "status") %||% 0, 2)
})

test_that("(i) malformed results (missing outcome column) produce exit 2", {
  skip_if_not_installed("mutantr")
  library(mutantr)

  # compute_exit_code with data frame missing 'outcome' should stop
  bad_results <- data.frame(mutant_id = 1L)
  expect_error(
    mutantr:::compute_exit_code(bad_results),
    "Internal error: results lacks 'outcome' column"
  )

  # NULL results should also trigger the guard
  expect_error(
    mutantr:::compute_exit_code(NULL),
    "Internal error: results lacks 'outcome' column"
  )
})

test_that("(e) --pkg=value form works identically", {
  skip_if_not_installed("mutantr")
  cli_path <- system.file("bin", "mutantr", package = "mutantr")
  expect_true(cli_path != "", "CLI script not found — install package first")

  pkg_dir <- make_inline_pkg(with_tests = TRUE)
  on.exit(unlink(pkg_dir, recursive = TRUE), add = TRUE)

  result <- system2("Rscript",
                    c(shQuote(cli_path), sprintf("--pkg=%s", shQuote(pkg_dir))),
                    stdout = TRUE, stderr = TRUE, wait = TRUE)

  expect_equal(attr(result, "status") %||% 0, 0)
  stdout_combined <- paste(result, collapse = "\n")
  expect_true(grepl("Mutation Testing Results", stdout_combined))
})
