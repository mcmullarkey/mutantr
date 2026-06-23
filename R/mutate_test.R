#' @noRd
`%||%` <- function(x, y) if (is.null(x)) y else x

#' Run mutation testing on an R package
#'
#' Scans the package's R/ directory for mutation sites, applies each mutation
#' one at a time, runs the test suite, and classifies outcomes. Uses parallel
#' workers for speed: each worker gets one persistent copy of the package
#' and mutates files in-place (reverting after each test).
#'
#' If a \code{.mutantr.toml} config file exists in \code{pkg_path}, its values
#' are merged with the explicit arguments following this priority:
#' explicit args > config > defaults. Only keys that match function parameter
#' names (\code{timeout}, \code{workers}, \code{output_dir}, \code{iterate},
#' \code{in_diff}) are applied. Config keys for unimplemented features
#' (\code{exclude}) are accepted but silently ignored.
#'
#' When \code{iterate = TRUE}, the function reads prior results from
#' \code{output_dir/mutant_results.json} and skips mutants that were previously
#' classified as \code{"caught"} or \code{"unviable"}. Only mutants that were
#' previously \code{"missed"}, \code{"timeout"}, or are entirely new are
#' re-tested. Skipped mutants appear in the output with their prior outcome,
#' ensuring row completeness. This enables an iterative workflow: run mutation
#' testing, improve test coverage for missed mutants, and re-run with
#' \code{iterate = TRUE} to focus only on the remaining gaps.
#'
#' @param pkg_path Path to the root of an R package
#' @param timeout Timeout in seconds per mutant test run (default: 30)
#' @param workers Number of parallel workers (default: 1)
#' @param output_dir Optional directory path. When provided, writes
#'   \code{mutant_results.json} and \code{mutant_results.md} to this directory.
#'   Default NULL (no file output).
#' @param iterate Logical. If \code{TRUE}, skips previously caught/unviable
#'   mutants from \code{output_dir/mutant_results.json}. Requires
#'   \code{output_dir} to be set. Default \code{FALSE}.
#' @param in_diff Optional path to a unified diff file. When provided, only
#'   mutations on lines changed in the diff are tested. The diff file is parsed
#'   after the baseline test (baseline always runs regardless of filter).
#'   Line-level filtering (not file-level): a file partially covered by the diff
#'   only has its changed lines tested. Default \code{NULL} (no filtering).
#' @return A data frame with columns: file, line, original, replacement, outcome.
#'   The outcome column classifies each mutant as \code{"caught"} (test failure),
#'   \code{"missed"} (no test failure), \code{"unviable"} (source/load error,
#'   including missing files or bad R syntax), or \code{"timeout"}.
#' @export
mutate_test <- function(pkg_path, timeout = NULL, workers = NULL, output_dir = NULL,
                        iterate = NULL, in_diff = NULL) {
  pkg_path <- normalizePath(pkg_path, mustWork = TRUE)

  # Read .mutantr.toml config and merge with priority: explicit args > config > defaults
  config <- read_config(pkg_path)

  # Merge: explicit args (non-NULL) > config > defaults
  if (is.null(timeout)) timeout <- config$timeout %||% 30
  if (is.null(workers)) workers <- config$workers %||% 1
  if (is.null(output_dir)) output_dir <- config$output_dir
  if (is.null(iterate)) iterate <- config$iterate %||% FALSE
  if (is.null(in_diff)) in_diff <- config$in_diff

  # Validate iterate requires output_dir
  if (iterate && is.null(output_dir)) {
    stop("iterate = TRUE requires output_dir to be set")
  }

  # Batch-prepare all mutations in Rust (scan + apply in one call)
  prepared_json <- mutant_prepare_all(pkg_path)
  prepared <- jsonlite::fromJSON(prepared_json, simplifyDataFrame = TRUE)

  if (is.null(prepared) || nrow(prepared) == 0) {
    message("No mutation sites found.")
    return(data.frame(
      file = character(),
      line = integer(),
      original = character(),
      replacement = character(),
      outcome = character(),
      stringsAsFactors = FALSE
    ))
  }

  # If iterate = TRUE, filter out previously caught/unviable mutants
  skipped <- NULL
  if (iterate) {
    prior <- read_prior_results(output_dir)
    if (!is.null(prior)) {
      filtered <- filter_skipped_mutants(prepared, prior)
      to_test <- filtered$to_test
      skipped <- filtered$skipped
    } else {
      to_test <- prepared
    }
  } else {
    to_test <- prepared
  }

  # Run baseline test first to confirm tests pass unmutated
  baseline <- run_tests_in_copy(pkg_path, timeout = timeout)
  if (!baseline$passed) {
    stop("Baseline tests fail on unmutated package. Fix tests before mutation testing.")
  }
  baseline_time <- baseline$elapsed

  # Apply in_diff filter: restrict to_test to only lines changed in the diff
  if (!is.null(in_diff)) {
    ranges <- parse_diff_ranges(in_diff)
    to_test <- filter_mutations_by_diff(to_test, ranges)
  }

  # Calculate per-mutant timeout (5x baseline, minimum of timeout arg)
  mutant_timeout <- max(timeout, baseline_time * 5)

  n <- nrow(to_test)

  if (n > 0) {
    if (workers <= 1) {
      # Serial execution: single package copy, mutate-in-place, revert
      results <- run_mutations_serial(pkg_path, to_test, mutant_timeout)
    } else {
      # Parallel execution: one copy per worker, mclapply
      results <- run_mutations_parallel(pkg_path, to_test, mutant_timeout, workers)
    }

    out <- do.call(rbind, results)
    rownames(out) <- NULL
  } else {
    # No mutants to test (all skipped)
    out <- data.frame(
      file = character(),
      line = integer(),
      original = character(),
      replacement = character(),
      outcome = character(),
      stringsAsFactors = FALSE
    )
  }

  # Merge skipped mutants back into results (iterate mode)
  if (iterate && !is.null(skipped) && nrow(skipped) > 0) {
    out <- rbind(out, skipped)
    rownames(out) <- NULL
  }

  # Print summary
  counts <- table(out$outcome)
  cli::cli_h2("Mutation Testing Results")
  cli::cli_text("{nrow(out)} mutants tested")
  for (nm in names(counts)) {
    cli::cli_bullets(stats::setNames(paste0(counts[[nm]], " ", nm), "*"))
  }

  if (!is.null(output_dir)) {
    if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
    write_json_report(out, output_dir)
    write_md_report(out, output_dir)
  }

  out
}

#' Read prior mutation results from output_dir
#'
#' Reads \code{mutant_results.json} from \code{output_dir} and returns a
#' data.frame with columns (file, line, original, replacement, outcome).
#' Returns \code{NULL} if the file doesn't exist, is malformed, or has
#' zero rows — in all cases the caller should proceed with all mutants.
#'
#' @param output_dir Directory containing \code{mutant_results.json}
#' @return A data.frame or NULL
#' @noRd
read_prior_results <- function(output_dir) {
  json_path <- file.path(output_dir, "mutant_results.json")

  if (!file.exists(json_path)) {
    warning("No prior results found in ", output_dir, "; running all mutants")
    return(NULL)
  }

  data <- tryCatch(
    jsonlite::fromJSON(json_path),
    error = function(e) {
      warning("Could not read prior results; running all mutants")
      NULL
    }
  )

  if (is.null(data) || is.null(data$results)) {
    warning("Could not read prior results; running all mutants")
    return(NULL)
  }

  results <- data$results

  # Handle empty results (no rows) — fromJSON may return a named empty list
  # when the JSON has {"results": {}} so we check both cases
  if (!is.data.frame(results) || nrow(results) == 0) {
    warning("Could not read prior results; running all mutants")
    return(NULL)
  }

  # Verify required columns exist
  required_cols <- c("file", "line", "original", "replacement", "outcome")
  if (!all(required_cols %in% names(results))) {
    warning("Could not read prior results; running all mutants")
    return(NULL)
  }

  # Subset to required columns to prevent rbind(out, skipped) from breaking
  # if the JSON report schema ever grows extra columns
  results <- results[, required_cols]
  results
}

#' Filter prepared mutants against prior results
#'
#' Pure function. Partitions the \code{prepared} data.frame into mutants
#' that need testing (\code{to_test}) and mutants that can be skipped
#' (\code{skipped}) because they were previously caught or unviable.
#' Match key is the 4-tuple (file, line, original, replacement).
#'
#' \code{to_test} includes:
#' \itemize{
#'   \item New mutants (not found in prior)
#'   \item Previously missed or timed-out mutants (need re-testing)
#' }
#'
#' \code{skipped} includes prior results rows for mutants that were
#' previously caught or unviable and still exist in prepared.
#'
#' @param prepared Data.frame from prepare step with columns
#'   file, line, original, replacement, mutated_content
#' @param prior Data.frame from prior results with columns
#'   file, line, original, replacement, outcome
#' @return A list with \code{to_test} and \code{skipped} data.frames
#' @noRd
filter_skipped_mutants <- function(prepared, prior) {
  # Coerce line to integer on both sides for reliable matching
  prepared$line <- as.integer(prepared$line)
  prior$line <- as.integer(prior$line)

  # Create composite match keys
  prepared_key <- paste(prepared$file, prepared$line,
                        prepared$original, prepared$replacement, sep = "|||")
  prior_key <- paste(prior$file, prior$line,
                     prior$original, prior$replacement, sep = "|||")

  # Build lookup from key to prior outcome
  prior_outcome <- stats::setNames(prior$outcome, prior_key)

  # Match each prepared row to its prior outcome (NA if no match)
  matched_outcome <- prior_outcome[prepared_key]

  # Determine which prepared rows are skipped (caught or unviable in prior)
  skip_mask <- matched_outcome %in% c("caught", "unviable") & !is.na(matched_outcome)

  # to_test: prepared rows not in skipped set
  to_test <- prepared[!skip_mask, , drop = FALSE]
  rownames(to_test) <- NULL

  # skipped: prior rows matching the skipped prepared mutants
  skipped_keys <- prepared_key[skip_mask]
  skipped <- prior[prior_key %in% skipped_keys, , drop = FALSE]
  rownames(skipped) <- NULL

  list(to_test = to_test, skipped = skipped)
}

#' Write JSON mutation report
#' @noRd
write_json_report <- function(results_df, output_dir) {
  total <- nrow(results_df)
  caught <- sum(results_df$outcome == "caught")
  missed <- sum(results_df$outcome == "missed")
  unviable <- sum(results_df$outcome == "unviable")
  timeout <- sum(results_df$outcome == "timeout")
  testable <- caught + missed
  mutation_score <- if (testable > 0) round(100 * caught / testable, 1) else NA_real_

  report <- list(
    summary = list(
      total = total,
      caught = caught,
      missed = missed,
      unviable = unviable,
      timeout = timeout,
      mutation_score = mutation_score
    ),
    results = results_df
  )

  jsonlite::write_json(report, file.path(output_dir, "mutant_results.json"),
                       pretty = TRUE, auto_unbox = TRUE)
}
#' Render a markdown detail section for one mutation outcome
#'
#' Called as \code{render_outcome_section(df, title, intro_lines)} from
#' \code{write_md_report()} with a pre-filtered data frame.
#' Does NOT filter — the caller must pass a pre-filtered data frame.
#' Does NOT write to disk — returns a character vector.
#' Does NOT emit a leading blank line separator (caller's responsibility).
#' Does NOT guard for nrow(df)==0 (caller guards).
#'
#' @param df data.frame with columns file, line, original, replacement
#' @param title section heading, e.g. "## Missed Mutants"
#' @param intro_lines character vector of explanatory text (must be non-empty; caller supplies intro)
#' @return character vector of markdown lines
#' @noRd
render_outcome_section <- function(df, title, intro_lines) {
  lines <- c(title, "", intro_lines, "")
  for (f in unique(df$file)) {
    file_rows <- df[df$file == f, ]
    lines <- c(lines,
      sprintf("### `%s`", f), "",
      "| Line | Original | Mutated To |",
      "|------|----------|------------|"
    )
    for (i in seq_len(nrow(file_rows))) {
      r <- file_rows[i, ]
      lines <- c(lines, sprintf("| %d | `%s` | `%s` |", r$line, r$original, r$replacement))
    }
    lines <- c(lines, "")
  }
  lines
}

#' Write markdown mutation report
#' @noRd
write_md_report <- function(results_df, output_dir) {
  total <- nrow(results_df)
  caught <- sum(results_df$outcome == "caught")
  missed <- sum(results_df$outcome == "missed")
  unviable <- sum(results_df$outcome == "unviable")
  timeout <- sum(results_df$outcome == "timeout")
  testable <- caught + missed
  score <- if (testable > 0) round(100 * caught / testable, 1) else NA_real_

  pct <- function(n) if (total > 0) sprintf("%.1f%%", 100 * n / total) else "0%"

  lines <- c(
    "# Mutation Testing Report",
    "",
    "## Summary",
    "",
    "| Metric | Value |",
    "|--------|-------|",
    sprintf("| Total mutants | %d |", total),
    sprintf("| Caught | %d (%s) |", caught, pct(caught)),
    sprintf("| Missed | %d (%s) |", missed, pct(missed)),
    sprintf("| Unviable | %d (%s) |", unviable, pct(unviable)),
    sprintf("| Timeout | %d (%s) |", timeout, pct(timeout)),
    sprintf("| **Mutation score** | **%s** |",
            if (is.na(score)) "N/A" else paste0(score, "%"))
  )

  if (unviable > 0) {
    unviable_df <- results_df[results_df$outcome == "unviable", ]
    lines <- c(lines, "", render_outcome_section(unviable_df,
      "## Unviable Mutants",
      c("These mutations caused errors during package loading (source/load",
        "failure) and could not be tested. Common causes include modified",
        "guard expressions, broken R syntax, or missing files.")))
  }

  if (missed > 0) {
    missed_df <- results_df[results_df$outcome == "missed", ]
    lines <- c(lines, "", render_outcome_section(missed_df,
      "## Missed Mutants",
      c("These mutations were not detected by the test suite. To improve test",
        "coverage, write tests that would fail when the original is replaced",
        "with the mutation.")))
  }

  writeLines(lines, file.path(output_dir, "mutant_results.md"))
}

#' Run mutations serially using a single package copy with mutate-revert
#' @noRd
run_mutations_serial <- function(pkg_path, prepared, timeout) {
  # Create one persistent package copy
  tmp_pkg <- tempfile("mutant_pkg_")
  on.exit(unlink(tmp_pkg, recursive = TRUE), add = TRUE)
  dir.create(tmp_pkg)
  file.copy(pkg_path, tmp_pkg, recursive = TRUE)
  tmp_pkg <- file.path(tmp_pkg, basename(pkg_path))

  n <- nrow(prepared)
  results <- vector("list", n)

  for (i in seq_len(n)) {
    m <- prepared[i, ]
    # Escape { and } for cli's glue interpolation — mutation text (e.g.
    # function-body replacement) may contain braces that cli would otherwise
    # try to eval() as R expressions, causing a crash.
    orig_escaped <- gsub("\\{", "{{", m$original)
    orig_escaped <- gsub("\\}", "}}", orig_escaped)
    repl_escaped <- gsub("\\{", "{{", m$replacement)
    repl_escaped <- gsub("\\}", "}}", repl_escaped)
    cli::cli_progress_step(
      sprintf("[%d/%d] %s:%d  %s -> %s", i, n, m$file, m$line, orig_escaped, repl_escaped)
    )
    results[[i]] <- test_mutation_in_place(tmp_pkg, m, timeout)
  }

  results
}

#' Run mutations in parallel using mclapply with one copy per worker
#' @noRd
run_mutations_parallel <- function(pkg_path, prepared, timeout, workers) {
  n <- nrow(prepared)

  # Create one persistent package copy per worker
  worker_dirs <- vapply(seq_len(workers), function(w) {
    tmp_pkg <- tempfile(paste0("mutant_worker_", w, "_"))
    dir.create(tmp_pkg)
    file.copy(pkg_path, tmp_pkg, recursive = TRUE)
    file.path(tmp_pkg, basename(pkg_path))
  }, character(1))

  on.exit({
    for (d in dirname(worker_dirs)) unlink(d, recursive = TRUE)
  }, add = TRUE)

  # Split mutations into chunks, one per worker
  indices <- seq_len(n)
  chunks <- split(indices, (indices - 1) %% workers)

  # Run each chunk in parallel
  chunk_results <- parallel::mclapply(seq_along(chunks), function(chunk_idx) {
    worker_pkg <- worker_dirs[chunk_idx]
    chunk <- chunks[[chunk_idx]]
    lapply(chunk, function(i) {
      m <- prepared[i, ]
      test_mutation_in_place(worker_pkg, m, timeout)
    })
  }, mc.cores = workers)

  # Flatten and reorder results
  flat <- vector("list", n)
  for (chunk_idx in seq_along(chunks)) {
    for (j in seq_along(chunks[[chunk_idx]])) {
      flat[[chunks[[chunk_idx]][j]]] <- chunk_results[[chunk_idx]][[j]]
    }
  }

  flat
}

#' Test a single mutation by writing mutated content in-place and reverting
#' @noRd
test_mutation_in_place <- function(pkg_copy, mutation, timeout) {
  r_file <- file.path(pkg_copy, "R", mutation$file)

  if (!file.exists(r_file)) {
    return(data.frame(
      file = mutation$file, line = mutation$line,
      original = mutation$original, replacement = mutation$replacement,
      outcome = "unviable", stringsAsFactors = FALSE
    ))
  }

  # Save original content
  original_content <- readLines(r_file, warn = FALSE)

  # Write mutated content
  writeLines(mutation$mutated_content, r_file)

  # Run tests
  test_result <- tryCatch({
    run_tests_in_copy(pkg_copy, timeout = timeout)
  }, error = function(e) {
    list(passed = FALSE, elapsed = 0, timeout = FALSE, error = TRUE)
  })

  # Revert to original

  writeLines(original_content, r_file)

  outcome <- mutant_classify_outcome(
    timeout = test_result$timeout,
    source_error = isTRUE(test_result$source_error),
    error = isTRUE(test_result$error),
    passed = test_result$passed
  )

  data.frame(
    file = mutation$file, line = mutation$line,
    original = mutation$original, replacement = mutation$replacement,
    outcome = outcome, stringsAsFactors = FALSE
  )
}

#' Run tests on a package copy, returning pass/fail and timing
#' @noRd
run_tests_in_copy <- function(pkg_path, timeout = 30) {
  start <- proc.time()["elapsed"]

  result <- tryCatch({
    out <- callr::r(
      function(path) {
        # Source phase: load all R files into a clean environment
        source_error <- FALSE
        env <- new.env(parent = globalenv())
        tryCatch({
          r_dir <- file.path(path, "R")
          for (f in list.files(r_dir, pattern = "\\.R$", full.names = TRUE)) {
            source(f, local = env)
          }
        }, error = function(e) {
          # Source/load error (e.g., stopifnot failure, bad syntax)
          source_error <<- TRUE
        })

        if (source_error) {
          return(list(passed = FALSE, source_error = TRUE, n_failed = NA_integer_))
        }

        # Test phase: run testthat tests
        test_dir <- file.path(path, "tests", "testthat")
        if (!dir.exists(test_dir)) {
          return(list(passed = TRUE, source_error = FALSE, n_failed = 0L))
        }

        results <- testthat::test_dir(
          test_dir,
          env = env,
          reporter = testthat::SilentReporter$new(),
          stop_on_failure = FALSE
        )

        n_fail <- sum(as.data.frame(results)$failed)
        list(passed = n_fail == 0L, source_error = FALSE, n_failed = n_fail)
      },
      args = list(path = pkg_path),
      timeout = timeout,
      error = "error"
    )

    elapsed <- as.numeric(proc.time()["elapsed"] - start)
    list(passed = out$passed, elapsed = elapsed, timeout = FALSE, error = FALSE,
         source_error = isTRUE(out$source_error))
  },
  callr_timeout_error = function(e) {
    elapsed <- as.numeric(proc.time()["elapsed"] - start)
    list(passed = FALSE, elapsed = elapsed, timeout = TRUE, error = FALSE,
         source_error = FALSE)
  },
  error = function(e) {
    elapsed <- as.numeric(proc.time()["elapsed"] - start)
    list(passed = FALSE, elapsed = elapsed, timeout = FALSE, error = TRUE,
         source_error = FALSE)
  })

  result
}
