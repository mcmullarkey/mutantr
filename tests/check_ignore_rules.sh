#!/usr/bin/env bash
# Predicate test: verify README and ignore rules for single-repo consolidation.
# Exits 0 only if all 8 gates pass.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILED=0

gate1_readme_has_bundled_wording() {
    echo "GATE 1: README.md has pak::pak() AND bundled/self-contained/in-tree wording..."
    if ! grep -q 'pak::pak("mcmullarkey/mutantr")' "$PROJECT_DIR/README.md"; then
        echo "FAIL: README.md missing pak::pak() install line"
        return 1
    fi
    # Check for bundled/self-contained/in-tree wording
    if ! grep -qiE 'bundled|self-contained|in.tree|no separate repo|no external dependency' "$PROJECT_DIR/README.md"; then
        echo "FAIL: README.md missing bundled/self-contained/in-tree wording"
        return 1
    fi
    echo "  OK"
}

gate2_no_stale_mutant_refs() {
    echo "GATE 2: No tracked file contains '../../../mutant' reference..."
    # Exclude the test scripts themselves and ADR docs which document the change
    if grep -r '../../../mutant' "$PROJECT_DIR" \
        --include='*.R' --include='*.rs' --include='*.toml' --include='*.md' \
        --exclude='*/check_self_contained.sh' \
        --exclude='*/check_ignore_rules.sh' \
        --exclude='*/0001-inline-mutant-engine.md' \
        2>/dev/null; then
        echo "FAIL: stale '../../../mutant' reference found"
        return 1
    fi
    echo "  OK"
}

gate3_no_stale_repo_language() {
    echo "GATE 3: No stale language about separate/external/sibling repo in README, R/, man/, tools/..."
    local dirs=("README.md" "R" "man" "tools")
    local found=0
    for d in "${dirs[@]}"; do
        target="$PROJECT_DIR/$d"
        if [ -f "$target" ]; then
            if grep -rni 'separate.*repo\|external.*repo\|sibling.*repo\|outside.*repo' "$target" 2>/dev/null; then
                echo "  Found in $d: $match"
                found=1
            fi
        elif [ -d "$target" ]; then
            matches=$(grep -rli 'separate.*repo\|external.*repo\|sibling.*repo\|outside.*repo' "$target" 2>/dev/null || true)
            if [ -n "$matches" ]; then
                echo "  Found in $d: $matches"
                found=1
            fi
        fi
    done
    if [ "$found" -eq 1 ]; then
        echo "FAIL: stale language about separate/sibling/external repo found"
        return 1
    fi
    echo "  OK"
}

gate4_rbuildignore_has_tests() {
    echo "GATE 4: .Rbuildignore contains '^src/rust/tests$'..."
    if ! grep -qF '^src/rust/tests$' "$PROJECT_DIR/.Rbuildignore"; then
        echo "FAIL: .Rbuildignore missing '^src/rust/tests$'"
        return 1
    fi
    echo "  OK"
}

gate5_rbuildignore_no_engine_source() {
    echo "GATE 5: .Rbuildignore does NOT contain '^src/rust/src/mutant$'..."
    if grep -qF '^src/rust/src/mutant$' "$PROJECT_DIR/.Rbuildignore"; then
        echo "FAIL: .Rbuildignore incorrectly excludes engine source"
        return 1
    fi
    echo "  OK"
}

gate6_gitignore_does_not_ignore_engine() {
    echo "GATE 6: .gitignore does NOT ignore 'src/rust/src/mutant' or 'src/rust/tests'..."
    local failed=0
    # Check root .gitignore
    if grep -q 'src/rust/src/mutant' "$PROJECT_DIR/.gitignore" 2>/dev/null; then
        echo "FAIL: root .gitignore ignores src/rust/src/mutant"
        failed=1
    fi
    if grep -q 'src/rust/tests' "$PROJECT_DIR/.gitignore" 2>/dev/null; then
        echo "FAIL: root .gitignore ignores src/rust/tests"
        failed=1
    fi
    # Check src/.gitignore
    if [ -f "$PROJECT_DIR/src/.gitignore" ]; then
        if grep -q 'src/rust/src/mutant' "$PROJECT_DIR/src/.gitignore" 2>/dev/null; then
            echo "FAIL: src/.gitignore ignores src/rust/src/mutant"
            failed=1
        fi
        if grep -q 'src/rust/tests' "$PROJECT_DIR/src/.gitignore" 2>/dev/null; then
            echo "FAIL: src/.gitignore ignores src/rust/tests"
            failed=1
        fi
    fi
    if [ "$failed" -eq 1 ]; then
        return 1
    fi
    echo "  OK"
}

gate7_target_in_both() {
    echo "GATE 7: src/rust/target covered by both .Rbuildignore AND some .gitignore..."
    local failed=0
    # Check .Rbuildignore
    if ! grep -qF '^src/rust/target$' "$PROJECT_DIR/.Rbuildignore" 2>/dev/null; then
        echo "FAIL: .Rbuildignore missing src/rust/target"
        failed=1
    fi
    # Check some .gitignore (root or src/.gitignore)
    local found_in_gitignore=0
    if grep -q 'target' "$PROJECT_DIR/.gitignore" 2>/dev/null; then
        found_in_gitignore=1
    fi
    if [ -f "$PROJECT_DIR/src/.gitignore" ] && grep -q 'target' "$PROJECT_DIR/src/.gitignore" 2>/dev/null; then
        found_in_gitignore=1
    fi
    if [ "$found_in_gitignore" -eq 0 ]; then
        echo "FAIL: target not covered by any .gitignore"
        failed=1
    fi
    if [ "$failed" -eq 1 ]; then
        return 1
    fi
    echo "  OK"
}

gate8_no_build_artifacts_tracked() {
    echo "GATE 8: No build artifacts (.o, .so, .dll, target/) tracked in git..."
    local artifacts
    artifacts=$(cd "$PROJECT_DIR" && git ls-files '*.o' '*.so' '*.dll' '**/target/' 2>/dev/null) || true
    if [ -n "$artifacts" ]; then
        echo "FAIL: Build artifacts tracked in git:"
        echo "$artifacts"
        return 1
    fi
    echo "  OK"
}

echo "=== Single-repo consolidation predicate checks ==="
echo ""

gate1_readme_has_bundled_wording || FAILED=1
echo ""
gate2_no_stale_mutant_refs || FAILED=1
echo ""
gate3_no_stale_repo_language || FAILED=1
echo ""
gate4_rbuildignore_has_tests || FAILED=1
echo ""
gate5_rbuildignore_no_engine_source || FAILED=1
echo ""
gate6_gitignore_does_not_ignore_engine || FAILED=1
echo ""
gate7_target_in_both || FAILED=1
echo ""
gate8_no_build_artifacts_tracked || FAILED=1
echo ""

if [ "$FAILED" -eq 1 ]; then
    echo "FAILED: One or more gates did not pass."
    exit 1
fi

echo "All gates passed. Single-repo consolidation complete."
exit 0
