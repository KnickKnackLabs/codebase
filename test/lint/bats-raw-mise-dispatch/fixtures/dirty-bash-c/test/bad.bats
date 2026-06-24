#!/usr/bin/env bats

@test "locks via bash -c" {
  run env REPO_DIR="$PWD" bash -c 'cd "$REPO_DIR" && mise run -q lock'
  [ "$status" -eq 0 ]
}