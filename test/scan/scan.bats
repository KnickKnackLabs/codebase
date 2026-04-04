#!/usr/bin/env bats
# Tests for codebase scan

setup() {
  CODEBASE_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
  TASK="$CODEBASE_DIR/.mise/tasks/scan"
}

# Helper: run scan with usage_ vars set
run_scan() {
  local pattern=""
  local lang="bash"
  local target=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -l|--lang) lang="$2"; shift 2 ;;
      -p|--pattern) pattern="$2"; shift 2 ;;
      *) target="$1"; shift ;;
    esac
  done

  usage_pattern="$pattern" \
  usage_lang="$lang" \
  usage_target="$target" \
  bash "$TASK"
}

# ============================================================================
# Basic matching
# ============================================================================

@test "scan: finds mise run calls in extension-less task files" {
  run run_scan -p 'mise run $$$ARGS' "$FIXTURES"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mise run ci:lint"* ]]
  [[ "$output" == *"mise run ci:test --verbose"* ]]
  [[ "$output" == *"mise run util:clean"* ]]
}

@test "scan: reports file paths for matches" {
  run run_scan -p 'mise run $$$ARGS' "$FIXTURES"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ci/build"* ]]
  [[ "$output" == *"ci/test"* ]]
}

@test "scan: does not match _task calls" {
  run run_scan -p 'mise run $$$ARGS' "$FIXTURES"
  [ "$status" -eq 0 ]
  [[ "$output" != *"_task ci:build"* ]]
}

@test "scan: returns no output when pattern has no matches" {
  run run_scan -p 'docker run $$$ARGS' "$FIXTURES"
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

# ============================================================================
# Different patterns
# ============================================================================

@test "scan: finds _task calls with custom pattern" {
  run run_scan -p '_task $$$ARGS' "$FIXTURES"
  [ "$status" -eq 0 ]
  [[ "$output" == *"_task ci:build"* ]]
}

@test "scan: finds set -euo pipefail" {
  run run_scan -p 'set -euo pipefail' "$FIXTURES"
  [ "$status" -eq 0 ]
  # All 4 fixture files have it
  count=$(echo "$output" | grep -c "set -euo pipefail")
  [ "$count" -eq 4 ]
}

# ============================================================================
# Error handling
# ============================================================================

@test "scan: fails when no pattern provided" {
  run run_scan "$FIXTURES"
  [ "$status" -ne 0 ]
}

@test "scan: fails when target does not exist" {
  run run_scan -p 'mise run $$$ARGS' "/nonexistent/path"
  [ "$status" -ne 0 ]
}
