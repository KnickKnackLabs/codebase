#!/usr/bin/env bats

@test "intentionally tests mise dispatch" {
  run mise run --help  # codebase:ignore bats-raw-mise-dispatch — testing mise help output
  [ "$status" -eq 0 ]
}