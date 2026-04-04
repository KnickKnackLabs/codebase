#!/usr/bin/env bats
# Tests for mise-settings lint rule

setup() {
  CODEBASE_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
  LINT="$CODEBASE_DIR/.mise/tasks/lint/mise-settings"
}

# ============================================================================
# Detection
# ============================================================================

@test "lint: passes when all settings present" {
  run bash -c "usage_targets='$FIXTURES/complete' bash '$LINT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "lint: fails when both settings missing" {
  run bash -c "usage_targets='$FIXTURES/missing-both' bash '$LINT'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"quiet = true"* ]]
  [[ "$output" == *'task_output = "interleave"'* ]]
}

@test "lint: fails when only task_output missing" {
  run bash -c "usage_targets='$FIXTURES/missing-output' bash '$LINT'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *'task_output = "interleave"'* ]]
  # Should NOT complain about quiet
  [[ "$output" != *"quiet = true"* ]]
}

@test "lint: fails when no mise.toml exists" {
  run bash -c "usage_targets='$FIXTURES/no-toml' bash '$LINT'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"no mise.toml"* ]]
}

@test "lint: checks multiple targets" {
  run bash -c "usage_targets='$FIXTURES/complete $FIXTURES/missing-both' bash '$LINT'"
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

  run bash -c "usage_targets='$WORK_DIR' usage_fix=true bash '$LINT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FIXED"* ]]

  # Verify settings were added
  grep -q 'quiet = true' "$WORK_DIR/mise.toml"
  grep -q 'task_output = "interleave"' "$WORK_DIR/mise.toml"
}

@test "fix: adds only missing setting when one already exists" {
  WORK_DIR="$BATS_TEST_TMPDIR/fix-partial"
  cp -r "$FIXTURES/missing-output" "$WORK_DIR"

  run bash -c "usage_targets='$WORK_DIR' usage_fix=true bash '$LINT'"
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

  run bash -c "usage_targets='$WORK_DIR' usage_fix=true bash '$LINT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ============================================================================
# Error handling
# ============================================================================

@test "lint: fails when target does not exist" {
  run bash -c "usage_targets='/nonexistent' bash '$LINT'"
  [ "$status" -ne 0 ]
}
