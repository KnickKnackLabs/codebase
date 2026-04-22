#!/usr/bin/env bats
# Tests for _task() migration

load ../../test_helper

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"

  # Copy before fixtures to a temp dir for migration (don't mutate fixtures)
  WORK_DIR="$BATS_TEST_TMPDIR/work"
  cp -r "$FIXTURES/before" "$WORK_DIR"
}

# Helper: compare a migrated file against its expected after
assert_matches_after() {
  local file="$1"
  diff -u "$FIXTURES/after/$file" "$WORK_DIR/$file"
}

# Helper: compare a migrated file against the before fixture
assert_matches_before() {
  local file="$1"
  diff -u "$FIXTURES/before/$file" "$WORK_DIR/$file"
}

# ============================================================================
# Individual variant tests
# ============================================================================

@test "migrate: simple mise run → _task" {
  codebase migrate:task-pattern "$WORK_DIR"
  assert_matches_after ".mise/tasks/simple"
}

@test "migrate: strips -q flag from mise run -q" {
  codebase migrate:task-pattern "$WORK_DIR"
  assert_matches_after ".mise/tasks/quiet-flag"
}

@test "migrate: preserves arguments after task name" {
  codebase migrate:task-pattern "$WORK_DIR"
  assert_matches_after ".mise/tasks/with-args"
}

@test "migrate: handles mise run inside command substitution" {
  codebase migrate:task-pattern "$WORK_DIR"
  assert_matches_after ".mise/tasks/in-subshell"
}

@test "migrate: does not change usage strings, comments, or existing _task calls" {
  codebase migrate:task-pattern "$WORK_DIR"
  assert_matches_after ".mise/tasks/no-change"
}

@test "migrate: does not change mise run in error strings or echo'd instructions" {
  codebase migrate:task-pattern "$WORK_DIR"
  assert_matches_after ".mise/tasks/error-strings"
}

# ============================================================================
# Full migration test
# ============================================================================

@test "migrate: all files match expected after state" {
  codebase migrate:task-pattern "$WORK_DIR"
  # Diff entire directory trees
  run diff -ru "$FIXTURES/after" "$WORK_DIR"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Reverse migration tests
# ============================================================================

@test "reverse: _task → mise run" {
  # Start from the after state
  rm -rf "$WORK_DIR"
  cp -r "$FIXTURES/after" "$WORK_DIR"
  codebase migrate:task-pattern --reverse "$WORK_DIR"
  # simple and with-args are lossless round-trips
  assert_matches_before ".mise/tasks/simple"
  assert_matches_before ".mise/tasks/with-args"
}

@test "reverse: does not change comments or echo strings" {
  rm -rf "$WORK_DIR"
  cp -r "$FIXTURES/after" "$WORK_DIR"
  codebase migrate:task-pattern --reverse "$WORK_DIR"
  assert_matches_before ".mise/tasks/error-strings"
}

@test "reverse: handles _task inside command substitution" {
  rm -rf "$WORK_DIR"
  cp -r "$FIXTURES/after" "$WORK_DIR"
  codebase migrate:task-pattern --reverse "$WORK_DIR"
  # in-subshell had mise run -q, reverse produces mise run (no -q)
  # so we check the specific expected output
  grep -q 'mise run email:quota' "$WORK_DIR/.mise/tasks/in-subshell"
  grep -q 'mise run email:list' "$WORK_DIR/.mise/tasks/in-subshell"
  # Should NOT contain _task anymore
  ! grep -q '_task' "$WORK_DIR/.mise/tasks/in-subshell"
}

# ============================================================================
# Round-trip tests
# ============================================================================

@test "round-trip: forward then reverse restores lossless fixtures" {
  # Only test fixtures where forward is lossless (no -q flag)
  codebase migrate:task-pattern "$WORK_DIR"
  codebase migrate:task-pattern --reverse "$WORK_DIR"
  assert_matches_before ".mise/tasks/simple"
  assert_matches_before ".mise/tasks/with-args"
  assert_matches_before ".mise/tasks/error-strings"
}

# ============================================================================
# Error handling
# ============================================================================

@test "migrate: fails when target does not exist" {
  run codebase migrate:task-pattern /nonexistent
  [ "$status" -ne 0 ]
}
