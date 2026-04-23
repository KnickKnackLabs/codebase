#!/usr/bin/env bats

@test "runs a nested task" {
  run "$REPO_DIR/.mise/tasks/lint/check" --json
  [ "$status" -eq 0 ]
}

@test "runs another nested task via bash" {
  bash "$REPO_DIR/.mise/tasks/lint/mcr-scope" target
}
