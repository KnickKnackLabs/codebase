#!/usr/bin/env bats
# Public-path contract for detecting repository Mise dispatch in BATS bodies.

load ../../test_helper
load test_helper
bats_require_minimum_version 1.5.0

@test "flags static nested bash payloads that bypass a wrapper" {
  write_bats <<'BATS'
#!/usr/bin/env bats
@test "stale caller" {
  run bash -c 'cd "$REPO_DIR" && CALLER_PWD="$1" mise run -q list --json' _ "$stale"
  MODE=test bash -c 'mise run verify'
  run bash -lc 'mise run status'
}
BATS

  run codebase lint:bats-public-task-path "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"3 raw repository Mise dispatch(es)"* ]]
  [[ "$output" == *"test/example.bats:3: run bash -c"* ]]
  [[ "$output" == *"test/example.bats:4: MODE=test bash -c"* ]]
  [[ "$output" == *"test/example.bats:5: run bash -lc"* ]]
}
@test "inspects double-quoted static shell payloads" {
  write_bats <<'BATS'
#!/usr/bin/env bats
@test "nested" {
  run bash -c "cd \"\$REPO_DIR\" && mise run list"
}
BATS

  run codebase lint:bats-public-task-path "$TARGET"

  [ "$status" -eq 1 ]
}
@test "does not claim to resolve dynamic shell payloads" {
  write_bats <<'BATS'
#!/usr/bin/env bats
@test "dynamic internal unit" {
  script="${COMMON_SRC}; call_internal"
  run bash -c "$script"
}
BATS

  run codebase lint:bats-public-task-path "$TARGET"

  [ "$status" -eq 0 ]
}
