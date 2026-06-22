# Plan: render-outcome-helper

## Feature Goal
Extract a shared `render_outcome_section(df, title, intro_lines)` helper from `write_md_report()` in `R/mutate_test.R` to eliminate the duplicated per-file grouping loop between the `## Missed Mutants` and `## Unviable Mutants` detail sections. Behavior-preserving refactor addressing §3.3 (single-responsibility helpers) and §5.2 (concise by default) design-principle drift identified during roborev review of PR #1.

## Source
- GitHub issue: #2 — `[chore] Extract render_outcome_section helper to eliminate duplicated report-rendering loop`
- Origin: roborev review of commit `7deea3b` (PR #1), triaged as defer → now implemented.

## Dependencies
- AC-1 depends on #1 (merged — unviable classification code is on `main`).
- No further ACs. This is a single-slice leaf refactor.

## AC Order

| AC | Title | Depends on | Risk | Conflict set |
|----|-------|-----------|------|--------------|
| 1 | Extract `render_outcome_section` helper; both sections use it; all tests pass | #1 (merged) | low | `R/mutate_test.R`, `tests/testthat/test-mutate_test.R` |

## Implementation Schedule

- **Batch 1 (single issue, sequential):** #2 — no parallelization needed (one AC, one file pair, low risk).

## Open Questions
None. Resolver confirmed no load-bearing disagreements (minor disagreement on fixture status resolved in favor of the adversarial proposer — NEW tests required because existing `grepl` tests cannot distinguish a helper call from an inline loop).

## Plan Reference
- Slice: AC-1 from render-outcome-helper
- Issue: #2
<!-- plan: .opencode/plans/render-outcome-helper.md -->
<!-- slice: AC-1 - Extract render_outcome_section helper -->
