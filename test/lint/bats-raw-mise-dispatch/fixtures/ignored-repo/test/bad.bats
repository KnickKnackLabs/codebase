#!/usr/bin/env bats

@test "locks the session" do
  run mise run -q lock
  [ "$status" -eq 0 ]
}