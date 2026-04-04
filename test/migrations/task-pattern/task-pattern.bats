#!/usr/bin/env bats
# Tests for _task() migration

setup() {
  CODEBASE_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
  MIGRATE="$CODEBASE_DIR/.mise/tasks/migrate/task-pattern"

  # Copy before fixtures to a temp dir for migration (don't mutate fixtures)
  WORK_DIR="$BATS_TEST_TMPDIR/work"
  cp -r "$FIXTURES/before" "$WORK_DIR"
}

# Helper: run forward migration on work dir
run_migrate() {
  usage_target="$WORK_DIR" bash "$MIGRATE"
}

# Helper: run reverse migration on work dir
run_migrate_reverse() {
  usage_target="$WORK_DIR" usage_reverse=true bash "$MIGRATE"
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
  run_migrate
  assert_matches_after ".mise/tasks/simple"
}

@test "migrate: strips -q flag from mise run -q" {
  run_migrate
  assert_matches_after ".mise/tasks/quiet-flag"
}

@test "migrate: preserves arguments after task name" {
  run_migrate
  assert_matches_after ".mise/tasks/with-args"
}

@test "migrate: handles mise run inside command substitution" {
  run_migrate
  assert_matches_after ".mise/tasks/in-subshell"
}

@test "migrate: does not change usage strings, comments, or existing _task calls" {
  run_migrate
  assert_matches_after ".mise/tasks/no-change"
}

@test "migrate: does not change mise run in error strings or echo'd instructions" {
  run_migrate
  assert_matches_after ".mise/tasks/error-strings"
}

# ============================================================================
# Full migration test
# ============================================================================

@test "migrate: all files match expected after state" {
  run_migrate
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
  run_migrate_reverse
  # simple and with-args are lossless round-trips
  assert_matches_before ".mise/tasks/simple"
  assert_matches_before ".mise/tasks/with-args"
}

@test "reverse: does not change comments or echo strings" {
  rm -rf "$WORK_DIR"
  cp -r "$FIXTURES/after" "$WORK_DIR"
  run_migrate_reverse
  assert_matches_before ".mise/tasks/error-strings"
}

@test "reverse: handles _task inside command substitution" {
  rm -rf "$WORK_DIR"
  cp -r "$FIXTURES/after" "$WORK_DIR"
  run_migrate_reverse
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
  run_migrate
  run_migrate_reverse
  assert_matches_before ".mise/tasks/simple"
  assert_matches_before ".mise/tasks/with-args"
  assert_matches_before ".mise/tasks/error-strings"
}

# ============================================================================
# Error handling
# ============================================================================

@test "migrate: fails when target does not exist" {
  run bash -c 'usage_target="/nonexistent" bash "'"$MIGRATE"'"'
  [ "$status" -ne 0 ]
}
