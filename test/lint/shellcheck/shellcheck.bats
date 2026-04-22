#!/usr/bin/env bats
# Tests for lint:shellcheck rule

setup() {
  CODEBASE_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
  LINT="$CODEBASE_DIR/.mise/tasks/lint/shellcheck"
}

# ============================================================================
# Detection
# ============================================================================

@test "lint: passes on a clean codebase" {
  run bash -c "usage_targets='$FIXTURES/clean' bash '$LINT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
}

@test "lint: fails on a codebase with shellcheck violations" {
  run bash -c "usage_targets='$FIXTURES/dirty' bash '$LINT'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty"* ]]
  [[ "$output" == *"violation"* ]]
}

@test "lint: fail output includes the violating file path" {
  run bash -c "usage_targets='$FIXTURES/dirty' bash '$LINT'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"broken"* ]]
}

@test "lint: fail output includes shellcheck error codes" {
  run bash -c "usage_targets='$FIXTURES/dirty' bash '$LINT'"
  [ "$status" -ne 0 ]
  # The broken fixture hits SC2086 (double-quote) and/or SC2045 (iterating ls)
  [[ "$output" == *"SC"* ]]
}

# ============================================================================
# Ignore directive
# ============================================================================

@test "lint: skips when codebase:ignore shellcheck is set in mise.toml" {
  run bash -c "usage_targets='$FIXTURES/ignored' bash '$LINT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"*"ignored"* ]]
}

# ============================================================================
# Scope
# ============================================================================

@test "lint: works on a codebase with no mise.toml" {
  run bash -c "usage_targets='$FIXTURES/no-toml' bash '$LINT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"no-toml"* ]]
}

@test "lint: passes on a codebase with no shell files" {
  run bash -c "usage_targets='$FIXTURES/empty' bash '$LINT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"empty"* ]]
  [[ "$output" == *"no shell files"* ]]
}

@test "lint: checks both .mise/tasks and lib/ directories" {
  run bash -c "usage_targets='$FIXTURES/mixed' bash '$LINT'"
  [ "$status" -ne 0 ]
  # Violation is in lib/bad.sh, not in the task — proves lib/ is scanned
  [[ "$output" == *"bad.sh"* ]]
}

# ============================================================================
# Multi-target
# ============================================================================

@test "lint: checks multiple targets and reports each" {
  run bash -c "usage_targets='$FIXTURES/clean $FIXTURES/dirty' bash '$LINT'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
  [[ "$output" == *"FAIL"*"dirty"* ]]
}

@test "lint: exit code is the number of failing targets" {
  run bash -c "usage_targets='$FIXTURES/dirty $FIXTURES/mixed' bash '$LINT'"
  [ "$status" -eq 2 ]
}

# ============================================================================
# Error paths
# ============================================================================

@test "lint: fails when target does not exist" {
  run bash -c "usage_targets='$FIXTURES/does-not-exist' bash '$LINT'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "lint: fails when no targets given" {
  run bash -c "usage_targets='' bash '$LINT'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least one target"* ]]
}
