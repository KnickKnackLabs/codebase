#!/usr/bin/env bats
# Tests for gum-table lint rule — detecting manual table formatting

load ../../test_helper

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# ============================================================================
# High confidence: column -t (always a true positive)
# ============================================================================

@test "column-t: detects piping to column -t" {
  run codebase lint:gum-table "$FIXTURES/manual-padding/task-c"
  [ "$status" -ne 0 ]
  [[ "$output" == *"[column-t]"* ]]
  [[ "$output" == *"WARN"* ]]
}

# ============================================================================
# High confidence: printf padding inside a loop
# ============================================================================

@test "loop-table: detects printf %-Ns inside while-read" {
  run codebase lint:gum-table "$FIXTURES/manual-padding/task-b"
  [ "$status" -ne 0 ]
  [[ "$output" == *"[loop-table]"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "loop-table: detects printf in piped while loop" {
  run codebase lint:gum-table "$FIXTURES/manual-padding/task-f"
  [ "$status" -ne 0 ]
  [[ "$output" == *"[loop-table]"* ]]
}

@test "loop-table: detects printf in loop, header outside is INFO" {
  run codebase lint:gum-table "$FIXTURES/manual-padding/task-e"
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
  run codebase lint:gum-table "$FIXTURES/manual-padding/task-a"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[padding]"* ]]
  [[ "$output" == *"INFO"* ]]
  # Should NOT have WARN
  [[ "$output" != *"WARN"* ]]
}

@test "padding: status display with label alignment is INFO only" {
  run codebase lint:gum-table "$FIXTURES/clean/task-status"
  [ "$status" -eq 0 ]
}

@test "padding: separator + header without loop is INFO only" {
  run codebase lint:gum-table "$FIXTURES/manual-padding/task-d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO"* ]]
}

# ============================================================================
# True negatives — no output at all
# ============================================================================

@test "clean: already using gum table" {
  run codebase lint:gum-table "$FIXTURES/clean/task-gum"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "clean: simple printf without padding" {
  run codebase lint:gum-table "$FIXTURES/clean/task-simple"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "clean: padding pattern in a comment" {
  run codebase lint:gum-table "$FIXTURES/clean/task-comment"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "clean: inline codebase:ignore suppresses hit" {
  run codebase lint:gum-table "$FIXTURES/clean/task-ignored"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "clean: padding pattern in a usage/help string" {
  run codebase lint:gum-table "$FIXTURES/clean/task-string"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ============================================================================
# Multi-file scanning
# ============================================================================

@test "directory scan finds high-confidence hits" {
  run codebase lint:gum-table "$FIXTURES/manual-padding"
  [ "$status" -ne 0 ]
  # task-b (loop), task-c (column-t), task-e (loop) should WARN
  [[ "$output" == *"task-b"* ]]
  [[ "$output" == *"task-c"* ]]
  [[ "$output" == *"task-e"* ]]
}

@test "clean directory passes entirely" {
  run codebase lint:gum-table "$FIXTURES/clean"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Output format
# ============================================================================

@test "WARN output includes file path, category, and line number" {
  run codebase lint:gum-table "$FIXTURES/manual-padding/task-b"
  [ "$status" -ne 0 ]
  [[ "$output" =~ WARN.*task-b:\[loop-table\].*[0-9]+: ]]
}

@test "INFO output includes file path, category, and line number" {
  run codebase lint:gum-table "$FIXTURES/manual-padding/task-a"
  [[ "$output" =~ INFO.*task-a:\[padding\].*[0-9]+: ]]
}

# ============================================================================
# Error handling
# ============================================================================

@test "fails when target does not exist" {
  run codebase lint:gum-table /nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

# ============================================================================
# Relative path resolution (regression: codebase#24)
# ============================================================================

@test "relative path resolves against CALLER_PWD (dirty fixture)" {
  # Regression: relative targets resolved against codebase's install
  # dir, not the caller's cwd — silent false negatives.
  # Uses a real dirty fixture to prove the violation is found.
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/tasks"
  # A loop-table violation (high-confidence WARN).
  cat > "$tmp/tasks/fmt" <<'SCRIPT'
#!/usr/bin/env bash
while read -r name status; do
  printf "%-20s %s\n" "$name" "$status"
done < input.txt
SCRIPT

  CALLER_PWD="$tmp" run codebase lint:gum-table tasks
  [ "$status" -ne 0 ]
  [[ "$output" == *"WARN"* ]]
  [[ "$output" == *"loop-table"* ]]
  rm -rf "$tmp"
}
