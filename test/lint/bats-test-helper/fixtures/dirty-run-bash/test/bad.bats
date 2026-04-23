#!/usr/bin/env bats

setup() { TASK="$REPO_DIR/.mise/tasks/foo"; }

@test "runs foo via run bash" {
  run bash "$TASK"
  [ "$status" -eq 0 ]
}
