# Tests for .mutantr.toml config file support
#
# Tests read_config() directly (via mutantr:::) and mutate_test() end-to-end
# with config files in the package root.

# ---- read_config unit tests ----

test_that("read_config returns flat list from valid TOML", {
  tmp <- tempfile("cfg_test_")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  writeLines(c(
    'timeout = 60',
    'workers = 2',
    'output_dir = "/tmp/reports"',
    'exclude = ["old.R", "deprecated.R"]',
    'iterate = true',
    'in_diff = "main"'
  ), file.path(tmp, ".mutantr.toml"))

  cfg <- mutantr:::read_config(tmp)

  expect_type(cfg, "list")
  expect_named(cfg)
  expect_equal(cfg$timeout, 60)
  expect_equal(cfg$workers, 2)
  expect_equal(cfg$output_dir, "/tmp/reports")
  expect_equal(cfg$exclude, c("old.R", "deprecated.R"))
  expect_true(cfg$iterate)
  expect_equal(cfg$in_diff, "main")
})

test_that("read_config errors on malformed TOML with filename", {
  tmp <- tempfile("cfg_malformed_")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  # Malformed TOML: unterminated array
  writeLines(c(
    'timeout = [60'
  ), file.path(tmp, ".mutantr.toml"))

  expect_error(
    mutantr:::read_config(tmp),
    ".mutantr.toml"
  )
})

test_that("read_config returns empty list for empty file", {
  tmp <- tempfile("cfg_empty_")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  writeLines(character(0), file.path(tmp, ".mutantr.toml"))

  cfg <- mutantr:::read_config(tmp)
  expect_type(cfg, "list")
  expect_length(cfg, 0)
})

test_that("read_config accepts unknown keys without error", {
  tmp <- tempfile("cfg_unknown_")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  writeLines(c(
    'timeout = 45',
    'future_feature_x = "hello"',
    'another_unknown = 42'
  ), file.path(tmp, ".mutantr.toml"))

  cfg <- mutantr:::read_config(tmp)

  expect_type(cfg, "list")
  expect_equal(cfg$timeout, 45)
  expect_equal(cfg$future_feature_x, "hello")
  expect_equal(cfg$another_unknown, 42)
})

test_that("read_config returns empty list when no file exists", {
  tmp <- tempfile("cfg_nofile_")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  cfg <- mutantr:::read_config(tmp)
  expect_type(cfg, "list")
  expect_length(cfg, 0)
})

test_that("read_config errors on type-mismatched values", {
  tmp <- tempfile("cfg_typemismatch_")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  # workers as string instead of numeric
  writeLines(c(
    'workers = "2"'
  ), file.path(tmp, ".mutantr.toml"))

  expect_error(
    mutantr:::read_config(tmp),
    "workers.*must be numeric"
  )
})

test_that("read_config errors on type-mismatched logical", {
  tmp <- tempfile("cfg_typemismatch2_")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  # iterate as string instead of logical
  writeLines(c(
    'iterate = "yes"'
  ), file.path(tmp, ".mutantr.toml"))

  expect_error(
    mutantr:::read_config(tmp),
    "iterate.*must be logical"
  )
})

test_that("read_config errors on type-mismatched output_dir", {
  tmp <- tempfile("cfg_typemismatch3_")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  # output_dir as number instead of character
  writeLines(c(
    'output_dir = 123'
  ), file.path(tmp, ".mutantr.toml"))

  expect_error(
    mutantr:::read_config(tmp),
    "output_dir.*must be character"
  )
})

test_that("read_config errors on scalar key with multi-element array", {
  tmp <- tempfile("cfg_scalar_array_")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  # timeout as multi-element array instead of scalar
  writeLines(c(
    'timeout = [60, 30]'
  ), file.path(tmp, ".mutantr.toml"))

  expect_error(
    mutantr:::read_config(tmp),
    "timeout.*must be a scalar"
  )
})

# ---- mutate_test integration tests with config ----

test_that("mutate_test uses config values when no explicit args", {
  skip_if_not_installed("mutantr")
  # Create a minimal package with a .mutantr.toml config
  pkg_dir <- tempfile("testpkg_cfg")
  dir.create(pkg_dir)
  dir.create(file.path(pkg_dir, "R"))
  dir.create(file.path(pkg_dir, "tests", "testthat"), recursive = TRUE)

  writeLines(c(
    "Package: testpkgcfg",
    "Title: Test Package",
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
    'library(testpkgcfg)',
    'test_check("testpkgcfg")'
  ), file.path(pkg_dir, "tests", "testthat.R"))

  # Set output_dir in config (no explicit output_dir arg to mutate_test)
  cfg_dir <- tempfile("cfg_output")
  writeLines(c(
    sprintf('output_dir = "%s"', cfg_dir)
  ), file.path(pkg_dir, ".mutantr.toml"))

  # Call mutate_test without explicit output_dir — config should apply
  results <- mutantr::mutate_test(pkg_dir)

  # Reports should exist in the config-specified directory
  expect_true(file.exists(file.path(cfg_dir, "mutant_results.json")))
  expect_true(file.exists(file.path(cfg_dir, "mutant_results.md")))

  unlink(pkg_dir, recursive = TRUE)
  unlink(cfg_dir, recursive = TRUE)
})

test_that("mutate_test explicit args override config", {
  skip_if_not_installed("mutantr")
  # Create a minimal package with a .mutantr.toml config
  pkg_dir <- tempfile("testpkg_cfg2")
  dir.create(pkg_dir)
  dir.create(file.path(pkg_dir, "R"))
  dir.create(file.path(pkg_dir, "tests", "testthat"), recursive = TRUE)

  writeLines(c(
    "Package: testpkgcfg2",
    "Title: Test Package",
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
    'library(testpkgcfg2)',
    'test_check("testpkgcfg2")'
  ), file.path(pkg_dir, "tests", "testthat.R"))

  # Set output_dir in config
  cfg_dir <- tempfile("cfg_output_ignored")
  writeLines(c(
    sprintf('output_dir = "%s"', cfg_dir)
  ), file.path(pkg_dir, ".mutantr.toml"))

  # Explicit output_dir — should override config
  explicit_dir <- tempfile("cfg_explicit")
  results <- mutantr::mutate_test(pkg_dir, output_dir = explicit_dir)

  # Reports should be in the explicit dir, NOT the config dir
  expect_true(file.exists(file.path(explicit_dir, "mutant_results.json")))
  expect_true(file.exists(file.path(explicit_dir, "mutant_results.md")))
  expect_false(file.exists(file.path(cfg_dir, "mutant_results.json")))

  unlink(pkg_dir, recursive = TRUE)
  unlink(cfg_dir, recursive = TRUE)
  unlink(explicit_dir, recursive = TRUE)
})

test_that("mutate_test with config workers works same as serial", {
  skip_if_not_installed("mutantr")
  # Create a minimal package with a .mutantr.toml config that sets workers = 2
  pkg_dir <- tempfile("testpkg_cfg3")
  dir.create(pkg_dir)
  dir.create(file.path(pkg_dir, "R"))
  dir.create(file.path(pkg_dir, "tests", "testthat"), recursive = TRUE)

  writeLines(c(
    "Package: testpkgcfg3",
    "Title: Test Package",
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
    'library(testpkgcfg3)',
    'test_check("testpkgcfg3")'
  ), file.path(pkg_dir, "tests", "testthat.R"))

  # Set workers = 2 in config
  writeLines("workers = 2", file.path(pkg_dir, ".mutantr.toml"))

  # Without explicit workers, config value (2) should be used
  # Compare with explicit workers = 1
  results_serial <- mutantr::mutate_test(pkg_dir, workers = 1)
  results_config <- mutantr::mutate_test(pkg_dir)

  serial_sorted <- results_serial[order(results_serial$file, results_serial$line, results_serial$replacement), ]
  config_sorted <- results_config[order(results_config$file, results_config$line, results_config$replacement), ]
  expect_equal(serial_sorted$outcome, config_sorted$outcome)

  unlink(pkg_dir, recursive = TRUE)
})

test_that("validate_args leaves timeout/workers/output_dir NULL when not supplied", {
  # Simulate parse_args output when no --timeout, --workers, --output-dir flags
  parsed <- list(
    pkg = tempdir(),          # exists
    timeout = NULL,
    workers = NULL,
    output_dir = NULL,
    iterate = FALSE,
    in_diff = FALSE,
    help = FALSE,
    version = FALSE
  )

  validated <- mutantr:::validate_args(parsed)

  expect_null(validated$timeout, "timeout should be NULL when not supplied")
  expect_null(validated$workers, "workers should be NULL when not supplied")
  expect_null(validated$output_dir, "output_dir should be NULL when not supplied")
})

test_that("CLI + config: NULL args from CLI let config apply through mutate_test", {
  skip_if_not_installed("mutantr")

  # Create a minimal package with passing tests
  pkg_dir <- tempfile("cli_cfg_testpkg")
  dir.create(pkg_dir)
  dir.create(file.path(pkg_dir, "R"))
  dir.create(file.path(pkg_dir, "tests", "testthat"), recursive = TRUE)
  on.exit(unlink(pkg_dir, recursive = TRUE), add = TRUE)

  writeLines(c(
    "Package: clicfgtest",
    "Title: CLI Config Test",
    "Version: 0.0.1",
    "Description: A test package for CLI+config integration.",
    "License: MIT",
    "Encoding: UTF-8"
  ), file.path(pkg_dir, "DESCRIPTION"))

  writeLines(
    'exportPattern("^[[:alpha:]]+")',
    file.path(pkg_dir, "NAMESPACE")
  )

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
    'library(clicfgtest)',
    'test_check("clicfgtest")'
  ), file.path(pkg_dir, "tests", "testthat.R"))

  # Set output_dir in config
  cfg_dir <- tempfile("cli_cfg_output")
  on.exit(unlink(cfg_dir, recursive = TRUE), add = TRUE)

  writeLines(sprintf('output_dir = "%s"', cfg_dir),
             file.path(pkg_dir, ".mutantr.toml"))

  # Simulate the CLI pipeline: parse_args → validate_args → mutate_test
  # This is exactly what cli_main does, minus the quit() call.
  parsed <- mutantr:::parse_args(c("--pkg", pkg_dir))
  validated <- mutantr:::validate_args(parsed)

  # Pass the (potentially NULL) validated args through to mutate_test
  results <- mutantr::mutate_test(
    pkg_path = validated$pkg,
    timeout = validated$timeout,
    workers = validated$workers,
    output_dir = validated$output_dir
  )

  # Files should exist in the config-specified directory
  expect_true(file.exists(file.path(cfg_dir, "mutant_results.json")))
  expect_true(file.exists(file.path(cfg_dir, "mutant_results.md")))
})
