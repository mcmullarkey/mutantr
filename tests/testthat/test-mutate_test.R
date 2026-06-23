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

test_that("unviable_source_error: source/load errors classified as unviable not caught", {
  # Create a package with two files:
  #   guard.R — has a stopifnot guard on the function result (source-time check)
  #   mult.R  — has a stopifnot guard on the function result (source-time check)
  # When mutations change the comparison in stopifnot(), source() fails.
  # Previously these were mis-classified as "caught", inflating the score.
  pkg_dir <- tempfile("testpkg")
  dir.create(pkg_dir)
  dir.create(file.path(pkg_dir, "R"))
  dir.create(file.path(pkg_dir, "tests", "testthat"), recursive = TRUE)

  writeLines(c(
    "Package: testpkg", "Title: Test Package", "Version: 0.0.1",
    "Description: A test package.", "License: MIT", "Encoding: UTF-8"
  ), file.path(pkg_dir, "DESCRIPTION"))

  writeLines('exportPattern("^[[:alpha:]]+")', file.path(pkg_dir, "NAMESPACE"))

  # guard.R: + (Arithmetic) and == (Comparison)
  #   == mutation → stopifnot(FALSE) → source error → unviable
  #   numeric literal mutation → guard result flips → source error → unviable
  #   +  mutation → function body change → tests fail → caught
  writeLines(c(
    "add <- function(x, y) { x + y }",
    "stopifnot(add(1, 2) == 3)"
  ), file.path(pkg_dir, "R", "guard.R"))

  # mult.R: * (Arithmetic) and == (Comparison)
  #   == mutation → stopifnot(FALSE) → source error → unviable
  #   numeric literal mutation → guard result flips → source error → unviable
  #   * mutation → function body change → tests fail → caught
  writeLines(c(
    "mult <- function(x, y) { x * y }",
    "stopifnot(mult(2, 3) == 6)"
  ), file.path(pkg_dir, "R", "mult.R"))

  # Tests that catch function body mutations but not guard mutations
  writeLines(c(
    'test_that("add works", {',
    '  expect_equal(add(1, 2), 3)',
    '  expect_equal(add(0, 0), 0)',
    '})',
    '',
    'test_that("mult works", {',
    '  expect_equal(mult(2, 3), 6)',
    '  expect_equal(mult(0, 5), 0)',
    '})'
  ), file.path(pkg_dir, "tests", "testthat", "test-math.R"))

  writeLines(c(
    'library(testthat)',
    'library(testpkg)',
    'test_check("testpkg")'
  ), file.path(pkg_dir, "tests", "testthat.R"))

  # Capture output to verify "unviable" appears in console
  # cli writes to stderr (message), so we capture both output and message
  output <- capture.output({
    results <- mutate_test(pkg_dir)
  }, type = "message")

  # (a) ≥1 row with outcome "unviable" AND ≥1 row with outcome "caught"
  expect_true(sum(results$outcome == "unviable") > 0,
              info = "Should have at least one unviable mutant")
  expect_true(sum(results$outcome == "caught") > 0,
              info = "Should have at least one caught mutant")

  # (b) unviable rows originate from guard-involved sites (line 2) OR from
  #     function-body sites (line 1) where the body mutation changes the
  #     function output such that the guard expression evaluates to FALSE
  #     at source-load time. Caught rows originate from function-body sites
  #     (line 1) where the body mutation changes function behavior but the
  #     guard still passes, so the test suite catches it.
  unviable <- results[results$outcome == "unviable", ]
  caught <- results[results$outcome == "caught", ]
  expect_true(any(unviable$line == 2),
              info = "At least some unviable mutants should be on guard/stopifnot lines (line 2)")
  expect_true(all(caught$line == 1),
              info = "Caught mutants should be on function-body lines (line 1)")
  # Guard-line mutations should ALL be unviable (tight == guard means any
  # change to a numeric literal or comparison operator flips the result)
  guard_line_unviable <- unviable[unviable$line == 2, ]
  expect_equal(nrow(guard_line_unviable),
               sum(results$line == 2),
               info = "All guard-line mutations should be unviable")

  # Now test with output_dir for JSON and MD report assertions
  out_dir <- tempfile("report_output")
  dir.create(out_dir)
  output2 <- capture.output({
    results2 <- mutate_test(pkg_dir, output_dir = out_dir)
  }, type = "message")

  json_path <- file.path(out_dir, "mutant_results.json")
  md_path <- file.path(out_dir, "mutant_results.md")

  json_data <- jsonlite::fromJSON(json_path)

  # (c) json_data$summary$unviable > 0
  expect_true(json_data$summary$unviable > 0,
              info = "JSON summary should have unviable > 0")

  # (d) MD report contains "## Unviable Mutants" detail section
  md_text <- paste(readLines(md_path), collapse = "\n")
  expect_true(grepl("## Unviable Mutants", md_text),
              info = "MD report should contain ## Unviable Mutants section")

  # (e) capture.output() includes "unviable"
  expect_true(any(grepl("unviable", output)),
              info = "Console output should contain 'unviable'")
  expect_true(any(grepl("unviable", output2)),
              info = "Console output (with output_dir) should contain 'unviable'")

  # (f) Correct totals: unviable > 0, caught > 0, total matches sum of parts
  expect_true(json_data$summary$unviable > 0,
              info = "JSON summary should have unviable > 0")
  expect_true(json_data$summary$caught > 0,
              info = "JSON summary should have caught > 0")
  expect_equal(json_data$summary$total,
               json_data$summary$unviable + json_data$summary$caught +
               json_data$summary$missed + json_data$summary$timeout,
               info = "Total should equal sum of all outcomes")

  # (g) No missed mutants: guard-stopifnot mutations are all unviable, not missed
  #     and mutation score should be 100% because all detectable mutants are caught
  expect_equal(json_data$summary$missed, 0,
               info = "Should have zero missed mutants — guard mutations are unviable, body mutations are caught")
  expect_equal(json_data$summary$mutation_score, 100,
               info = "Mutation score should be 100 — all caught or unviable, none missed")

  # (h) Unviable Mutants section lists mutants grouped by file
  expect_true(grepl("### `guard.R`", md_text),
              info = "MD report should list guard.R under Unviable Mutants")
  expect_true(grepl("### `mult.R`", md_text),
              info = "MD report should list mult.R under Unviable Mutants")

  unlink(pkg_dir, recursive = TRUE)
  unlink(out_dir, recursive = TRUE)
})

test_that("render_outcome_section produces byte-identical markdown", {
  df <- data.frame(
    file = c("a.R", "a.R", "b.R"),
    line = c(20L, 10L, 5L),
    original = c(">", "TRUE", "+"),
    replacement = c("<=", "FALSE", "-"),
    stringsAsFactors = FALSE
  )
  result <- mutantr:::render_outcome_section(df, "## Missed Mutants",
                                   c("Intro line 1.", "Intro line 2."))
  expected <- c(
    "## Missed Mutants", "",
    "Intro line 1.", "Intro line 2.", "",
    "### `a.R`", "",
    "| Line | Original | Mutated To |",
    "|------|----------|------------|",
    "| 20 | `>` | `<=` |",
    "| 10 | `TRUE` | `FALSE` |", "",
    "### `b.R`", "",
    "| Line | Original | Mutated To |",
    "|------|----------|------------|",
    "| 5 | `+` | `-` |", ""
  )
  expect_equal(result, expected)
})

test_that("write_md_report renders both sections via shared helper", {
  results_df <- data.frame(
    file = c("guard.R", "guard.R", "math.R"),
    line = c(2L, 4L, 10L),
    original = c("!=", ">", ">"),
    replacement = c("==", "<=", "<="),
    outcome = c("unviable", "unviable", "missed"),
    stringsAsFactors = FALSE
  )
  tmp <- tempfile("mdtest_")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  mutantr:::write_md_report(results_df, tmp)
  md <- paste(readLines(file.path(tmp, "mutant_results.md")), collapse = "\n")

  # (a) Section ordering: Unviable before Missed
  uv_pos <- regexpr("## Unviable Mutants", md, fixed = TRUE)[1]
  ms_pos <- regexpr("## Missed Mutants", md, fixed = TRUE)[1]
  expect_true(uv_pos > 0 && ms_pos > uv_pos,
    info = "Unviable section must appear before Missed section")

  # (b) Distinct intro text per section
  expect_true(grepl("package loading", md, fixed = TRUE),
    info = "Unviable intro must mention package loading")
  expect_true(grepl("not detected by the test suite", md, fixed = TRUE),
    info = "Missed intro must mention not detected by test suite")

  # (c) Per-file grouping
  expect_true(grepl("### `guard.R`", md, fixed = TRUE),
    info = "guard.R must appear as a per-file heading")
  expect_true(grepl("### `math.R`", md, fixed = TRUE),
    info = "math.R must appear as a per-file heading")

  # (d) Exact table rows
  expect_true(grepl("| 2 | `!=` | `==` |", md, fixed = TRUE),
    info = "Unviable mutant row must match exact format")
  expect_true(grepl("| 10 | `>` | `<=` |", md, fixed = TRUE),
    info = "Missed mutant row must match exact format")

  # (e) Table header appears exactly twice (once per file; one file per section in this fixture)
  hdr_matches <- gregexpr("| Line | Original | Mutated To |", md, fixed = TRUE)[[1]]
  expect_equal(length(hdr_matches), 2L,
    info = "Table header must appear exactly twice (once per file; one file per section in this fixture)")
})

test_that("render_outcome_section honors Does-NOT contracts", {
  # Does NOT filter: all input rows appear in output
  df <- data.frame(
    file = c("a.R", "a.R", "b.R"),
    line = c(20L, 10L, 5L),
    original = c(">", "TRUE", "+"),
    replacement = c("<=", "FALSE", "-"),
    stringsAsFactors = FALSE
  )
  result <- mutantr:::render_outcome_section(df, "## Missed Mutants",
                                   c("Intro line 1.", "Intro line 2."))
  expected_len <- 18L
  expect_length(result, expected_len)

  # Does NOT guard for nrow==0: returns header + intro, no file sections
  df_empty <- data.frame(
    file = character(0),
    line = integer(0),
    original = character(0),
    replacement = character(0),
    stringsAsFactors = FALSE
  )
  result_empty <- mutantr:::render_outcome_section(df_empty, "## Title", c("intro"))
  expect_equal(result_empty, c("## Title", "", "intro", ""))

})
