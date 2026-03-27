test_that("mutate_test runs mutations against a package and classifies outcomes", {
  # Create a minimal R package with one function and one test
  pkg_dir <- tempfile("testpkg")
  dir.create(pkg_dir)
  dir.create(file.path(pkg_dir, "R"))
  dir.create(file.path(pkg_dir, "tests", "testthat"), recursive = TRUE)

  writeLines(c(
    "Package: testpkg",
    "Title: Test Package",
    "Version: 0.0.1",
    "Description: A test package.",
    "License: MIT",
    "Encoding: UTF-8"
  ), file.path(pkg_dir, "DESCRIPTION"))

  writeLines(c(
    'exportPattern("^[[:alpha:]]+")'
  ), file.path(pkg_dir, "NAMESPACE"))

  # A simple function with an == operator
  writeLines(c(
    "is_positive <- function(x) {",
    "  if (x > 0) {",
    "    return(TRUE)",
    "  }",
    "  FALSE",
    "}"
  ), file.path(pkg_dir, "R", "math.R"))

  # A test that should catch mutations to > and TRUE/FALSE
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

  # Run mutation testing
  results <- mutate_test(pkg_dir)

  # Should return a data frame with expected columns
  expect_s3_class(results, "data.frame")
  expect_true("outcome" %in% names(results))
  expect_true("file" %in% names(results))
  expect_true("original" %in% names(results))
  expect_true("replacement" %in% names(results))
  expect_true("line" %in% names(results))

  # Should have tested some mutations
  expect_gt(nrow(results), 0)

  # Outcomes should be one of: caught, missed, unviable, timeout
  expect_true(all(results$outcome %in% c("caught", "missed", "unviable", "timeout")))

  # The > -> <= mutation should be caught (test checks positive/negative/zero)
  caught <- results[results$outcome == "caught", ]
  expect_gt(nrow(caught), 0)

  # Clean up
  unlink(pkg_dir, recursive = TRUE)
})

test_that("mutate_test with workers > 1 produces same results", {
  pkg_dir <- tempfile("testpkg")
  dir.create(pkg_dir)
  dir.create(file.path(pkg_dir, "R"))
  dir.create(file.path(pkg_dir, "tests", "testthat"), recursive = TRUE)

  writeLines(c(
    "Package: testpkg",
    "Title: Test Package",
    "Version: 0.0.1",
    "Description: A test package.",
    "License: MIT",
    "Encoding: UTF-8"
  ), file.path(pkg_dir, "DESCRIPTION"))

  writeLines(c(
    'exportPattern("^[[:alpha:]]+")'
  ), file.path(pkg_dir, "NAMESPACE"))

  writeLines(c(
    "is_positive <- function(x) {",
    "  if (x > 0) {",
    "    return(TRUE)",
    "  }",
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

  results_serial <- mutate_test(pkg_dir, workers = 1)
  results_parallel <- mutate_test(pkg_dir, workers = 2)

  # Same outcomes regardless of worker count
  serial_sorted <- results_serial[order(results_serial$file, results_serial$line, results_serial$replacement), ]
  parallel_sorted <- results_parallel[order(results_parallel$file, results_parallel$line, results_parallel$replacement), ]
  expect_equal(serial_sorted$outcome, parallel_sorted$outcome)

  unlink(pkg_dir, recursive = TRUE)
})

test_that("mutate_test writes JSON and markdown reports when output_dir is set", {
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

  out_dir <- tempfile("report_output")
  dir.create(out_dir)
  results <- mutate_test(pkg_dir, output_dir = out_dir)

  # Return value unchanged
  expect_s3_class(results, "data.frame")
  expect_gt(nrow(results), 0)

  # JSON report exists and is valid
  json_path <- file.path(out_dir, "mutant_results.json")
  expect_true(file.exists(json_path))
  json_data <- jsonlite::fromJSON(json_path)
  expect_true("results" %in% names(json_data))
  expect_true("summary" %in% names(json_data))
  expect_equal(nrow(json_data$results), nrow(results))
  expect_true("total" %in% names(json_data$summary))
  expect_true("mutation_score" %in% names(json_data$summary))

  # Markdown report exists and has key sections
  md_path <- file.path(out_dir, "mutant_results.md")
  expect_true(file.exists(md_path))
  md_text <- paste(readLines(md_path), collapse = "\n")
  expect_true(grepl("# Mutation Testing Report", md_text))
  expect_true(grepl("## Summary", md_text))
  expect_true(grepl("| Metric", md_text))

  # If there are missed mutants, they should appear grouped by file
  missed <- results[results$outcome == "missed", ]
  if (nrow(missed) > 0) {
    expect_true(grepl("## Missed Mutants", md_text))
  }

  unlink(pkg_dir, recursive = TRUE)
  unlink(out_dir, recursive = TRUE)
})
