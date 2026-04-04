#!/usr/bin/env bats
# Tests for gum-table lint rule — detecting manual table formatting

setup() {
  CODEBASE_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
  LINT="$CODEBASE_DIR/.mise/tasks/lint/gum-table"
}

run_lint() {
  usage_targets="$1" bash "$LINT"
}

# ============================================================================
# High confidence: column -t (always a true positive)
# ============================================================================

@test "column-t: detects piping to column -t" {
  run run_lint "$FIXTURES/manual-padding/task-c"
  [ "$status" -ne 0 ]
  [[ "$output" == *"[column-t]"* ]]
  [[ "$output" == *"WARN"* ]]
}

# ============================================================================
# High confidence: printf padding inside a loop
# ============================================================================

@test "loop-table: detects printf %-Ns inside while-read" {
  run run_lint "$FIXTURES/manual-padding/task-b"
  [ "$status" -ne 0 ]
  [[ "$output" == *"[loop-table]"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "loop-table: detects printf in piped while loop" {
  run run_lint "$FIXTURES/manual-padding/task-f"
  [ "$status" -ne 0 ]
  [[ "$output" == *"[loop-table]"* ]]
}

@test "loop-table: detects printf in loop, header outside is INFO" {
  run run_lint "$FIXTURES/manual-padding/task-e"
  [ "$status" -ne 0 ]
  [[ "$output" == *"[loop-table]"* ]]
  [[ "$output" == *"[padding]"* ]]
  # The loop hit is WARN, the header is INFO
  echo "$output" | grep "loop-table" | grep -q "WARN"
  echo "$output" | grep "padding" | grep -q "INFO"
}

# ============================================================================
# Low confidence: printf padding outside loops (INFO only, not a failure)
# ============================================================================

@test "padding: printf %-Ns outside loop is INFO, not a failure" {
  run run_lint "$FIXTURES/manual-padding/task-a"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[padding]"* ]]
  [[ "$output" == *"INFO"* ]]
  # Should NOT have WARN
  [[ "$output" != *"WARN"* ]]
}

@test "padding: status display with label alignment is INFO only" {
  run run_lint "$FIXTURES/clean/task-status"
  [ "$status" -eq 0 ]
}

@test "padding: separator + header without loop is INFO only" {
  run run_lint "$FIXTURES/manual-padding/task-d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO"* ]]
}

# ============================================================================
# True negatives — no output at all
# ============================================================================

@test "clean: already using gum table" {
  run run_lint "$FIXTURES/clean/task-gum"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "clean: simple printf without padding" {
  run run_lint "$FIXTURES/clean/task-simple"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "clean: padding pattern in a comment" {
  run run_lint "$FIXTURES/clean/task-comment"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "clean: padding pattern in a usage/help string" {
  run run_lint "$FIXTURES/clean/task-string"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ============================================================================
# Multi-file scanning
# ============================================================================

@test "directory scan finds high-confidence hits" {
  run run_lint "$FIXTURES/manual-padding"
  [ "$status" -ne 0 ]
  # task-b (loop), task-c (column-t), task-e (loop) should WARN
  [[ "$output" == *"task-b"* ]]
  [[ "$output" == *"task-c"* ]]
  [[ "$output" == *"task-e"* ]]
}

@test "clean directory passes entirely" {
  run run_lint "$FIXTURES/clean"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Output format
# ============================================================================

@test "WARN output includes file path, category, and line number" {
  run run_lint "$FIXTURES/manual-padding/task-b"
  [ "$status" -ne 0 ]
  [[ "$output" =~ WARN.*task-b:\[loop-table\].*[0-9]+: ]]
}

@test "INFO output includes file path, category, and line number" {
  run run_lint "$FIXTURES/manual-padding/task-a"
  [[ "$output" =~ INFO.*task-a:\[padding\].*[0-9]+: ]]
}

# ============================================================================
# Error handling
# ============================================================================

@test "fails when target does not exist" {
  run run_lint "/nonexistent"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}
