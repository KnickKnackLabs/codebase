#!/usr/bin/env bats
# Tests for mise-settings lint rule

load ../../test_helper

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# ============================================================================
# Detection
# ============================================================================

@test "lint: passes when all settings present" {
  run codebase lint:mise-settings "$FIXTURES/complete"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "lint: fails when both settings missing" {
  run codebase lint:mise-settings "$FIXTURES/missing-both"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"quiet = true"* ]]
  [[ "$output" == *'task_output = "interleave"'* ]]
}

@test "lint: fails when only task_output missing" {
  run codebase lint:mise-settings "$FIXTURES/missing-output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *'task_output = "interleave"'* ]]
  # Should NOT complain about quiet
  [[ "$output" != *"quiet = true"* ]]
}

@test "lint: fails when no mise.toml exists" {
  run codebase lint:mise-settings "$FIXTURES/no-toml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"no mise.toml"* ]]
}

@test "lint: skips when codebase:ignore mise-settings is set" {
  run codebase lint:mise-settings "$FIXTURES/ignored"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"* ]]
}

@test "lint: checks multiple targets" {
  run codebase lint:mise-settings "$FIXTURES/complete" "$FIXTURES/missing-both"
  [ "$status" -ne 0 ]
  [[ "$output" == *"OK"*"complete"* ]]
  [[ "$output" == *"FAIL"*"missing-both"* ]]
}

# ============================================================================
# Fix mode
# ============================================================================

@test "fix: adds missing settings" {
  WORK_DIR="$BATS_TEST_TMPDIR/fix-test"
  cp -r "$FIXTURES/missing-both" "$WORK_DIR"

  run codebase lint:mise-settings --fix "$WORK_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FIXED"* ]]

  # Verify settings were added
  grep -q 'quiet = true' "$WORK_DIR/mise.toml"
  grep -q 'task_output = "interleave"' "$WORK_DIR/mise.toml"
}

@test "fix: adds only missing setting when one already exists" {
  WORK_DIR="$BATS_TEST_TMPDIR/fix-partial"
  cp -r "$FIXTURES/missing-output" "$WORK_DIR"

  run codebase lint:mise-settings --fix "$WORK_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FIXED"* ]]

  grep -q 'quiet = true' "$WORK_DIR/mise.toml"
  grep -q 'task_output = "interleave"' "$WORK_DIR/mise.toml"

  # quiet = true should appear exactly once (not duplicated)
  count=$(grep -c 'quiet = true' "$WORK_DIR/mise.toml")
  [ "$count" -eq 1 ]
}

@test "fix: no-op on already-complete target" {
  WORK_DIR="$BATS_TEST_TMPDIR/fix-noop"
  cp -r "$FIXTURES/complete" "$WORK_DIR"

  run codebase lint:mise-settings --fix "$WORK_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ============================================================================
# Error handling
# ============================================================================

@test "lint: fails when target does not exist" {
  run codebase lint:mise-settings /nonexistent
  [ "$status" -ne 0 ]
}
