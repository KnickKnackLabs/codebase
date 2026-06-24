#!/usr/bin/env bats

@test "locks the session" {
  run mise run -q lock
  [ "$status" -eq 0 ]
}