#!/usr/bin/env bats
# Public-path contract for persistent stderr redirection by redirection-only exec.

load ../../test_helper
bats_require_minimum_version 1.5.0

setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/.mise/tasks"
}

write_shell() {
  local repo="$1"
  local name="$2"
  mkdir -p "$repo/.mise/tasks"
  cat > "$repo/.mise/tasks/$name"
  chmod +x "$repo/.mise/tasks/$name"
}

@test "reports common persistent stderr redirections" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
exec 3<>"$tty" 2>/dev/null
exec 2>/dev/null
exec 3<>"$tty" 2>&-
exec 3<>"$tty" 2>&1
exec 3<>"$tty" 2>error.log
exec 2<>error.log
exec &>/dev/null
exec >&combined.log
BASH

  run codebase lint:exec-stderr-persistence "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo: 8 persistent stderr redirection(s)"* ]]
  [[ "$output" == *"probe:2: exec 3<>\"\$tty\" 2>/dev/null"* ]]
  [[ "$output" == *"probe:9: exec >&combined.log"* ]]
}

@test "reports redirection-only exec inside conditionals functions and multiline commands" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
probe() {
  if ! exec 3<>"$tty" 2>/dev/null; then
    printf 'failed\n' >&2
  fi
  exec \
    3<>"$tty" \
    2>/dev/null
}
BASH

  run codebase lint:exec-stderr-persistence "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"probe:3:"* ]]
  [[ "$output" == *"probe:6:"* ]]
  [[ "$output" == *"FAIL  repo: 2 persistent stderr redirection(s)"* ]]
}

@test "reports equivalent redirection-only exec invocation forms" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
\exec 2>/dev/null

exec -- 2>/dev/null

FOO=bar exec 2>/dev/null

command exec 2>/dev/null
BASH

  run codebase lint:exec-stderr-persistence "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo: 4 persistent stderr redirection(s)"* ]]
  [[ "$output" == *"probe:2: \\exec 2>/dev/null"* ]]
  [[ "$output" == *"probe:8: command exec 2>/dev/null"* ]]
}

@test "accepts process replacement and scoped execution contexts" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
exec child --flag 2>/dev/null
exec "$child" 2>error.log
{ exec 3<>"$tty"; } 2>/dev/null
( exec 3<>"$tty" 2>/dev/null )
value=$(exec 3<>"$tty" 2>/dev/null)
cat <(exec 3<>"$tty" 2>/dev/null)
BASH

  run codebase lint:exec-stderr-persistence "$REPO"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OK    repo"* ]]
}

@test "accepts comments strings lookalikes and non-stderr descriptor setup" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
# exec 2>/dev/null
printf '%s\n' 'exec 2>/dev/null'
myexec 2>/dev/null
exec 3<>"$tty"
exec 1>/dev/null
BASH

  run codebase lint:exec-stderr-persistence "$REPO"

  [ "$status" -eq 0 ]
}

@test "descriptor duplication requires an explicit restoration reason" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
exec 2>&3
exec 2>&10
exec 2>&"$saved_fd" # codebase:ignore exec-stderr-persistence -- restore the saved stderr descriptor
BASH

  run codebase lint:exec-stderr-persistence "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo: 2 persistent stderr redirection(s)"* ]]
  [[ "$output" == *"probe:2: exec 2>&3"* ]]
  [[ "$output" == *"probe:3: exec 2>&10"* ]]
  [[ "$output" != *"saved_fd"* ]]
}

@test "inline ignores must name the rule and include a reason" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
exec 3<>"$first" 2>/dev/null # codebase:ignore exec-stderr-persistence -- caller restores stderr
exec 3<>"$second" 2>/dev/null # codebase:ignore exec-stderr-persistence
BASH

  run codebase lint:exec-stderr-persistence "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo: 1 persistent stderr redirection(s)"* ]]
  [[ "$output" != *"\$first"* ]]
  [[ "$output" == *"\$second"* ]]
}

@test "a reason on the final line can classify a multiline exec" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
exec \
  3<>"$tty" \
  2>/dev/null # codebase:ignore exec-stderr-persistence -- restored immediately below
exec 2>&3 # codebase:ignore exec-stderr-persistence -- restore the saved stderr descriptor
BASH

  run codebase lint:exec-stderr-persistence "$REPO"

  [ "$status" -eq 0 ]
}

@test "target-level ignore skips the repository" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
exec 2>/dev/null
BASH
  cat > "$REPO/mise.toml" <<'TOML'
# codebase:ignore exec-stderr-persistence -- generated compatibility fixture
TOML

  run codebase lint:exec-stderr-persistence "$REPO"

  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP  repo (codebase:ignore)"* ]]
}

@test "discovers shell files outside mise tasks and extensionless shebang files" {
  mkdir -p "$REPO/lib" "$REPO/bin"
  cat > "$REPO/lib/probe.sh" <<'BASH'
#!/usr/bin/env bash
exec 2>/dev/null
BASH
  cat > "$REPO/bin/tool" <<'BASH'
#!/bin/sh
exec 2>&-
BASH

  run codebase lint:exec-stderr-persistence "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo: 2 persistent stderr redirection(s)"* ]]
  [[ "$output" == *"lib/probe.sh"* ]]
  [[ "$output" == *"bin/tool"* ]]
}

@test "quoted multi-target paths survive public Usage parsing" {
  local dirty="$BATS_TEST_TMPDIR/dirty repo"
  local clean="$BATS_TEST_TMPDIR/clean repo"
  write_shell "$dirty" probe <<'BASH'
#!/usr/bin/env bash
exec 2>/dev/null
BASH
  write_shell "$clean" probe <<'BASH'
#!/usr/bin/env bash
exec child 2>/dev/null
BASH

  run codebase lint:exec-stderr-persistence "$dirty" "$clean"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  dirty repo"* ]]
  [[ "$output" == *"OK    clean repo"* ]]
}

@test "caller-relative targets resolve through the public shim contract" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
exec 2>/dev/null
BASH
  CODEBASE_CALLER_PWD="$BATS_TEST_TMPDIR" run codebase lint:exec-stderr-persistence repo

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo"* ]]
}

@test "a target with no shell files passes clearly" {
  rm -rf "$REPO/.mise"
  printf 'plain\n' > "$REPO/README.md"

  run codebase lint:exec-stderr-persistence "$REPO"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OK    repo (no shell files found)"* ]]
}

@test "two dirty targets return the number of failing targets" {
  local other="$BATS_TEST_TMPDIR/other"
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
exec 2>/dev/null
BASH
  write_shell "$other" probe <<'BASH'
#!/usr/bin/env bash
exec 2>&-
BASH

  run codebase lint:exec-stderr-persistence "$REPO" "$other"

  [ "$status" -eq 2 ]
}

@test "missing and nonexistent targets fail through the public contract" {
  run codebase lint:exec-stderr-persistence
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required arg"* ]]
  [[ "$output" == *"<targets>"* ]]

  run codebase lint:exec-stderr-persistence "$REPO/missing"
  [ "$status" -ne 0 ]
  [[ "$output" == *"target does not exist"* ]]
}

@test "task help states the persistent current-shell boundary" {
  run bash -c 'cd "$REPO_DIR" && mise tasks info lint:exec-stderr-persistence'

  [ "$status" -eq 0 ]
  [[ "$output" == *"redirection-only exec"* ]]
  [[ "$output" == *"persistently redirect stderr"* ]]
}
