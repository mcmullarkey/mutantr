# Tests for diff filtering module (R/diff_filter.R)
#
# Tests parse_diff_ranges() and filter_mutations_by_diff() directly
# via mutantr::: (both are internal/not exported), plus integration
# test for mutate_test(in_diff = ...).

# ---- parse_diff_ranges unit tests ----

test_that("parse_diff_ranges: single file, single hunk", {
  tmp <- tempfile("diff_single_")
  writeLines(c(
    "diff --git a/R/foo.R b/R/foo.R",
    "index abc..def 100644",
    "--- a/R/foo.R",
    "+++ b/R/foo.R",
    "@@ -10,5 +10,7 @@",
    "unchanged",
    "+added line 1",
    "+added line 2"
  ), tmp)
  on.exit(unlink(tmp))

  result <- mutantr:::parse_diff_ranges(tmp)
  expect_s3_class(result, "data.frame")
  expect_equal(names(result), c("file", "line_start", "line_end"))
  expect_equal(nrow(result), 1)
  expect_equal(result$file, "foo.R")
  expect_equal(result$line_start, 10)
  expect_equal(result$line_end, 16)
})

test_that("parse_diff_ranges: multi-file diff", {
  tmp <- tempfile("diff_multi_")
  writeLines(c(
    "diff --git a/R/foo.R b/R/foo.R",
    "index abc..def 100644",
    "--- a/R/foo.R",
    "+++ b/R/foo.R",
    "@@ -1,3 +1,4 @@",
    " a",
    "+b",
    "diff --git a/R/bar.R b/R/bar.R",
    "index ghi..jkl 100644",
    "--- a/R/bar.R",
    "+++ b/R/bar.R",
    "@@ -5,2 +5,2 @@",
    "-old",
    "+new"
  ), tmp)
  on.exit(unlink(tmp))

  result <- mutantr:::parse_diff_ranges(tmp)
  expect_equal(nrow(result), 2)
  expect_equal(result$file, c("foo.R", "bar.R"))
  expect_equal(result$line_start, c(1, 5))
  expect_equal(result$line_end, c(4, 6))
})

test_that("parse_diff_ranges: multi-hunk file", {
  tmp <- tempfile("diff_multihunk_")
  writeLines(c(
    "diff --git a/R/foo.R b/R/foo.R",
    "index abc..def 100644",
    "--- a/R/foo.R",
    "+++ b/R/foo.R",
    "@@ -1,3 +1,4 @@",
    " a",
    "+b",
    "@@ -10,5 +10,6 @@",
    " unchanged",
    "+new line"
  ), tmp)
  on.exit(unlink(tmp))

  result <- mutantr:::parse_diff_ranges(tmp)
  expect_equal(nrow(result), 2)
  expect_true(all(result$file == "foo.R"))
  expect_equal(result$line_start, c(1, 10))
  expect_equal(result$line_end, c(4, 15))
})

test_that("parse_diff_ranges: omitted count format", {
  # @@ -3 +4,2 @@ means old_count=1 (omitted defaults to 1), new_count=2
  tmp <- tempfile("diff_omitcount_")
  writeLines(c(
    "diff --git a/R/foo.R b/R/foo.R",
    "index abc..def 100644",
    "--- a/R/foo.R",
    "+++ b/R/foo.R",
    "@@ -3 +4,2 @@",
    " unchanged",
    "+new line"
  ), tmp)
  on.exit(unlink(tmp))

  result <- mutantr:::parse_diff_ranges(tmp)
  expect_equal(nrow(result), 1)
  expect_equal(result$file, "foo.R")
  expect_equal(result$line_start, 4)
  expect_equal(result$line_end, 5)
})

test_that("parse_diff_ranges: zero new-count adds no range", {
  # @@ -3,2 +4,0 @@ means the entire hunk is a deletion — no new lines
  tmp <- tempfile("diff_zeronew_")
  writeLines(c(
    "diff --git a/R/foo.R b/R/foo.R",
    "index abc..def 100644",
    "--- a/R/foo.R",
    "+++ b/R/foo.R",
    "@@ -3,2 +4,0 @@",
    " -deleted_line1",
    " -deleted_line2"
  ), tmp)
  on.exit(unlink(tmp))

  result <- mutantr:::parse_diff_ranges(tmp)
  expect_equal(nrow(result), 0)
})

test_that("parse_diff_ranges: empty diff returns empty data.frame with correct types", {
  tmp <- tempfile("diff_empty_")
  writeLines(character(0), tmp)
  on.exit(unlink(tmp))

  result <- mutantr:::parse_diff_ranges(tmp)
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)
  expect_equal(ncol(result), 3)
  expect_equal(names(result), c("file", "line_start", "line_end"))
  # Check types are preserved even when empty
  expect_type(result$file, "character")
  expect_type(result$line_start, "integer")
  expect_type(result$line_end, "integer")
})

test_that("parse_diff_ranges: non-existent file errors", {
  expect_error(
    mutantr:::parse_diff_ranges("/nonexistent/path/to/diff"),
    "in_diff file not found: /nonexistent/path/to/diff"
  )
})

# ---- filter_mutations_by_diff unit tests ----

test_that("filter_mutations_by_diff: mutations on changed lines are included", {
  prepared <- data.frame(
    file = c("foo.R", "foo.R", "bar.R"),
    line = c(2L, 10L, 5L),
    original = c(">", "TRUE", "+"),
    replacement = c("<=", "FALSE", "-"),
    stringsAsFactors = FALSE
  )
  ranges <- data.frame(
    file = c("foo.R", "bar.R"),
    line_start = c(2L, 5L),
    line_end = c(4L, 5L),
    stringsAsFactors = FALSE
  )

  result <- mutantr:::filter_mutations_by_diff(prepared, ranges)
  expect_equal(nrow(result), 2)
  expect_true(all(paste(result$file, result$line) %in% c("foo.R 2", "bar.R 5")))
})

test_that("filter_mutations_by_diff: mutations on unchanged lines are excluded", {
  prepared <- data.frame(
    file = c("foo.R", "foo.R"),
    line = c(2L, 10L),
    original = c(">", "TRUE"),
    replacement = c("<=", "FALSE"),
    stringsAsFactors = FALSE
  )
  ranges <- data.frame(
    file = c("foo.R"),
    line_start = c(5L),
    line_end = c(15L),
    stringsAsFactors = FALSE
  )

  result <- mutantr:::filter_mutations_by_diff(prepared, ranges)
  expect_equal(nrow(result), 1)
  expect_equal(result$line, 10L)
})

test_that("filter_mutations_by_diff: line-level precision — not file-level", {
  # foo.R has both changed lines (line 2, 4) and unchanged lines (line 10)
  prepared <- data.frame(
    file = c("foo.R", "foo.R", "foo.R"),
    line = c(2L, 4L, 10L),
    original = c(">", "==", "TRUE"),
    replacement = c("<=", "!=", "FALSE"),
    stringsAsFactors = FALSE
  )
  ranges <- data.frame(
    file = c("foo.R"),
    line_start = c(2L),
    line_end = c(5L),
    stringsAsFactors = FALSE
  )

  result <- mutantr:::filter_mutations_by_diff(prepared, ranges)
  # Lines 2 and 4 are within [2, 5]; line 10 is outside
  expect_equal(nrow(result), 2)
  expect_true(all(result$line %in% c(2L, 4L)))
  expect_false(10L %in% result$line)
})

test_that("filter_mutations_by_diff: empty ranges returns empty result", {
  prepared <- data.frame(
    file = c("foo.R"),
    line = c(2L),
    original = c(">"),
    replacement = c("<="),
    stringsAsFactors = FALSE
  )
  ranges <- data.frame(
    file = character(0),
    line_start = integer(0),
    line_end = integer(0),
    stringsAsFactors = FALSE
  )

  result <- mutantr:::filter_mutations_by_diff(prepared, ranges)
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)
})

test_that("filter_mutations_by_diff: empty prepared returns empty result", {
  prepared <- data.frame(
    file = character(0),
    line = integer(0),
    original = character(0),
    replacement = character(0),
    stringsAsFactors = FALSE
  )
  ranges <- data.frame(
    file = c("foo.R"),
    line_start = c(2L),
    line_end = c(5L),
    stringsAsFactors = FALSE
  )

  result <- mutantr:::filter_mutations_by_diff(prepared, ranges)
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)
})

# ---- Integration test: mutate_test(in_diff = ...) ----

test_that("mutate_test: in_diff filters to changed lines only (line-level precision)", {
  skip_if_not_installed("mutantr")
  library(mutantr)
  # Create a 3-file package (a.R, b.R, c.R), each with 3 mutation-bearing lines
  pkg_dir <- tempfile("testpkg_indiff")
  dir.create(pkg_dir)
  dir.create(file.path(pkg_dir, "R"))
  dir.create(file.path(pkg_dir, "tests", "testthat"), recursive = TRUE)

  writeLines(c(
    "Package: testpkgid",
    "Title: Test Package for in_diff",
    "Version: 0.0.1",
    "Description: A test package.",
    "License: MIT",
    "Encoding: UTF-8"
  ), file.path(pkg_dir, "DESCRIPTION"))

  writeLines('exportPattern("^[[:alpha:]]+")', file.path(pkg_dir, "NAMESPACE"))

  # a.R: 3 lines with mutable operators (lines 1, 2, 3)
  # Each function returns TRUE or FALSE depending on input
  writeLines(c(
    "a_chk_gt <- function(x) x > 0",
    "a_chk_eq <- function(x) x == 0",
    "a_chk_lt <- function(x) x < 0"
  ), file.path(pkg_dir, "R", "a.R"))

  # b.R: 3 lines with mutable operators (lines 1, 2, 3)
  writeLines(c(
    "b_chk_gt <- function(x) x > 0",
    "b_chk_eq <- function(x) x == 0",
    "b_chk_lt <- function(x) x < 0"
  ), file.path(pkg_dir, "R", "b.R"))

  # c.R: 3 lines with mutable operators (lines 1, 2, 3)
  writeLines(c(
    "c_chk_gt <- function(x) x > 0",
    "c_chk_eq <- function(x) x == 0",
    "c_chk_lt <- function(x) x < 0"
  ), file.path(pkg_dir, "R", "c.R"))

  # Tests that catch all mutations
  writeLines(c(
    'test_that("all functions work", {',
    '  expect_true(a_chk_gt(1)); expect_false(a_chk_gt(0))',
    '  expect_true(a_chk_eq(0)); expect_false(a_chk_eq(1))',
    '  expect_true(a_chk_lt(-1)); expect_false(a_chk_lt(0))',
    '  expect_true(b_chk_gt(1)); expect_false(b_chk_gt(0))',
    '  expect_true(b_chk_eq(0)); expect_false(b_chk_eq(1))',
    '  expect_true(b_chk_lt(-1)); expect_false(b_chk_lt(0))',
    '  expect_true(c_chk_gt(1)); expect_false(c_chk_gt(0))',
    '  expect_true(c_chk_eq(0)); expect_false(c_chk_eq(1))',
    '  expect_true(c_chk_lt(-1)); expect_false(c_chk_lt(0))',
    '})'
  ), file.path(pkg_dir, "tests", "testthat", "test-all.R"))

  writeLines(c(
    'library(testthat)',
    'library(testpkgid)',
    'test_check("testpkgid")'
  ), file.path(pkg_dir, "tests", "testthat.R"))

  # Create a diff changing only a.R line 2 and all b.R lines (lines 1, 2, 3)
  # a.R: @@ -1,3 +1,3 @@  (lines 1-3 unchanged) then @@ -2,1 +2,1 @@ (line 2 changed)
  # Wait, we need a precise diff. Let's create it manually.
  # The diff format: a.R only line 2 changed, b.R lines 1-3 all changed
  diff_path <- tempfile("test_diff_")
  writeLines(c(
    "diff --git a/R/a.R b/R/a.R",
    "index abc..def 100644",
    "--- a/R/a.R",
    "+++ b/R/a.R",
    "@@ -2,1 +2,1 @@",
    "-a2 <- function(x) { if (x == 0) TRUE }",
    "+a2 <- function(x) { if (x != 0) TRUE }",
    "diff --git a/R/b.R b/R/b.R",
    "index ghi..jkl 100644",
    "--- a/R/b.R",
    "+++ b/R/b.R",
    "@@ -1,3 +1,3 @@",
    "-b1 <- function(x) { if (x > 0) TRUE }",
    "+b1 <- function(x) { if (x >= 0) TRUE }",
    "-b2 <- function(x) { if (x == 0) TRUE }",
    "+b2 <- function(x) { if (x != 0) TRUE }",
    "-b3 <- function(x) { if (x < 0) TRUE }",
    "+b3 <- function(x) { if (x <= 0) TRUE }"
  ), diff_path)

  # Run with in_diff filter
  results_filtered <- mutate_test(pkg_dir, in_diff = diff_path)

  # Assert: a.R line 2 included, a.R lines 1,3 excluded
  a_lines <- results_filtered$line[results_filtered$file == "a.R"]
  expect_true(2L %in% a_lines,
              info = "a.R line 2 should be included (changed line)")
  expect_false(1L %in% a_lines,
               info = "a.R line 1 should be excluded (unchanged line)")
  expect_false(3L %in% a_lines,
               info = "a.R line 3 should be excluded (unchanged line)")

  # Assert: b.R all lines included
  b_lines <- results_filtered$line[results_filtered$file == "b.R"]
  expect_true(all(c(1L, 2L, 3L) %in% b_lines),
              info = "All b.R lines should be included (all changed)")

  # Assert: c.R all excluded
  c_lines <- results_filtered$file == "c.R"
  expect_false(any(c_lines),
               info = "c.R should be excluded entirely (no changes)")

  # Assert: result is a strict subset of the full run (without in_diff)
  results_full <- mutate_test(pkg_dir)
  expect_true(nrow(results_full) > nrow(results_filtered),
              info = "Filtered results should be a strict subset of full results")

  # All filtered rows should appear in full results with same outcomes
  merged <- merge(results_filtered, results_full,
                  by = c("file", "line", "original", "replacement"))
  expect_equal(nrow(merged), nrow(results_filtered),
               info = "All filtered rows must exist in full results")
  expect_equal(merged$outcome.x, merged$outcome.y,
               info = "Filtered outcomes must match full outcomes")

  unlink(pkg_dir, recursive = TRUE)
  unlink(diff_path)
})

# ---- Backward compatibility test ----

test_that("mutate_test: in_diff = NULL produces identical results to not passing in_diff", {
  skip_if_not_installed("mutantr")
  library(mutantr)
  pkg_dir <- tempfile("testpkg_backcompat")
  dir.create(pkg_dir)
  dir.create(file.path(pkg_dir, "R"))
  dir.create(file.path(pkg_dir, "tests", "testthat"), recursive = TRUE)

  writeLines(c(
    "Package: testpkgbc",
    "Title: Test Package for backward compat",
    "Version: 0.0.1",
    "Description: A test package.",
    "License: MIT",
    "Encoding: UTF-8"
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

  writeLines(c(
    'test_that("is_positive works", {',
    '  expect_true(is_positive(1))',
    '  expect_false(is_positive(-1))',
    '  expect_false(is_positive(0))',
    '})'
  ), file.path(pkg_dir, "tests", "testthat", "test-math.R"))

  writeLines(c(
    'library(testthat)',
    'library(testpkgbc)',
    'test_check("testpkgbc")'
  ), file.path(pkg_dir, "tests", "testthat.R"))

  utils::capture.output({
    results_default <- mutate_test(pkg_dir)
  }, type = "message")

  utils::capture.output({
    results_explicit <- mutate_test(pkg_dir, in_diff = NULL)
  }, type = "message")

  expect_equal(results_default, results_explicit)

  unlink(pkg_dir, recursive = TRUE)
})
