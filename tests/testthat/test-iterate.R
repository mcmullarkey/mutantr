test_that("iterate = TRUE with NULL output_dir errors", {
  # Create a minimal package so normalizePath() succeeds
  pkg_dir <- tempfile("testpkg")
  dir.create(pkg_dir)
  dir.create(file.path(pkg_dir, "R"))
  dir.create(file.path(pkg_dir, "tests", "testthat"), recursive = TRUE)
  writeLines(c(
    "Package: testpkg", "Title: Test Package", "Version: 0.0.1",
    "Description: A test package.", "License: MIT", "Encoding: UTF-8"
  ), file.path(pkg_dir, "DESCRIPTION"))
  writeLines('exportPattern("^[[:alpha:]]+")', file.path(pkg_dir, "NAMESPACE"))
  writeLines("x <- 1", file.path(pkg_dir, "R", "dummy.R"))
  writeLines(c(
    'library(testthat)',
    'library(testpkg)',
    'test_check("testpkg")'
  ), file.path(pkg_dir, "tests", "testthat.R"))

  expect_error(
    mutate_test(pkg_dir, iterate = TRUE),
    "iterate = TRUE requires output_dir to be set",
    fixed = TRUE
  )

  unlink(pkg_dir, recursive = TRUE)
})

test_that("iterate = TRUE with no prior JSON warns and runs all", {
  pkg_dir <- tempfile("testpkg")
  dir.create(pkg_dir)
  dir.create(file.path(pkg_dir, "R"))
  dir.create(file.path(pkg_dir, "tests", "testthat"), recursive = TRUE)

  writeLines(c(
    "Package: testpkg", "Title: Test Package", "Version: 0.0.1",
    "Description: A test package.", "License: MIT", "Encoding: UTF-8"
  ), file.path(pkg_dir, "DESCRIPTION"))

  writeLines('exportPattern("^[[:alpha:]]+")', file.path(pkg_dir, "NAMESPACE"))

  writeLines(c(
    "is_positive <- function(x) {",
    "  if (x > 0) { return(TRUE) }",
    "  FALSE",
    "}"
  ), file.path(pkg_dir, "R", "math.R"))

  writeLines(c(
    'test_that("is_positive works", {',
    '  expect_true(is_positive(1))',
    '  expect_false(is_positive(-1))',
    '  expect_false(is_positive(0))',
    '})'
  ), file.path(pkg_dir, "tests", "testthat", "test-math.R"))

  writeLines(c(
    'library(testthat)',
    'library(testpkg)',
    'test_check("testpkg")'
  ), file.path(pkg_dir, "tests", "testthat.R"))

  # Empty output_dir with no prior JSON
  out_dir <- tempfile("empty_results")
  dir.create(out_dir)

  expect_warning(
    {
      utils::capture.output({
        results <- mutate_test(pkg_dir, output_dir = out_dir, iterate = TRUE)
      }, type = "message")
    },
    "No prior results found in", fixed = TRUE
  )

  # Should still run all mutants (same as non-iterate)
  expect_s3_class(results, "data.frame")
  expect_gt(nrow(results), 0)

  unlink(pkg_dir, recursive = TRUE)
  unlink(out_dir, recursive = TRUE)
})

test_that("iterate = TRUE with malformed JSON warns and runs all", {
  pkg_dir <- tempfile("testpkg")
  dir.create(pkg_dir)
  dir.create(file.path(pkg_dir, "R"))
  dir.create(file.path(pkg_dir, "tests", "testthat"), recursive = TRUE)

  writeLines(c(
    "Package: testpkg", "Title: Test Package", "Version: 0.0.1",
    "Description: A test package.", "License: MIT", "Encoding: UTF-8"
  ), file.path(pkg_dir, "DESCRIPTION"))

  writeLines('exportPattern("^[[:alpha:]]+")', file.path(pkg_dir, "NAMESPACE"))

  writeLines(c(
    "is_positive <- function(x) {",
    "  if (x > 0) { return(TRUE) }",
    "  FALSE",
    "}"
  ), file.path(pkg_dir, "R", "math.R"))

  writeLines(c(
    'test_that("is_positive works", {',
    '  expect_true(is_positive(1))',
    '  expect_false(is_positive(-1))',
    '  expect_false(is_positive(0))',
    '})'
  ), file.path(pkg_dir, "tests", "testthat", "test-math.R"))

  writeLines(c(
    'library(testthat)',
    'library(testpkg)',
    'test_check("testpkg")'
  ), file.path(pkg_dir, "tests", "testthat.R"))

  out_dir <- tempfile("malformed_results")
  dir.create(out_dir)
  writeLines("this is not valid json", file.path(out_dir, "mutant_results.json"))

  expect_warning(
    {
      utils::capture.output({
        results <- mutate_test(pkg_dir, output_dir = out_dir, iterate = TRUE)
      }, type = "message")
    },
    "Could not read prior results", fixed = TRUE
  )

  expect_s3_class(results, "data.frame")
  expect_gt(nrow(results), 0)

  unlink(pkg_dir, recursive = TRUE)
  unlink(out_dir, recursive = TRUE)
})

test_that("iterate = FALSE (default) behavior unchanged", {
  pkg_dir <- tempfile("testpkg")
  dir.create(pkg_dir)
  dir.create(file.path(pkg_dir, "R"))
  dir.create(file.path(pkg_dir, "tests", "testthat"), recursive = TRUE)

  writeLines(c(
    "Package: testpkg", "Title: Test Package", "Version: 0.0.1",
    "Description: A test package.", "License: MIT", "Encoding: UTF-8"
  ), file.path(pkg_dir, "DESCRIPTION"))

  writeLines('exportPattern("^[[:alpha:]]+")', file.path(pkg_dir, "NAMESPACE"))

  writeLines(c(
    "is_positive <- function(x) {",
    "  if (x > 0) { return(TRUE) }",
    "  FALSE",
    "}"
  ), file.path(pkg_dir, "R", "math.R"))

  writeLines(c(
    'test_that("is_positive works", {',
    '  expect_true(is_positive(1))',
    '  expect_false(is_positive(-1))',
    '  expect_false(is_positive(0))',
    '})'
  ), file.path(pkg_dir, "tests", "testthat", "test-math.R"))

  writeLines(c(
    'library(testthat)',
    'library(testpkg)',
    'test_check("testpkg")'
  ), file.path(pkg_dir, "tests", "testthat.R"))

  # Default iterate = FALSE
  utils::capture.output({
    results_default <- mutate_test(pkg_dir)
  }, type = "message")

  # Explicit iterate = FALSE
  utils::capture.output({
    results_explicit <- mutate_test(pkg_dir, iterate = FALSE)
  }, type = "message")

  expect_equal(results_default$outcome, results_explicit$outcome)

  unlink(pkg_dir, recursive = TRUE)
})

test_that("read_prior_results returns NULL on missing file", {
  tmp <- tempfile("no_json")
  dir.create(tmp)
  result <- mutantr:::read_prior_results(tmp)
  expect_null(result)
  unlink(tmp, recursive = TRUE)
})

test_that("read_prior_results returns NULL on malformed JSON", {
  tmp <- tempfile("bad_json")
  dir.create(tmp)
  writeLines("not json", file.path(tmp, "mutant_results.json"))
  result <- mutantr:::read_prior_results(tmp)
  expect_null(result)
  unlink(tmp, recursive = TRUE)
})

test_that("read_prior_results returns NULL on empty results", {
  tmp <- tempfile("empty_results")
  dir.create(tmp)
  empty_json <- jsonlite::toJSON(list(summary = list(total = 0), results = list()))
  writeLines(empty_json, file.path(tmp, "mutant_results.json"))
  result <- mutantr:::read_prior_results(tmp)
  expect_null(result)
  unlink(tmp, recursive = TRUE)
})

test_that("read_prior_results reads valid JSON", {
  tmp <- tempfile("valid_json")
  dir.create(tmp)
  df <- data.frame(
    file = c("math.R"), line = c(2L),
    original = c(">"), replacement = c("<="),
    outcome = c("caught"), stringsAsFactors = FALSE
  )
  report <- list(summary = list(total = 1, caught = 1), results = df)
  jsonlite::write_json(report, file.path(tmp, "mutant_results.json"),
                       pretty = TRUE, auto_unbox = TRUE)
  result <- mutantr:::read_prior_results(tmp)
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 1)
  expect_equal(result$outcome, "caught")
  unlink(tmp, recursive = TRUE)
})

test_that("filter_skipped_mutants partitions correctly", {
  prepared <- data.frame(
    file = c("a.R", "a.R", "b.R", "b.R", "c.R"),
    line = c(2L, 5L, 3L, 7L, 1L),
    original = c(">", "TRUE", "+", "==", "FALSE"),
    replacement = c("<=", "FALSE", "-", "!=", "TRUE"),
    mutated_content = c("x <=", "FALSE", "x -", "x !=", "TRUE"),
    stringsAsFactors = FALSE
  )

  prior <- data.frame(
    file = c("a.R", "a.R", "b.R", "b.R"),
    line = c(2, 5, 3, 10),
    original = c(">", "TRUE", "+", "=="),
    replacement = c("<=", "FALSE", "-", "!="),
    outcome = c("caught", "missed", "unviable", "timeout"),
    stringsAsFactors = FALSE
  )

  result <- mutantr:::filter_skipped_mutants(prepared, prior)

  # to_test should include:
  # - a.R:5 TRUE->FALSE (prior was "missed" — retest)
  # - b.R:7 ==->!= (no prior match — new mutant)
  # - c.R:1 FALSE->TRUE (no prior match — new mutant)
  expect_equal(nrow(result$to_test), 3)
  expect_true(all(
    paste(result$to_test$file, result$to_test$line) %in%
      c("a.R 5", "b.R 7", "c.R 1")
  ))

  # skipped should include:
  # - a.R:2 >-><= (prior was "caught")
  # - b.R:3 +->- (prior was "unviable")
  expect_equal(nrow(result$skipped), 2)
  expect_true(all(result$skipped$outcome %in% c("caught", "unviable")))
  expect_true(all(
    paste(result$skipped$file, result$skipped$line) %in%
      c("a.R 2", "b.R 3")
  ))
})

test_that("filter_skipped_mutants coerces line to integer", {
  prepared <- data.frame(
    file = "a.R", line = 2L,
    original = ">", replacement = "<=",
    mutated_content = "x <=",
    stringsAsFactors = FALSE
  )

  # line is numeric (as from JSON round-trip)
  prior <- data.frame(
    file = "a.R", line = 2.0,
    original = ">", replacement = "<=",
    outcome = "caught",
    stringsAsFactors = FALSE
  )

  result <- mutantr:::filter_skipped_mutants(prepared, prior)
  expect_equal(nrow(result$to_test), 0)
  expect_equal(nrow(result$skipped), 1)
})

test_that("iterate skips previously caught mutants and merges prior outcomes", {
  # ——— First run: catch all mutants ———
  pkg_dir <- tempfile("testpkg")
  dir.create(pkg_dir)
  dir.create(file.path(pkg_dir, "R"))
  dir.create(file.path(pkg_dir, "tests", "testthat"), recursive = TRUE)

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

  # Full test suite — catches all 4 mutants
  writeLines(c(
    'test_that("is_positive works", {',
    '  expect_true(is_positive(1))',
    '  expect_false(is_positive(-1))',
    '  expect_false(is_positive(0))',
    '})'
  ), file.path(pkg_dir, "tests", "testthat", "test-math.R"))

  writeLines(c(
    'library(testthat)',
    'library(testpkg)',
    'test_check("testpkg")'
  ), file.path(pkg_dir, "tests", "testthat.R"))

  out_dir <- tempfile("iterate_results")
  dir.create(out_dir)

  # First run
  utils::capture.output({
    results1 <- mutate_test(pkg_dir, output_dir = out_dir)
  }, type = "message")

  # Verify all caught
  expect_true(all(results1$outcome == "caught"),
              info = "First run should catch all mutants")
  n_total <- nrow(results1)

  # ——— Between runs: add file with new mutants ———
  writeLines(c(
    "is_even <- function(x) {",
    "  x %% 2 == 0",
    "}"
  ), file.path(pkg_dir, "R", "utils.R"))

  # ——— Weaken existing test: remove assertions that catch FALSE->TRUE ———
  writeLines(c(
    'test_that("is_positive works", {',
    '  expect_true(is_positive(1))',
    '})'
  ), file.path(pkg_dir, "tests", "testthat", "test-math.R"))

  # ——— Second run with iterate=TRUE ———
  utils::capture.output({
    results2 <- mutate_test(pkg_dir, output_dir = out_dir, iterate = TRUE)
  }, type = "message")

  # Total prepared should be n_total + utils.R mutants
  utils::capture.output({
    results_full <- mutate_test(pkg_dir)
  }, type = "message")
  n_prepared <- nrow(results_full)

  # (1) Previously-caught FALSE->TRUE mutant remains "caught" (not re-tested)
  false_to_true <- results2[results2$original == "FALSE" & results2$replacement == "TRUE", ]
  expect_true(nrow(false_to_true) >= 1,
              info = "Should have FALSE->TRUE mutant in results")
  expect_equal(false_to_true$outcome[1], "caught",
               info = "Previously-caught FALSE->TRUE should remain caught (from prior)")

  # (2) Row completeness: nrow(results2) == n_prepared
  expect_equal(nrow(results2), n_prepared,
               info = "Results should include all prepared mutants (skipped + tested)")

  # (3) JSON contains all mutants (skipped + tested)
  json_path <- file.path(out_dir, "mutant_results.json")
  expect_true(file.exists(json_path))
  json_data <- jsonlite::fromJSON(json_path)
  expect_equal(nrow(json_data$results), n_prepared,
               info = "JSON should contain all mutants (skipped + tested)")

  unlink(pkg_dir, recursive = TRUE)
  unlink(out_dir, recursive = TRUE)
})

test_that("iterate with empty prior results runs all mutants", {
  pkg_dir <- tempfile("testpkg")
  dir.create(pkg_dir)
  dir.create(file.path(pkg_dir, "R"))
  dir.create(file.path(pkg_dir, "tests", "testthat"), recursive = TRUE)

  writeLines(c(
    "Package: testpkg", "Title: Test Package", "Version: 0.0.1",
    "Description: A test package.", "License: MIT", "Encoding: UTF-8"
  ), file.path(pkg_dir, "DESCRIPTION"))

  writeLines('exportPattern("^[[:alpha:]]+")', file.path(pkg_dir, "NAMESPACE"))

  writeLines(c(
    "is_positive <- function(x) {",
    "  if (x > 0) { return(TRUE) }",
    "  FALSE",
    "}"
  ), file.path(pkg_dir, "R", "math.R"))

  writeLines(c(
    'test_that("is_positive works", {',
    '  expect_true(is_positive(1))',
    '  expect_false(is_positive(-1))',
    '  expect_false(is_positive(0))',
    '})'
  ), file.path(pkg_dir, "tests", "testthat", "test-math.R"))

  writeLines(c(
    'library(testthat)',
    'library(testpkg)',
    'test_check("testpkg")'
  ), file.path(pkg_dir, "tests", "testthat.R"))

  out_dir <- tempfile("empty_prior")
  dir.create(out_dir)

  # Write JSON with empty results
  empty_json <- jsonlite::toJSON(list(
    summary = list(total = 0, caught = 0, missed = 0, unviable = 0, timeout = 0),
    results = list()
  ))
  writeLines(empty_json, file.path(out_dir, "mutant_results.json"))

  expect_warning(
    {
      utils::capture.output({
        results <- mutate_test(pkg_dir, output_dir = out_dir, iterate = TRUE)
      }, type = "message")
    },
    "Could not read prior results", fixed = TRUE
  )

  expect_s3_class(results, "data.frame")
  expect_gt(nrow(results), 0)

  unlink(pkg_dir, recursive = TRUE)
  unlink(out_dir, recursive = TRUE)
})

test_that("iterate retests previously missed mutants", {
  # ——— First run with weak tests: miss at least one mutant ———
  # The function has a FALSE return literal that a weak test never exercises.
  # The FALSE -> TRUE mutation is MISSED because is_positive(1) returns at
  # line 3 (TRUE branch) and never reaches line 5.
  pkg_dir <- tempfile("testpkg")
  dir.create(pkg_dir)
  dir.create(file.path(pkg_dir, "R"))
  dir.create(file.path(pkg_dir, "tests", "testthat"), recursive = TRUE)

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

  # Weak test: only tests x=1, which takes the TRUE branch at line 3.
  # The FALSE -> TRUE mutant on line 5 is never reached, so it's "missed".
  # The > -> <= mutant on line 2 IS caught because 1 <= 0 is FALSE.
  writeLines(c(
    'test_that("is_positive works", {',
    '  expect_true(is_positive(1))',
    '})'
  ), file.path(pkg_dir, "tests", "testthat", "test-math.R"))

  writeLines(c(
    'library(testthat)',
    'library(testpkg)',
    'test_check("testpkg")'
  ), file.path(pkg_dir, "tests", "testthat.R"))

  out_dir <- tempfile("retest_results")
  dir.create(out_dir)

  # First run
  utils::capture.output({
    results1 <- mutate_test(pkg_dir, output_dir = out_dir)
  }, type = "message")

  # At least one mutant should be "missed" with the weak test
  expect_true(any(results1$outcome == "missed"),
              info = "Weak test should miss at least one mutant")

  # The FALSE -> TRUE mutation should be missed specifically
  false_to_true <- results1[
    results1$original == "FALSE" & results1$replacement == "TRUE", ]
  expect_true(nrow(false_to_true) >= 1,
              info = "FALSE -> TRUE mutant should exist")
  expect_equal(false_to_true$outcome[1], "missed",
               info = paste0("FALSE -> TRUE should be missed with weak test",
                             " (is_positive(1) never reaches line 5)"))

  # ——— Strengthen tests to catch the missed mutant ———
  # Adding expect_false(is_positive(-1)) triggers the FALSE -> TRUE mutation
  # because is_positive(-1) falls through to line 5, which is now TRUE.
  writeLines(c(
    'test_that("is_positive works", {',
    '  expect_true(is_positive(1))',
    '  expect_false(is_positive(-1))',
    '})'
  ), file.path(pkg_dir, "tests", "testthat", "test-math.R"))

  # ——— Second run with iterate=TRUE ———
  utils::capture.output({
    results2 <- mutate_test(pkg_dir, output_dir = out_dir, iterate = TRUE)
  }, type = "message")

  # The previously-missed FALSE -> TRUE mutant should now be "caught"
  false_to_true2 <- results2[
    results2$original == "FALSE" & results2$replacement == "TRUE", ]
  expect_true(nrow(false_to_true2) >= 1,
              info = "Should have FALSE -> TRUE mutant in second results")
  expect_equal(false_to_true2$outcome[1], "caught",
               info = paste0("Previously-missed FALSE -> TRUE should now be caught",
                             " after test strengthening"))

  unlink(pkg_dir, recursive = TRUE)
  unlink(out_dir, recursive = TRUE)
})
