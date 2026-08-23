#!/usr/bin/env bats
# Public-path contract for detecting repository Mise dispatch in BATS bodies.

load ../../test_helper
load test_helper
bats_require_minimum_version 1.5.0

@test "flags direct root dispatch with BATS run env and explicit root forms" {
  write_bats <<'BATS'
#!/usr/bin/env bats
@test "direct" {
  mise run lock
  run mise --quiet run list
  run env CALLER_PWD="$PWD" mise run status
  command mise run inspect
  run command mise run doctor
  MODE=test command mise run audit
  command env MODE=test mise run trace
  run command env MODE=test mise run report
  env MODE=test command mise run not-a-dispatch
  run env MODE=test command mise run also-not-a-dispatch
  run mise -C "$REPO_DIR" run verify
}
BATS

  run codebase lint:bats-public-task-path "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  fixture repo: 9 raw repository Mise dispatch(es)"* ]]
  [[ "$output" == *"test/example.bats:3: mise run lock"* ]]
  [[ "$output" == *"test/example.bats:6: command mise run inspect"* ]]
  [[ "$output" == *"test/example.bats:8: MODE=test command mise run audit"* ]]
  [[ "$output" == *"test/example.bats:13: run mise -C"* ]]
  [[ "$output" != *"not-a-dispatch"* ]]
}
@test "does not flag wrapper definitions or Mise text used as data" {
  write_bats <<'BATS'
#!/usr/bin/env bats
mytool() {
  (cd "$REPO_DIR" && mise run -q "$@")
}
@test "search syntax" {
  run rg 'mise run task' "$REPO_DIR"
  printf '%s\n' 'mise run example'
  run mytool list
}
BATS

  run codebase lint:bats-public-task-path "$TARGET"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OK    fixture"* ]]
}
@test "allows explicit alternate fixture workspaces" {
  write_bats <<'BATS'
#!/usr/bin/env bats
@test "fixture dispatch" {
  run mise -C "$fixture" run test
  run mise -C"$fixture" run test
  run env MODE=test mise --cd="$WORK_DIR" run verify
  run bash -c 'cd "$fixture" && env -u REPO_DIR mise run test'
}
BATS

  run codebase lint:bats-public-task-path "$TARGET"

  [ "$status" -eq 0 ]
}
@test "does not mistake canonical root for an alternate workspace" {
  write_bats <<'BATS'
#!/usr/bin/env bats
@test "root dispatch" {
  run mise --cd="${REPO_DIR}" run test
  run mise -C"$REPO_DIR" run test
  run mise -C "$REPO_DIR/" run test
  run mise -C "${REPO_DIR}/." run test
  run bash -c 'cd "$REPO_DIR" && env -u REPO_DIR mise run test'
  run bash -c 'cd "$fixture" && env -u REPO_DIR mise -C "$REPO_DIR" run test'
  run bash -c 'cd "$fixture" && env -u REPO_DIR mise -C"$REPO_DIR" run verify'
}
BATS

  run codebase lint:bats-public-task-path "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"7 raw repository Mise dispatch(es)"* ]]
}
@test "supports function-comment BATS syntax" {
  {
    printf '%s\n' '#!/usr/bin/env bats'
    printf '%s\n' 'dispatch() { # @''test'
    printf '%s\n' '  run mise run test' '}'
    printf '%s\n' 'function keyword_dispatch { # @''test'
    printf '%s\n' '  run mise run verify' '}'
  } > "$TARGET/test/example.bats"

  run codebase lint:bats-public-task-path "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"2 raw repository Mise dispatch(es)"* ]]
  [[ "$output" == *"test/example.bats:3:"* ]]
  [[ "$output" == *"test/example.bats:6:"* ]]
}
