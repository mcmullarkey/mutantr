# ADR-0001: Inline mutant engine as nested Rust module

**Status:** Accepted
**Date:** 2026-06-22

## Context

The `mutantr` R package generates R source mutations via a Rust static library (`rmutant`).
Originally the Rust code depended on a standalone `mutant` Rust crate via a relative path
dependency (`mutant = { path = '../../../mutant' }`). This coupling has two problems:

1. **Fragile build:** The path dependency requires a sibling checkout at a specific relative
   location. CI, fresh clones, or alternative workspace layouts break the build.
2. **Version drift:** The engine crate evolves independently of the R package. There is no
   guarantee the installed crate matches what the R package expects.

The R community expects R packages to be self-contained. An external Rust crate dependency
is invisible to R's build system and creates a hidden requirement.

## Options

### Option A: Inline as a nested module (chosen)

Copy the 7 source files of the `mutant` crate into `src/rust/src/mutant/` as a directory
module, rename the crate root `lib.rs` to `mod.rs`, declare `pub mod mutant;` in the
rmutant lib.rs, and remove the path dependency from Cargo.toml.

- **Pros:** Self-contained build; single `cargo build` produces the static lib; no external
  checkout needed; dependency versions (`thiserror`, `serde`) move to Cargo.toml where they
  are visible and managed.
- **Cons:** The engine code lives inside the R package repo; shared Rust projects cannot
  depend on it directly (not a concern — this engine is purpose-built for mutantr).
- **Neutral:** The `crate::` → `super::` rewrite in the inlined files is mechanical and
  required exactly once.

### Option B: Publish `mutant` to crates.io and use a version dep

- **Pros:** Canonical Rust dependency management; version pinning.
- **Cons:** The `mutant` crate is experimental and not ready for publication; adds
  maintenance burden of version bumps; CI must fetch from crates.io.

### Option C: Keep the path dependency

- **Pros:** No code movement; maximally DRY.
- **Cons:** Fragile, invisible to R's build system, prevents self-contained distribution.

## Decision

Adopt Option A: inline the mutant engine as a nested `src/rust/src/mutant/` module.

## Consequences

- The R package becomes self-contained — `R CMD INSTALL` + `cargo build` is the only
  build step. No external Rust checkouts needed.
- The Rust workspace at `src/rust/` now has a single crate with a module tree instead of
  two crates with a path dependency.
- All `crate::` references in the inlined code become `super::` references to reflect
  the new module nesting.
- `thiserror` and `serde` (with `derive`) are listed explicitly in Cargo.toml.
- Tests and unit tests continue to work unchanged because the public API surface
  (`mutant::scan_file`, etc.) is preserved — it now resolves to the local module
  instead of an external crate.
