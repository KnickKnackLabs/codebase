#!/usr/bin/env bats

@test "runs list" {
  run "$REPO_DIR/.mise/tasks/list" --json
  [ "$status" -eq 0 ]
}
