#!/usr/bin/env bats
# Tests for lint:bats-test-task rule

load ../../test_helper

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# ============================================================================
# Pass paths
# ============================================================================

@test "bats-test-task: passes on the canonical pattern" {
  run codebase lint:bats-test-task "$FIXTURES/clean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
}

@test "bats-test-task: passes when target has no .mise/tasks/test" {
  run codebase lint:bats-test-task "$FIXTURES/no-task"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"no-task"* ]]
  [[ "$output" == *"nothing to check"* ]]
}

@test "bats-test-task: passes on the shimmer variant (dir-based + --recursive)" {
  # Shimmer uses dir-based suite names ($TEST_DIR/$arg, not .bats files) and
  # appends --recursive. Both are legitimate — the rule shouldn't be that
  # prescriptive.
  run codebase lint:bats-test-task "$FIXTURES/shimmer-variant"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"shimmer-variant"* ]]
}

# ============================================================================
# Failure modes
# ============================================================================

@test "bats-test-task: flags missing USAGE arg spec" {
  run codebase lint:bats-test-task "$FIXTURES/missing-usage-arg"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"missing-usage-arg"* ]]
  [[ "$output" == *"missing #USAGE arg spec"* ]]
}

@test "bats-test-task: flags missing USAGE examples" {
  run codebase lint:bats-test-task "$FIXTURES/missing-examples"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing #USAGE example"* ]]
}

@test "bats-test-task: flags multiple bats invocations" {
  run codebase lint:bats-test-task "$FIXTURES/multiple-bats"
  [ "$status" -ne 0 ]
  [[ "$output" == *"2 'bats' invocations"* ]]
}

@test "bats-test-task: flags outer 'if \$#' wrapping bats" {
  run codebase lint:bats-test-task "$FIXTURES/if-dollar-hash"
  [ "$status" -ne 0 ]
  [[ "$output" == *"outer 'if"* ]]
  [[ "$output" == *"wraps bats"* ]]
}

@test "bats-test-task: flat pattern's *.bats globs do NOT count as invocations" {
  # Regression guard: an earlier regex counted every `bats` word including
  # `*.bats` extensions, so the canonical template showed 4–6 "invocations"
  # and wrongly failed. Only line-start `bats` or `exec bats` counts.
  run codebase lint:bats-test-task "$FIXTURES/clean"
  [ "$status" -eq 0 ]
  [[ "$output" != *"invocations found"* ]]
}

# ============================================================================
# Ignore directive
# ============================================================================

@test "bats-test-task: 'codebase:ignore bats-test-task' in mise.toml skips the target" {
  run codebase lint:bats-test-task "$FIXTURES/ignored-file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"*"ignored-file"* ]]
}

# ============================================================================
# Output details
# ============================================================================

@test "bats-test-task: fail output includes the remediation hint" {
  run codebase lint:bats-test-task "$FIXTURES/missing-usage-arg"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bats-tool-testing.md"* ]]
}

@test "bats-test-task: reports all issues for a multi-violation target" {
  run codebase lint:bats-test-task "$FIXTURES/if-dollar-hash"
  [ "$status" -ne 0 ]
  # if-dollar-hash has both the outer-if pattern AND 2 bats invocations.
  # Both should be reported in a single FAIL block.
  [[ "$output" == *"outer 'if"* ]]
  [[ "$output" == *"invocations"* ]]
}

# ============================================================================
# Error handling
# ============================================================================

@test "bats-test-task: fails when no targets given" {
  run codebase lint:bats-test-task
  [ "$status" -ne 0 ]
  # mise USAGE parser emits the error before our script runs.
}

@test "bats-test-task: fails when target does not exist" {
  run codebase lint:bats-test-task "/nonexistent/path/xyz"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

# ============================================================================
# Multi-target
# ============================================================================

@test "bats-test-task: accepts multiple targets and reports each" {
  run codebase lint:bats-test-task "$FIXTURES/clean" "$FIXTURES/missing-examples"
  [ "$status" -ne 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
  [[ "$output" == *"FAIL"*"missing-examples"* ]]
}
