# Diff parsing and mutation filtering module
#
# Provides two functions for PR-incremental mutation testing:
#   parse_diff_ranges()       — effectful: reads a unified diff file
#   filter_mutations_by_diff() — pure: subsets prepared mutations to
#                                only those on changed lines
#
# What this module DOES:
#   - Parse unified diff files into line-range data.frames
#   - Filter mutation data.frames to lines intersecting diff ranges
#
# What this module does NOT do:
#   - Run mutation tests (that's mutate_test()'s responsibility)
#   - Write reports
#   - Detect diff files in the working directory


#' Parse a unified diff file into per-hunk line ranges
#'
#' Effectful. Reads a unified diff file and returns a data.frame with one row
#' per hunk. Each row records the file (basename), start line, and end line
#' (inclusive) of the new-file lines added or modified by the hunk.
#'
#' Parsing rules:
#' \itemize{
#'   \item File paths are extracted from \code{diff --git b/path} headers
#'         and reduced to basename for matching against prepared$file.
#'   \item Hunk headers (\code{@@ -old,count +new,count @@}) determine the
#'         new-file line range: start = new, end = new + new_count - 1.
#'   \item Omitted counts default to 1 (e.g., \code{@@ -3 +4,2 @@} has
#'         new_count = 2, start = 4, end = 5).
#'   \item Zero new-count hunks (pure deletions) produce no range.
#'   \item Multi-hunk files produce multiple rows.
#'   \item An empty diff returns an empty data.frame with correct column types.
#' }
#'
#' @param diff_path Path to a unified diff file
#' @return A data.frame with columns: \code{file} (character), \code{line_start}
#'   (integer), \code{line_end} (integer). One row per hunk.
#' @noRd
parse_diff_ranges <- function(diff_path) {
  if (!file.exists(diff_path)) {
    stop("in_diff file not found: ", diff_path)
  }

  lines <- readLines(diff_path, warn = FALSE)

  # Edge case: empty diff
  if (length(lines) == 0) {
    return(data.frame(
      file = character(0),
      line_start = integer(0),
      line_end = integer(0),
      stringsAsFactors = FALSE
    ))
  }

  current_file <- NULL
  result_files <- character(0)
  result_starts <- integer(0)
  result_ends <- integer(0)

  for (line in lines) {
    # Track current file from diff --git headers
    # Format: diff --git a/path b/path
    if (grepl("^diff --git ", line)) {
      # Extract the b/path portion
      parts <- strsplit(line, " ")[[1]]
      if (length(parts) >= 4) {
        b_path <- parts[4]  # e.g., "b/R/foo.R"
        current_file <- basename(b_path)
      }
      next
    }

    # Parse hunk headers: @@ -old_start,old_count +new_start,new_count @@
    if (grepl("^@@ -", line)) {
      # Extract the two range specs: -old_start,old_count +new_start,new_count
      hunk_match <- regmatches(line, regexec(
        "^@@\\s+-([0-9]+)(?:,([0-9]+))?\\s+\\+([0-9]+)(?:,([0-9]+))?\\s+@@",
        line
      ))[[1]]

      if (length(hunk_match) >= 5) {
        new_start <- as.integer(hunk_match[4])
        new_count <- if (nzchar(hunk_match[5])) as.integer(hunk_match[5]) else 1L

        # Zero new-count (deletion-only hunks) produce no range
        if (new_count == 0) {
          next
        }

        new_end <- new_start + new_count - 1L

        result_files <- c(result_files, current_file)
        result_starts <- c(result_starts, new_start)
        result_ends <- c(result_ends, new_end)
      }
    }
  }

  data.frame(
    file = result_files,
    line_start = result_starts,
    line_end = result_ends,
    stringsAsFactors = FALSE
  )
}


#' Filter prepared mutations to lines that intersect diff ranges
#'
#' Pure function. Takes the prepared mutation data.frame and the ranges
#' data.frame from \code{parse_diff_ranges()}, and returns a subset of
#' \code{prepared} where each mutation's line number falls within at least
#' one range for the same file.
#'
#' @param prepared Data.frame with at least columns \code{file} (character,
#'   basename) and \code{line} (integer).
#' @param ranges Data.frame with columns \code{file} (character), \code{line_start}
#'   (integer), \code{line_end} (integer). One row per hunk.
#' @return A subset of \code{prepared} (same columns) containing only mutations
#'   on changed lines. Returns an empty data.frame (same column structure) if no
#'   ranges match.
#' @noRd
filter_mutations_by_diff <- function(prepared, ranges) {
  if (nrow(prepared) == 0 || nrow(ranges) == 0) {
    # Return empty prepared with same column structure
    return(prepared[integer(0), , drop = FALSE])
  }

  # For each prepared row, check if it intersects any range for the same file
  keep <- logical(nrow(prepared))

  for (i in seq_len(nrow(prepared))) {
    mut_file <- prepared$file[i]
    mut_line <- prepared$line[i]

    # Check all ranges for this file
    file_ranges <- ranges[ranges$file == mut_file, , drop = FALSE]
    if (nrow(file_ranges) == 0) {
      keep[i] <- FALSE
      next
    }

    for (j in seq_len(nrow(file_ranges))) {
      if (mut_line >= file_ranges$line_start[j] &&
          mut_line <= file_ranges$line_end[j]) {
        keep[i] <- TRUE
        break
      }
    }
  }

  prepared[keep, , drop = FALSE]
}
