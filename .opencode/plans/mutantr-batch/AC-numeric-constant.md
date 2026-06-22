---
ac: numeric-constant
depends_on: none
risk: medium
---

## AC spec: Numeric literal detection and mutation (0→1, 1→0, n→0/1/-1) in scanner

### Executable Spec
- **predicate:** scan_source detects numeric literals as MutationKind::Numeric with correct originals and replacements: "0"→["1"], "1"→["0"], "42"→["0","1","-1"], "3.14"→["0.0","1.0","-1.0"], "0.0"→["1.0"], "1.0"→["0.0"], ".5"→["0.0","1.0","-1.0"], "1e5"→one site (no Arithmetic for embedded e), "1.5e-3"→one site (embedded - is exponent NOT Arithmetic), "-5"→two sites (- is Arithmetic, 5 is Numeric), "a0 <- 0"→only 0 after <- (not in a0), strings/comments skipped, apply_mutations produces correct text, serde_json round-trip works.
- **probe:** `cargo test -p mutant -- numeric`
- **negative:** Static OperatorPair approach (finds 0 inside strings, inside a0, breaks on 0.5). Must NOT use operator registry — numerics are open-ended.
- **verification:** code · cargo test
- **fixture status:** NEW — unit tests in scanner.rs + integration test in tests/integration.rs
- **rubric anchor:** §1.2, §2.3, §5.1

### Design Intent
- **Types (§1):** Add Numeric variant to MutationKind. No exhaustive match exists in codebase — safe.
- **Pure/effectful (§2):** scan_source remains pure. New try_scan_numeric_literal helper is pure. Tests need no fixtures.
- **Boundary cuts (§3):** Numeric detection is new branch BEFORE operator loop. operators.rs NOT touched. mutate.rs NOT touched (generic span-based).
- **Module responsibility (§4):** scanner.rs gains numeric detection. operators.rs explicitly does NOT gain numeric entries.
- **Function discipline (§5):** try_scan_numeric_literal does one thing: detect+classify numeric at position.

### Technical Context
- **Files:** `src/types.rs` (add Numeric), `src/scanner.rs` (new branch + helper + tests), `tests/integration.rs` (round-trip test)
- **Key details:** Boundary: char before first digit must not be ident UNLESS . preceded by non-ident. Char after literal must not be ident (rejects 1L, 1i, 0x). Floats (contain . or e/E) get .0-suffixed replacements. Integers get bare replacements. Scientific notation: e/E with optional +/- then required digit. R suffixes (L, i) deferred.
- **Conflict set:** `src/scanner.rs`, `src/types.rs`, `tests/integration.rs`