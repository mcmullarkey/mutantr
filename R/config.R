# .mutantr.toml config file reader
#
# This module provides a narrow reader for .mutantr.toml configuration files.
# It reads, parses, and syntax-validates the file, then returns a flat named
# list of config values. It does NOT apply settings or merge with defaults —
# that happens in mutate_test().
#
# What it DOES:
#   - Read .mutantr.toml from the package root directory
#   - Parse TOML via configr::read.config()
#   - Validate expected types for known keys
#   - Accept unknown keys (forward-compatible)
#
# What it does NOT do:
#   - Traverse parent directories to find config files
#   - Merge config with defaults or explicit arguments
#   - Apply config values to mutation testing logic
#   - Validate semantic constraints (e.g., timeout > 0)

#' Read .mutantr.toml configuration file
#'
#' Reads the \code{.mutantr.toml} file from the package root directory.
#' This is a narrow reader: it only reads and parses, does NOT apply
#' settings or merge with defaults — that happens in \code{mutate_test()}.
#'
#' @param pkg_path Path to the package root directory
#'
#' @return A flat named list of config values, or empty list if no file
#'   exists or the file is empty. Known keys with their expected R types:
#'   \itemize{
#'     \item{\code{timeout}}{ numeric (integer) }
#'     \item{\code{workers}}{ numeric (integer) }
#'     \item{\code{output_dir}}{ character }
#'     \item{\code{exclude}}{ character vector }
#'     \item{\code{iterate}}{ logical }
#'     \item{\code{in_diff}}{ character }
#'   }
#'   Unknown keys are accepted and included in the returned list
#'   (forward-compatible).
#'
#' @noRd
read_config <- function(pkg_path) {
  config_path <- file.path(pkg_path, ".mutantr.toml")

  if (!file.exists(config_path)) {
    return(list())
  }

  raw <- configr::read.config(file = config_path, format = "toml")

  # configr returns FALSE on parse failure
  if (identical(raw, FALSE)) {
    stop("Failed to parse ", basename(config_path), call. = FALSE)
  }

  if (length(raw) == 0) {
    return(list())
  }

  # Type validation for known keys
  # Use named list of checker functions — clean and extensible
  type_checkers <- list(
    timeout    = is.numeric,
    workers    = is.numeric,
    output_dir = is.character,
    exclude    = is.character,
    iterate    = is.logical,
    in_diff    = is.character
  )

  type_names <- list(
    timeout    = "numeric",
    workers    = "numeric",
    output_dir = "character",
    exclude    = "character",
    iterate    = "logical",
    in_diff    = "character"
  )

  for (key in names(raw)) {
    checker <- type_checkers[[key]]
    if (is.null(checker)) {
      # Unknown key — accepted (forward-compatible)
      next
    }
    if (!checker(raw[[key]])) {
      stop(
        "In ", basename(config_path), ": '", key,
        "' must be ", type_names[[key]], ", got: ",
        deparse(raw[[key]]),
        call. = FALSE
      )
    }
  }

  raw
}
