#!/usr/bin/env bats
# Tests for lint:bats-python-one-liner rule

load ../../test_helper

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# Pass paths

@test "bats-python-one-liner: passes on clean codebase with heredoc Python" {
  run codebase lint:bats-python-one-liner "$FIXTURES/clean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
}

@test "bats-python-one-liner: passes when target has no test/ dir" {
  run codebase lint:bats-python-one-liner "$FIXTURES/empty"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"empty"* ]]
  [[ "$output" == *"no test/ .bats files found"* ]]
}

@test "bats-python-one-liner: does not flag short harmless python3 -c print" {
  run codebase lint:bats-python-one-liner "$FIXTURES/clean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# Detection

@test "bats-python-one-liner: flags python3 -c with assert" {
  run codebase lint:bats-python-one-liner "$FIXTURES/dirty-assert"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty-assert"* ]]
  [[ "$output" == *"python3 -c"* ]]
  [[ "$output" == *"assert"* ]]
}

@test "bats-python-one-liner: flags python -c with assert" {
  run codebase lint:bats-python-one-liner "$FIXTURES/dirty-python"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty-python"* ]]
  [[ "$output" == *"python -c"* ]]
  [[ "$output" == *"assert"* ]]
}

@test "bats-python-one-liner: flags long python3 -c with assert" {
  run codebase lint:bats-python-one-liner "$FIXTURES/dirty-long"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty-long"* ]]
  [[ "$output" == *"assert"* ]]
}

# False positives — these should NOT be flagged

@test "bats-python-one-liner: does NOT flag heredoc Python" {
  run codebase lint:bats-python-one-liner "$FIXTURES/heredoc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# Ignore directives

@test "bats-python-one-liner: inline '# codebase:ignore' suppresses a single line" {
  run codebase lint:bats-python-one-liner "$FIXTURES/ignored-inline"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "bats-python-one-liner: 'codebase:ignore bats-python-one-liner' in mise.toml skips target" {
  run codebase lint:bats-python-one-liner "$FIXTURES/ignored-file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"*"ignored-file"* ]]
}

# Output details

@test "bats-python-one-liner: fail output includes file:line citations" {
  run codebase lint:bats-python-one-liner "$FIXTURES/dirty-assert"
  [ "$status" -ne 0 ]
  [[ "$output" == *"test/bad.bats:"*":"* ]]
}

@test "bats-python-one-liner: fail output includes remediation hint" {
  run codebase lint:bats-python-one-liner "$FIXTURES/dirty-assert"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bats-tool-testing.md"* ]]
  [[ "$output" == *"heredoc"* ]]
}

# Error handling

@test "bats-python-one-liner: fails when no targets given" {
  run codebase lint:bats-python-one-liner
  [ "$status" -ne 0 ]
}

@test "bats-python-one-liner: fails when target does not exist" {
  run codebase lint:bats-python-one-liner "/nonexistent/path/xyz"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

# Multi-target

@test "bats-python-one-liner: accepts multiple targets and reports each" {
  run codebase lint:bats-python-one-liner "$FIXTURES/clean" "$FIXTURES/dirty-assert"
  [ "$status" -ne 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
  [[ "$output" == *"FAIL"*"dirty-assert"* ]]
}
