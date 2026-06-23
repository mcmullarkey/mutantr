# mutantr

Mutation testing for R packages, powered by Rust.

mutantr introduces small changes (mutants) to your R source code — flipping `==` to `!=`, swapping `TRUE` for `FALSE`, replacing `+` with `-` — then runs your test suite against each one. If your tests catch the mutant, great. If they don't, you've found a gap in your test coverage.

The core engine is written in Rust and bundled directly with this package — no external checkout needed. It's exposed to R via [extendr](https://extendr.github.io/), so scanning and mutation generation are near-instant even on large packages. Test execution runs in parallel across multiple workers, bringing a 111-mutant package from ~3 minutes down to ~25 seconds on 4 cores.

## Install

```r
pak::pak("mcmullarkey/mutantr")
```

Requires Rust toolchain (`rustc >= 1.65.0` and `cargo`). Install via [rustup](https://rustup.rs/) if you don't have it. The package builds and installs end-to-end via [rextendr](https://github.com/extendr/rextendr) and passes `R CMD check`.

## Usage

```r
library(mutantr)

results <- mutate_test("path/to/your/package", workers = 4)
```

This scans your package's `R/` directory, generates all possible mutations, runs your testthat suite against each one, and returns a data frame of outcomes: **caught**, **missed**, **unviable**, or **timeout**.

To write reports for humans and AI agents:

```r
results <- mutate_test("path/to/your/package", workers = 4, output_dir = "reports")
```

This produces `mutant_results.md` (a readable summary with missed mutants grouped by file) and `mutant_results.json` (machine-readable, suitable for feeding into an AI agent to generate targeted tests).

## Classifying outcomes

`mutant_classify_outcome()` exposes the Rust-backed classifier the engine uses internally, so downstream tools can map raw boolean signals to an outcome without re-implementing the precedence rules:

```r
mutant_classify_outcome(timeout = FALSE, source_error = FALSE, error = FALSE, passed = TRUE)
#> "missed"
```

It returns one of `"caught"`, `"missed"`, `"unviable"`, or `"timeout"`, with precedence `timeout` > `source_error` > (`error` or not `passed`) > `missed`.

## Mutation operators

| Category | Mutations |
|----------|-----------|
| Comparison | `==` / `!=`, `<` / `>=`, `>` / `<=` |
| Logical | `&&` / `\|\|`, `&` / `\|` |
| Arithmetic | `+` / `-`, `*` / `/` |
| Boolean | `TRUE` / `FALSE` |

The scanner is R-aware: it skips comments, strings, and assignment operators (`<-`, `<<-`), and respects word boundaries so `isTRUE(x)` doesn't get mutated.
