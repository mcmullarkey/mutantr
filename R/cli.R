# CLI helper functions for mutantr
#
# This module provides the CLI entry point helper functions used by
# inst/bin/mutantr. It does NOT perform mutation scanning — that is
# the responsibility of mutate_test() and the Rust backend.
#
# What it DOES:
#   - Parse command-line arguments (--flag=value and --flag value)
#   - Validate parsed arguments (dir.exists, numeric coercion)
#   - Compute CI exit codes (0=all caught, 1=missed, 2=error)
#   - Orchestrate the CLI lifecycle
#
# What it does NOT do:
#   - Perform mutation testing itself
#   - Write reports (handled by write_json_report / write_md_report)
#   - Print detailed per-mutant progress (handled by mutate_test)

#' Parse command-line arguments
#'
#' Pure function. Takes the result of \code{commandArgs(TRUE)} and returns
#' a named list. Supports both \code{--flag=value} and \code{--flag value}
#' forms. Unknown flags trigger an error with the flag name in the message.
#'
#' @param args Character vector from \code{commandArgs(TRUE)}
#' @return A named list with fields: pkg, timeout, workers, output_dir,
#'   iterate, in_diff, help, version
#' @noRd
parse_args <- function(args) {
  known_flags <- c(
    "--pkg", "--timeout", "--workers", "--output-dir",
    "--iterate", "--in-diff", "--help", "--version"
  )

  flag_to_name <- c(
    "--pkg" = "pkg",
    "--timeout" = "timeout",
    "--workers" = "workers",
    "--output-dir" = "output_dir",
    "--iterate" = "iterate",
    "--in-diff" = "in_diff",
    "--help" = "help",
    "--version" = "version"
  )

  boolean_flags <- c("--iterate", "--in-diff", "--help", "--version")

  result <- list(
    pkg = NULL, timeout = NULL, workers = NULL, output_dir = NULL,
    iterate = FALSE, in_diff = FALSE, help = FALSE, version = FALSE
  )

  i <- 1L
  while (i <= length(args)) {
    arg <- args[i]

    if (!grepl("^--", arg)) {
      stop("Unexpected argument: ", arg, call. = FALSE)
    }

    # Check for --flag=value form
    eq_pos <- regexpr("=", arg, fixed = TRUE)
    if (eq_pos > 0) {
      flag <- substring(arg, 1L, eq_pos - 1L)
      value <- substring(arg, eq_pos + 1L)
    } else {
      flag <- arg
      value <- NULL
    }

    if (!(flag %in% known_flags)) {
      stop("Unknown flag: ", flag, call. = FALSE)
    }

    name <- unname(flag_to_name[flag])

    if (flag %in% boolean_flags) {
      result[[name]] <- TRUE
      i <- i + 1L
    } else if (!is.null(value)) {
      result[[name]] <- value
      i <- i + 1L
    } else {
      # Value flag without inline value — next arg is the value
      if (i + 1L > length(args)) {
        stop("Flag ", flag, " requires a value", call. = FALSE)
      }
      if (grepl("^--", args[i + 1L])) {
        stop("Flag ", flag, " requires a value", call. = FALSE)
      }
      result[[name]] <- args[i + 1L]
      i <- i + 2L
    }
  }

  result
}


#' Validate parsed CLI arguments
#'
#' Pure function. Checks:
#' \itemize{
#'   \item \code{pkg} is provided and \code{dir.exists(pkg)} is true
#'   \item \code{timeout} is numeric if provided
#'   \item \code{workers} is integer if provided
#' }
#' Returns a validated list with default values filled in, or stops with an
#' error message.
#'
#' @param parsed Named list from \code{parse_args()}
#' @return A validated named list with defaults applied
#' @noRd
validate_args <- function(parsed) {
  validated <- parsed

  # --pkg is required and must exist
  if (is.null(parsed$pkg) || nchar(parsed$pkg) == 0L) {
    stop("--pkg is required and must be a valid directory path", call. = FALSE)
  }
  if (!dir.exists(parsed$pkg)) {
    stop("Package directory does not exist: ", parsed$pkg, call. = FALSE)
  }
  validated$pkg <- parsed$pkg

  # --timeout: validate if supplied, leave NULL to let mutate_test() merge config/defaults
  if (!is.null(parsed$timeout)) {
    timeout_num <- suppressWarnings(as.numeric(parsed$timeout))
    if (is.na(timeout_num)) {
      stop("--timeout must be numeric, got: ", parsed$timeout, call. = FALSE)
    }
    if (timeout_num <= 0) {
      stop("--timeout must be positive, got: ", timeout_num, call. = FALSE)
    }
    validated$timeout <- timeout_num
  }
  # else: validated$timeout stays NULL (from validated <- parsed)

  # --workers: validate if supplied, leave NULL to let mutate_test() merge config/defaults
  if (!is.null(parsed$workers)) {
    workers_int <- suppressWarnings(as.integer(parsed$workers))
    if (is.na(workers_int)) {
      stop("--workers must be an integer, got: ", parsed$workers, call. = FALSE)
    }
    if (workers_int < 1L) {
      stop("--workers must be >= 1, got: ", workers_int, call. = FALSE)
    }
    validated$workers <- workers_int
  }
  # else: validated$workers stays NULL (from validated <- parsed)

  # --output-dir: optional, NULL if empty
  if (is.null(parsed$output_dir) || nchar(parsed$output_dir) == 0L) {
    validated$output_dir <- NULL
  }

  validated
}


#' Compute CI exit code from mutation test results
#'
#' Pure function. Maps mutation test results to an exit code:
#' \itemize{
#'   \item 1 — if any mutant has outcome "missed"
#'   \item 0 — all mutants caught (or no mutants found)
#' }
#'
#' Errors (NULL results or missing outcome column) raise an error rather than
#' returning 2 — the caller (\code{cli_main}) wraps this in \code{tryCatch} to
#' produce exit code 2, maintaining the inversion guard.
#'
#' @param results Data frame returned by \code{mutate_test()}
#' @return Integer 0 or 1
#' @noRd
compute_exit_code <- function(results) {
  if (is.null(results) || !"outcome" %in% names(results)) {
    stop("Internal error: results lacks 'outcome' column", call. = FALSE)
  }
  if (sum(results$outcome == "missed") > 0L) {
    return(1L)
  }
  0L
}


#' Print CLI usage information
#' @noRd
print_usage <- function() {
  cat("Usage: mutantr --pkg <path> [options]\n")
  cat("\n")
  cat("Run mutation testing on an R package and exit with a CI-compatible\n")
  cat("exit code: 0 (all caught), 1 (missed > 0), 2 (error).\n")
  cat("\n")
  cat("Options:\n")
  cat("  --pkg <path>          Path to R package (required)\n")
  cat("  --timeout <secs>      Timeout per mutant test run (default: 30)\n")
  cat("  --workers <n>         Number of parallel workers (default: 1)\n")
  cat("  --output-dir <path>   Write JSON and Markdown reports to this directory\n")
  cat("  --iterate             (Not yet supported) Iteratively improve tests\n")
  cat("  --in-diff             (Not yet supported) Only test mutants in git diff\n")
  cat("  --help                Print this usage message and exit\n")
  cat("  --version             Print package version and exit\n")
}


#' CLI main entry point
#'
#' Effectful orchestrator. Parses arguments, validates, runs mutation testing,
#' prints summary, and exits with the appropriate CI exit code.
#'
#' Wraps \code{mutate_test()} in \code{tryCatch()} so that any error results
#' in exit code 2 (not exit code 1, which R's \code{stop()} would produce at
#' the Rscript level — this is the critical inversion guard).
#'
#' @param args Character vector from \code{commandArgs(TRUE)}
#' @return Never returns — calls \code{quit(status = )}
#' @noRd
cli_main <- function(args) {
  # Parse
  parsed <- tryCatch(
    parse_args(args),
    error = function(e) {
      message(e$message)
      quit(status = 2L)
    }
  )

  # Fast path: --help
  if (isTRUE(parsed$help)) {
    print_usage()
    quit(status = 0L)
  }

  # Fast path: --version
  if (isTRUE(parsed$version)) {
    cat(as.character(packageVersion("mutantr")), "\n")
    quit(status = 0L)
  }

  # Forward-compatible flags: warn but don't forward yet
  if (isTRUE(parsed$iterate)) {
    message("Warning: --iterate is not yet supported; ignored.")
  }
  if (isTRUE(parsed$in_diff)) {
    message("Warning: --in-diff is not yet supported; ignored.")
  }

  # Validate
  validated <- tryCatch(
    validate_args(parsed),
    error = function(e) {
      message(e$message)
      quit(status = 2L)
    }
  )

  # Run mutation testing with error guard
  error <- NULL
  results <- tryCatch(
    mutate_test(
      pkg_path = validated$pkg,
      timeout = validated$timeout,
      workers = validated$workers,
      output_dir = validated$output_dir
    ),
    error = function(e) {
      error <<- e
      NULL
    }
  )

  if (!is.null(error)) {
    message("Error during mutation testing: ", error$message)
    quit(status = 2L)
  }

  # Compute and return exit code
  # Wrapped in tryCatch so that stop() inside compute_exit_code (NULL results
  # or missing outcome column) produces exit 2, NOT exit 1 — the inversion
  # guard ensures errors are never conflated with "missed > 0".
  exit_code <- tryCatch(
    compute_exit_code(results),
    error = function(e) {
      message(e$message)
      2L
    }
  )
  quit(status = exit_code)
}
