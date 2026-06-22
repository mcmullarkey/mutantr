---
ac: function-body
depends_on: none
risk: high
---

## AC spec: Detect `name <- function(...) { body }` and replace body with `{ return(NULL) }`

### Executable Spec
- **predicate:** scan_source("f <- function(x) { x + 1 }", "test.R") returns one site with kind==FunctionBody { name: "f", body_span }, replacements==["{ return(NULL) }"], original=="{ x + 1 }", apply yields "f <- function(x) { return(NULL) }" AND body_span correctly covers { through matching } across nested braces, strings, comments, default args AND scan_source("f <- function(x) { return(NULL) }") returns zero sites (noop) AND name "new" → zero sites AND anonymous → zero sites AND single-expression (no braces) → zero sites AND "function" in string → zero sites AND "myfunction" → zero sites (word boundary) AND unclosed body → zero sites, no panic AND find_matching_brace independently testable.
- **probe:** `cargo test`
- **negative:** Naive raw-byte brace counting fails on: nested braces (if {} else {}), braces in strings ("}"), braces in comments (# { }), braces in default args (function(x = {1})).
- **verification:** code · cargo test (15+ test cases)
- **fixture status:** NEW — 15+ inline test cases in scanner.rs + integration tests
- **rubric anchor:** §1.2, §2.3, §5.1

### Design Intent
- **Types (§1):** Add FunctionBody { name: String, body_span: Span } struct variant to MutationKind. location.span set to same as body_span so apply_mutation works unchanged.
- **Pure/effectful (§2):** scan_source pure. find_matching_brace pure helper. All tests fixture-free.
- **Boundary cuts (§3):** MutationKind in types.rs, detection in scanner.rs, application in mutate.rs (unchanged). No back-edge.
- **Module responsibility (§4):** scanner.rs gains function-body detection. find_matching_brace has own docstring.
- **Function discipline (§5):** find_matching_brace does one thing (brace matching with string/comment awareness). Detection split from brace matching.

### Technical Context
- **Files:** `src/types.rs:21-26` (add variant), `src/scanner.rs` (find_matching_brace + detection logic), `tests/integration.rs` (extend + new tests). mutate.rs NOT touched.
- **Key details:** Detection flow: scan backward from <- for name, after function keyword with word-boundary, track paren depth to ), skip whitespace, expect {, call find_matching_brace. Noop skip if body is return(NULL). Name "new" skip. Unclosed → None → skip silently.
- **Conflict set:** `src/types.rs`, `src/scanner.rs`, `tests/integration.rs`