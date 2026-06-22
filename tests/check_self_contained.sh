#!/usr/bin/env bash
# Predicate test: verify mutantr is self-contained with inlined mutant engine.
# Exits 0 only if all 6 guards pass.
set -euo pipefail

RUST_DIR="src/rust"
FAILED=0

guard0_check_cargo_toml_no_mutant_dep() {
    echo "GUARD 0: Cargo.toml has no 'mutant =' line..."
    if grep -n 'mutant = ' "$RUST_DIR/Cargo.toml" 2>/dev/null; then
        echo "FAIL: Cargo.toml still references mutant dependency"
        return 1
    fi
    echo "  OK"
}

guard0b_check_cargo_toml_has_thiserror_serde() {
    echo "GUARD 0b: Cargo.toml lists thiserror and serde (derive)..."
    if ! grep -q 'thiserror' "$RUST_DIR/Cargo.toml"; then
        echo "FAIL: thiserror not found in Cargo.toml"
        return 1
    fi
    if ! grep -q 'serde' "$RUST_DIR/Cargo.toml"; then
        echo "FAIL: serde not found in Cargo.toml"
        return 1
    fi
    # Verify serde has derive feature
    if ! grep -q 'derive' "$RUST_DIR/Cargo.toml"; then
        # serde might be listed without derive feature — fail
        if grep -q 'serde' "$RUST_DIR/Cargo.toml"; then
            echo "FAIL: serde found but without 'derive' feature"
            return 1
        fi
    fi
    echo "  OK"
}

guard1_check_mod_mutant_in_librs() {
    echo "GUARD 1: src/lib.rs declares 'mod mutant;'..."
    if ! grep -q 'mod mutant;' "$RUST_DIR/src/lib.rs"; then
        echo "FAIL: no 'mod mutant;' declaration in lib.rs"
        return 1
    fi
    echo "  OK"
}

guard2_check_source_files() {
    echo "GUARD 2: All 7 source files exist under src/mutant/..."
    local files=("mod.rs" "error.rs" "types.rs" "operators.rs" "mutate.rs" "scanner.rs" "package.rs")
    for f in "${files[@]}"; do
        if [ ! -f "$RUST_DIR/src/mutant/$f" ]; then
            echo "FAIL: missing src/mutant/$f"
            return 1
        fi
    done
    echo "  OK"
}

guard3_check_no_stale_mutant_refs() {
    echo "GUARD 3: No stale '../../../mutant' references in src/rust/..."
    if grep -r '../../../mutant' "$RUST_DIR/" --include='*.rs' --include='*.toml' 2>/dev/null; then
        echo "FAIL: stale '../../../mutant' reference found"
        return 1
    fi
    echo "  OK"
}

guard4_check_cargo_build() {
    echo "GUARD 4: cargo build succeeds after fresh Cargo.lock..."
    local lockfile="$RUST_DIR/Cargo.lock"
    if [ -f "$lockfile" ]; then
        rm -f "$lockfile"
        echo "  (deleted existing Cargo.lock)"
    fi
    if ! (cargo build --manifest-path "$RUST_DIR/Cargo.toml" 2>&1); then
        echo "FAIL: cargo build failed"
        return 1
    fi
    echo "  OK"
}

guard5_check_lock_no_mutant_package() {
    echo "GUARD 5: Regenerated Cargo.lock has no [[package]] name = 'mutant'..."
    # Use grep to check for the mutant package entry; use raw parsing
    if grep -q 'name = "mutant"' "$RUST_DIR/Cargo.lock" 2>/dev/null; then
        echo "FAIL: Cargo.lock still contains a 'mutant' package entry"
        return 1
    fi
    echo "  OK"
}

echo "=== Self-contained predicate checks ==="
echo ""

guard0_check_cargo_toml_no_mutant_dep || FAILED=1
echo ""
guard0b_check_cargo_toml_has_thiserror_serde || FAILED=1
echo ""
guard1_check_mod_mutant_in_librs || FAILED=1
echo ""
guard2_check_source_files || FAILED=1
echo ""
guard3_check_no_stale_mutant_refs || FAILED=1
echo ""
guard4_check_cargo_build || FAILED=1
echo ""
guard5_check_lock_no_mutant_package || FAILED=1
echo ""

if [ "$FAILED" -eq 1 ]; then
    echo "FAILED: One or more guards did not pass."
    exit 1
fi

echo "All guards passed. Package is self-contained."
exit 0
