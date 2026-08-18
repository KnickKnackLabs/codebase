#!/usr/bin/env bats
# Public-path tests for Codebase's self-hosting test task.

load ../test_helper

@test "test task runs an exact BATS file" {
  run codebase test test/test-task/fixtures/sample.bats

  [ "$status" -eq 0 ]
  [[ "$output" == *"1..2"* ]]
  [[ "$output" == *"alpha with spaces"* ]]
  [[ "$output" == *"beta"* ]]
}

@test "test task resolves a suite directory under test" {
  run codebase test test-task/fixtures

  [ "$status" -eq 0 ]
  [[ "$output" == *"1..2"* ]]
}

@test "test task forwards quoted BATS arguments without an extra separator" {
  run codebase test test/test-task/fixtures/sample.bats --filter "alpha with spaces"

  [ "$status" -eq 0 ]
  [[ "$output" == *"1..1"* ]]
  [[ "$output" == *"alpha with spaces"* ]]
  [[ "$output" != *"beta"* ]]
}

@test "test task clears inherited variadic arguments when none are passed" {
  export usage_args="test/does-not-exist.bats"

  run codebase test --filter "resolve_target: absolute path passes through unchanged"

  [ "$status" -eq 0 ]
  [[ "$output" == *"1..1"* ]]
  [[ "$output" == *"resolve_target: absolute path passes through unchanged"* ]]
}
