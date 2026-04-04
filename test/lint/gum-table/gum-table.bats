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
# True positives — should detect
# ============================================================================

@test "detects printf with fixed-width padding (%-20s)" {
  run run_lint "$FIXTURES/manual-padding/task-a"
  [ "$status" -ne 0 ]
  [[ "$output" == *"%-20s"* ]]
}

@test "detects padded printf in a loop" {
  run run_lint "$FIXTURES/manual-padding/task-b"
  [ "$status" -ne 0 ]
  [[ "$output" == *"%-30s"* ]]
}

@test "detects column -t usage" {
  run run_lint "$FIXTURES/manual-padding/task-c"
  [ "$status" -ne 0 ]
  [[ "$output" == *"column -t"* ]]
}

@test "detects separator lines with manual padding" {
  run run_lint "$FIXTURES/manual-padding/task-d"
  [ "$status" -ne 0 ]
  [[ "$output" == *"%-20s"* ]]
}

@test "reports all hits in a file with multiple patterns" {
  run run_lint "$FIXTURES/manual-padding/task-a"
  [ "$status" -ne 0 ]
  # task-a has two printf lines with %-20s
  count=$(echo "$output" | grep -c "WARN")
  [ "$count" -eq 2 ]
}

@test "detects across entire directory" {
  run run_lint "$FIXTURES/manual-padding"
  [ "$status" -ne 0 ]
  # All four fixture files should produce warnings
  [[ "$output" == *"task-a"* ]]
  [[ "$output" == *"task-b"* ]]
  [[ "$output" == *"task-c"* ]]
  [[ "$output" == *"task-d"* ]]
}

# ============================================================================
# True negatives — should NOT detect
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

@test "clean: entire clean directory passes" {
  run run_lint "$FIXTURES/clean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ============================================================================
# Output format
# ============================================================================

@test "output includes file path and line number" {
  run run_lint "$FIXTURES/manual-padding/task-a"
  [ "$status" -ne 0 ]
  # Format: WARN  name:rel:lineno: line
  [[ "$output" =~ WARN.*task-a:[0-9]+: ]]
}

# ============================================================================
# Error handling
# ============================================================================

@test "fails when target does not exist" {
  run run_lint "/nonexistent"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}
