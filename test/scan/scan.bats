#!/usr/bin/env bats
# Tests for codebase scan

setup() {
  CODEBASE_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  FIXTURES_A="$BATS_TEST_DIRNAME/fixtures"
  FIXTURES_B="$BATS_TEST_DIRNAME/fixtures-b"
  TASK="$CODEBASE_DIR/.mise/tasks/scan"
}

# Helper: run scan with usage_ vars set
run_scan() {
  local pattern=""
  local lang="bash"
  local targets=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -l|--lang) lang="$2"; shift 2 ;;
      -p|--pattern) pattern="$2"; shift 2 ;;
      *) targets+=("$1"); shift ;;
    esac
  done

  usage_pattern="$pattern" \
  usage_lang="$lang" \
  usage_targets="${targets[*]}" \
  bash "$TASK"
}

# ============================================================================
# Single target (basic matching)
# ============================================================================

@test "scan: finds mise run calls in extension-less task files" {
  run run_scan -p 'mise run $$$ARGS' "$FIXTURES_A"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mise run ci:lint"* ]]
  [[ "$output" == *"mise run ci:test --verbose"* ]]
  [[ "$output" == *"mise run util:clean"* ]]
}

@test "scan: reports file paths for matches" {
  run run_scan -p 'mise run $$$ARGS' "$FIXTURES_A"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ci/build"* ]]
  [[ "$output" == *"ci/test"* ]]
}

@test "scan: does not match _task calls" {
  run run_scan -p 'mise run $$$ARGS' "$FIXTURES_A"
  [ "$status" -eq 0 ]
  [[ "$output" != *"_task ci:build"* ]]
}

@test "scan: returns no output when pattern has no matches" {
  run run_scan -p 'docker run $$$ARGS' "$FIXTURES_A"
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

# ============================================================================
# Different patterns
# ============================================================================

@test "scan: finds _task calls with custom pattern" {
  run run_scan -p '_task $$$ARGS' "$FIXTURES_A"
  [ "$status" -eq 0 ]
  [[ "$output" == *"_task ci:build"* ]]
}

@test "scan: finds set -euo pipefail" {
  run run_scan -p 'set -euo pipefail' "$FIXTURES_A"
  [ "$status" -eq 0 ]
  count=$(echo "$output" | grep -c "set -euo pipefail")
  [ "$count" -eq 4 ]
}

# ============================================================================
# Multiple targets
# ============================================================================

@test "multi: finds matches across multiple codebases" {
  run run_scan -p 'mise run $$$ARGS' "$FIXTURES_A" "$FIXTURES_B"
  [ "$status" -eq 0 ]
  # fixtures-a has mise run calls
  [[ "$output" == *"mise run ci:lint"* ]]
  # fixtures-b has a mise run call
  [[ "$output" == *"mise run build"* ]]
}

@test "multi: prefixes output with codebase name" {
  run run_scan -p 'mise run $$$ARGS' "$FIXTURES_A" "$FIXTURES_B"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fixtures:"* ]]
  [[ "$output" == *"fixtures-b:"* ]]
}

@test "multi: handles mix of matching and non-matching targets" {
  run run_scan -p '_task $$$ARGS' "$FIXTURES_A" "$FIXTURES_B"
  [ "$status" -eq 0 ]
  # Only fixtures-a has _task calls
  [[ "$output" == *"fixtures:"* ]]
  [[ "$output" != *"fixtures-b:"* ]]
}

# ============================================================================
# Error handling
# ============================================================================

@test "error: fails when no pattern provided" {
  run run_scan "$FIXTURES_A"
  [ "$status" -ne 0 ]
}

@test "error: fails when target does not exist" {
  run run_scan -p 'mise run $$$ARGS' "/nonexistent/path"
  [ "$status" -ne 0 ]
}

@test "error: fails when any target in multi does not exist" {
  run run_scan -p 'mise run $$$ARGS' "$FIXTURES_A" "/nonexistent/path"
  [ "$status" -ne 0 ]
}
