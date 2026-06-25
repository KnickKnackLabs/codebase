#!/usr/bin/env bats
# Tests for lint:mise-usage-examples rule

load ../../test_helper

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# === Detection ===

@test "mise-usage-examples: passes on a repo where all tasks with args have examples" {
  run codebase lint:mise-usage-examples "$FIXTURES/clean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
}

@test "mise-usage-examples: flags a task that has #USAGE arg but no #USAGE example" {
  run codebase lint:mise-usage-examples "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty"* ]]
  [[ "$output" == *"missing #USAGE example"* ]]
}

@test "mise-usage-examples: flags a task that has #USAGE flag but no #USAGE example" {
  run codebase lint:mise-usage-examples "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty"* ]]
  [[ "$output" == *"deploy"*"missing #USAGE example"* ]]
}

@test "mise-usage-examples: flags boolean-only flags (no placeholder) without examples" {
  run codebase lint:mise-usage-examples "$FIXTURES/boolean-only"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"boolean-only"* ]]
  [[ "$output" == *"verbose"*"missing #USAGE example"* ]]
}

@test "mise-usage-examples: skips hidden tasks (#MISE hide=true) even without examples" {
  run codebase lint:mise-usage-examples "$FIXTURES/hidden"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"hidden"* ]]
  [[ "$output" != *"internal-tool"* ]]
}

@test "mise-usage-examples: skips tasks with no #USAGE arg/flag at all" {
  run codebase lint:mise-usage-examples "$FIXTURES/no-args"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"no-args"* ]]
}

@test "mise-usage-examples: respects inline codebase:ignore comment" {
  run codebase lint:mise-usage-examples "$FIXTURES/ignored-inline"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"ignored-inline"* ]]
}

@test "mise-usage-examples: respects repo-level codebase:ignore in mise.toml" {
  run codebase lint:mise-usage-examples "$FIXTURES/ignored-repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"*"ignored-repo (codebase:ignore)"* ]]
}

@test "mise-usage-examples: passes on a repo with no .mise/tasks directory" {
  run codebase lint:mise-usage-examples "$FIXTURES/no-tasks"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"no-tasks"* ]]
}

@test "mise-usage-examples: passes on empty repo (tasks dir exists but is empty)" {
  run codebase lint:mise-usage-examples "$FIXTURES/empty"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"empty"* ]]
}

@test "mise-usage-examples: flags only the offending task when others are clean" {
  run codebase lint:mise-usage-examples "$FIXTURES/mixed"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"mixed"* ]]
  # The failing task
  [[ "$output" == *"broken-task"* ]]
  # The clean task should not appear as FAIL
  [[ "$output" != *"greet"* ]]
}

@test "mise-usage-examples: flag output includes the task path relative to .mise/tasks" {
  run codebase lint:mise-usage-examples "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"greet"*"missing #USAGE example"* ]]
  [[ "$output" == *"deploy"*"missing #USAGE example"* ]]
}