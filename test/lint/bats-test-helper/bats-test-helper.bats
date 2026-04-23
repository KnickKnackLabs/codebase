#!/usr/bin/env bats
# Tests for lint:bats-test-helper rule

load ../../test_helper

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# ============================================================================
# Pass paths
# ============================================================================

@test "bats-test-helper: passes on clean wrapper-based tests" {
  run codebase lint:bats-test-helper "$FIXTURES/clean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
}

@test "bats-test-helper: passes when target has no test/ dir" {
  run codebase lint:bats-test-helper "$FIXTURES/empty"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"empty"* ]]
  [[ "$output" == *"no test/ files found"* ]]
}

# ============================================================================
# Invocation signatures — each form fails
# ============================================================================

@test "bats-test-helper: flags 'bash \$TASK' (var whose name contains TASK)" {
  run codebase lint:bats-test-helper "$FIXTURES/dirty-task-var"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty-task-var"* ]]
  [[ "$output" == *"bash"*'$TASK'* ]]
}

@test "bats-test-helper: flags 'bash \"…/.mise/tasks/X\"' (literal task path)" {
  run codebase lint:bats-test-helper "$FIXTURES/dirty-task-path"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty-task-path"* ]]
  [[ "$output" == *".mise/tasks/foo"* ]]
}

@test "bats-test-helper: flags 'run \"…/.mise/tasks/X\"' (bats run with task path)" {
  run codebase lint:bats-test-helper "$FIXTURES/dirty-run-path"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty-run-path"* ]]
  [[ "$output" == *".mise/tasks/list"* ]]
}

@test "bats-test-helper: flags 'run bash \$TASK' (nested form)" {
  run codebase lint:bats-test-helper "$FIXTURES/dirty-run-bash"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty-run-bash"* ]]
  # Assert on fragments to avoid the rule self-flagging this file: the
  # literal 'run bash "$TASK"' would match the invocation regex, but
  # splitting it across the glob keeps the rule clean on its own tests.
  [[ "$output" == *'run bash'*'"$TASK"'* ]]
}

# ============================================================================
# False positives — none of these are actual invocations
# ============================================================================

@test "bats-test-helper: does NOT flag reading a task file as data (grep/cat)" {
  # Regression guard: 'grep "$MCR/.mise/tasks/foo"' reads the script, doesn't
  # invoke it. 'cat > "$fake/.mise/tasks/x" <<EOF' writes a fixture.
  # Passing '.mise/tasks/ci/*' as an argument to another tool is also fine.
  run codebase lint:bats-test-helper "$FIXTURES/false-positives"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ============================================================================
# Ignore directives
# ============================================================================

@test "bats-test-helper: inline '# codebase:ignore' suppresses a single line" {
  run codebase lint:bats-test-helper "$FIXTURES/ignored-inline"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "bats-test-helper: 'codebase:ignore bats-test-helper' in mise.toml skips the target" {
  run codebase lint:bats-test-helper "$FIXTURES/ignored-file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"*"ignored-file"* ]]
}

# ============================================================================
# Output details
# ============================================================================

@test "bats-test-helper: fail output includes file:line citations" {
  run codebase lint:bats-test-helper "$FIXTURES/dirty-task-var"
  [ "$status" -ne 0 ]
  [[ "$output" == *"test/bad.bats:"*":"* ]]
}

@test "bats-test-helper: fail output includes the remediation hint" {
  run codebase lint:bats-test-helper "$FIXTURES/dirty-task-var"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bats-tool-testing.md"* ]]
  [[ "$output" == *"Call the Tool"* ]]
}

# ============================================================================
# Error handling
# ============================================================================

@test "bats-test-helper: fails when no targets given" {
  run codebase lint:bats-test-helper
  [ "$status" -ne 0 ]
  # mise USAGE parser emits the error before our script runs.
}

@test "bats-test-helper: fails when target does not exist" {
  run codebase lint:bats-test-helper "/nonexistent/path/xyz"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

# ============================================================================
# Multi-target
# ============================================================================

@test "bats-test-helper: accepts multiple targets and reports each" {
  run codebase lint:bats-test-helper "$FIXTURES/clean" "$FIXTURES/dirty-task-var"
  [ "$status" -ne 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
  [[ "$output" == *"FAIL"*"dirty-task-var"* ]]
}
