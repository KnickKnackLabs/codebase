#!/usr/bin/env bats
# Tests for lint:mise-run-quiet rule

load ../../test_helper

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# ============================================================================
# Detection
# ============================================================================

@test "mise-run-quiet: passes on a clean codebase (no mise run calls)" {
  run codebase lint:mise-run-quiet "$FIXTURES/clean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "mise-run-quiet: passes when -q is already used" {
  run codebase lint:mise-run-quiet "$FIXTURES/clean-already-quiet"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "mise-run-quiet: flags mise run in command substitution" {
  run codebase lint:mise-run-quiet "$FIXTURES/dirty-command-sub"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty-command-sub"* ]]
  [[ "$output" == *"[command-sub]"* ]]
  [[ "$output" == *'$(mise run build)'* ]]
}

@test "mise-run-quiet: flags mise run in eval" {
  run codebase lint:mise-run-quiet "$FIXTURES/dirty-eval"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty-eval"* ]]
  [[ "$output" == *"[eval]"* ]]
  [[ "$output" == *'eval "$(mise run env)"'* ]]
}

@test "mise-run-quiet: warns on mise run in pipeline" {
  run codebase lint:mise-run-quiet "$FIXTURES/dirty-pipe"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty-pipe"* ]]
  [[ "$output" == *"[pipeline]"* ]]
  [[ "$output" == *'mise run check | grep error'* ]]
}

@test "mise-run-quiet: flags multiple violations in one file" {
  run codebase lint:mise-run-quiet "$FIXTURES/dirty-mixed"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty-mixed"* ]]
  [[ "$output" == *"[command-sub]"* ]]
  [[ "$output" == *"[eval]"* ]]
  [[ "$output" == *"[pipeline]"* ]]
}

@test "mise-run-quiet: fail output includes the violating file path" {
  run codebase lint:mise-run-quiet "$FIXTURES/dirty-command-sub"
  [ "$status" -ne 0 ]
  [[ "$output" == *".mise/tasks/t"* ]]
}

@test "mise-run-quiet: fail output suggests adding -q" {
  run codebase lint:mise-run-quiet "$FIXTURES/dirty-command-sub"
  [ "$status" -ne 0 ]
  [[ "$output" == *"mise run -q"* ]]
}

# ============================================================================
# Safe contexts
# ============================================================================

@test "mise-run-quiet: does not flag bare mise run (interactive)" {
  run codebase lint:mise-run-quiet "$FIXTURES/dirty-mixed"
  [ "$status" -ne 0 ]
  # Should flag the violations but NOT the bare 'mise run status' line
  [[ "$output" == *"FAIL"* ]]
  # The bare line should not appear in the output
  local bare_count
  bare_count=$(echo "$output" | grep -c "mise run status" || true)
  # It may appear in the hint text, but should not be flagged as a violation
  [[ "$output" != *"[command-sub]".*"mise run status"* ]]
  [[ "$output" != *"[eval]".*"mise run status"* ]]
  [[ "$output" != *"[pipeline]".*"mise run status"* ]]
}

@test "mise-run-quiet: does not flag mise run with stderr redirect" {
  run codebase lint:mise-run-quiet "$FIXTURES/dirty-mixed"
  [ "$status" -ne 0 ]
  # The stderr redirect line should not appear as a violation
  [[ "$output" != *"mise run lint 2>/dev/null"* ]]
}

@test "mise-run-quiet: does not flag mise run -q in command substitution" {
  run codebase lint:mise-run-quiet "$FIXTURES/clean-already-quiet"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ============================================================================
# Ignore mechanisms
# ============================================================================

@test "mise-run-quiet: respects file-level codebase:ignore" {
  run codebase lint:mise-run-quiet "$FIXTURES/ignored-file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"*"ignored-file"* ]]
}

@test "mise-run-quiet: respects inline codebase:ignore with reason" {
  run codebase lint:mise-run-quiet "$FIXTURES/ignored-inline"
  [ "$status" -ne 0 ]
  # Should flag the eval line (no ignore) but not the command sub line (has ignore)
  [[ "$output" == *"[eval]"* ]]
  # The ignored line should not appear as a violation
  [[ "$output" != *"codebase:ignore mise-run-quiet"* ]]
}

# ============================================================================
# Edge cases
# ============================================================================

@test "mise-run-quiet: skips directories with no shell files" {
  run codebase lint:mise-run-quiet "$FIXTURES/no-shell-files"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"no shell files"* ]]
}

@test "mise-run-quiet: handles multiple targets" {
  run codebase lint:mise-run-quiet "$FIXTURES/clean" "$FIXTURES/dirty-command-sub"
  [ "$status" -ne 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
  [[ "$output" == *"FAIL"*"dirty-command-sub"* ]]
}

@test "mise-run-quiet: does not flag 'mise run' in comments" {
  run codebase lint:mise-run-quiet "$FIXTURES/clean"
  [ "$status" -eq 0 ]
  # The clean fixture has no mise run calls at all
  [[ "$output" == *"OK"* ]]
}

@test "mise-run-quiet: does not flag mise run with flags (not just bare)" {
  run codebase lint:mise-run-quiet "$FIXTURES/dirty-command-sub"
  [ "$status" -ne 0 ]
  # Should flag both $(mise run build) and $(mise run count --all)
  [[ "$output" == *"mise run build"* ]]
  [[ "$output" == *"mise run count"* ]]
}