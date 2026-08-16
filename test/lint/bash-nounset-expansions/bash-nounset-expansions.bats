#!/usr/bin/env bats
# Shared behavior tests for Bash 3.2 nounset expansion lints.

load ../../test_helper
bats_require_minimum_version 1.5.0

setup() {
  FIXTURE="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$FIXTURE/.mise/tasks"
}

write_task() {
  local name="$1"
  cat > "$FIXTURE/.mise/tasks/$name"
  chmod +x "$FIXTURE/.mise/tasks/$name"
}

@test "argv: flags braced positional expansion under nounset" {
  write_task wrapper <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
exec child "${@}"
BASH

  run codebase lint:bash-empty-argv-forwarding "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *'FAIL  repo: 1 braced empty-argv expansion'* ]]
  [[ "$output" == *'exec child "${@}"'* ]]
  [[ "$output" == *'Use "$@" instead of "${@}"'* ]]
}

@test "argv: flags unquoted braced positional expansion under nounset" {
  write_task wrapper <<'BASH'
#!/usr/bin/env bash
set -u
exec child ${@}
BASH

  run codebase lint:bash-empty-argv-forwarding "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *'exec child ${@}'* ]]
}

@test "argv: accepts the unbraced positional form that is safe on Bash 3.2" {
  write_task wrapper <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
exec child "$@"
BASH

  run codebase lint:bash-empty-argv-forwarding "$FIXTURE"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OK    repo"* ]]
}

@test "argv: accepts the guarded alternate-value form" {
  write_task wrapper <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
exec child ${@+"${@}"}
BASH

  run codebase lint:bash-empty-argv-forwarding "$FIXTURE"

  [ "$status" -eq 0 ]
}

@test "argv: ignores braced examples in comments, strings, and quoted heredocs" {
  write_task wrapper <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
# Never write exec child "${@}" here.
printf '%s\n' 'exec child "${@}"'
cat <<'EXAMPLE'
exec child "${@}"
EXAMPLE
BASH

  run codebase lint:bash-empty-argv-forwarding "$FIXTURE"

  [ "$status" -eq 0 ]
}

@test "array: flags at-sign and star expansions under nounset" {
  write_task wrapper <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
args=()
child "${args[@]}" "${args[*]}"
BASH

  run codebase lint:bash-empty-array-expansions "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *'FAIL  repo: 2 empty-array expansion'* ]]
  [[ "$output" == *'child "${args[@]}" "${args[*]}"'* ]]
}

@test "array: flags loop and assignment contexts because Bash 3.2 fails before context matters" {
  write_task wrapper <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
args=()
copy=("${args[@]}")
for arg in "${args[@]}"; do
  printf '%s\n' "$arg"
done
BASH

  run codebase lint:bash-empty-array-expansions "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *'FAIL  repo: 2 empty-array expansion'* ]]
  [[ "$output" == *'copy=("${args[@]}")'* ]]
  [[ "$output" == *'for arg in "${args[@]}"'* ]]
}

@test "array: ignores examples in quoted heredocs" {
  write_task wrapper <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
cat <<'EXAMPLE'
child "${args[@]}"
EXAMPLE
BASH

  run codebase lint:bash-empty-array-expansions "$FIXTURE"

  [ "$status" -eq 0 ]
}

@test "array: accepts guarded at-sign and star forms" {
  write_task wrapper <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
args=()
child ${args[@]+"${args[@]}"} ${args[*]+"${args[*]}"}
BASH

  run codebase lint:bash-empty-array-expansions "$FIXTURE"

  [ "$status" -eq 0 ]
}

@test "both rules ignore hazards in files that do not enable nounset" {
  write_task wrapper <<'BASH'
#!/usr/bin/env bash
exec child "${@}" "${args[@]}"
BASH

  run codebase lint:bash-empty-argv-forwarding "$FIXTURE"
  [ "$status" -eq 0 ]

  run codebase lint:bash-empty-array-expansions "$FIXTURE"
  [ "$status" -eq 0 ]
}

@test "nounset examples in quoted heredocs do not activate either rule" {
  write_task wrapper <<'BASH'
#!/usr/bin/env bash
cat <<'EXAMPLE'
set -euo pipefail
EXAMPLE
child "${@}" "${args[@]}"
BASH

  run codebase lint:bash-empty-argv-forwarding "$FIXTURE"
  [ "$status" -eq 0 ]

  run codebase lint:bash-empty-array-expansions "$FIXTURE"
  [ "$status" -eq 0 ]
}

@test "both rules recognize set -o nounset after another command" {
  write_task wrapper <<'BASH'
#!/usr/bin/env bash
printf 'starting\n'; set -o nounset
child "${@}" "${args[@]}"
BASH

  run codebase lint:bash-empty-argv-forwarding "$FIXTURE"
  [ "$status" -eq 1 ]

  run codebase lint:bash-empty-array-expansions "$FIXTURE"
  [ "$status" -eq 1 ]
}

@test "nounset gating recognizes separated set options" {
  write_task wrapper <<'BASH'
#!/usr/bin/env bash
set -e -u -o pipefail
child "${@}" "${args[@]}"
BASH

  run codebase lint:bash-empty-argv-forwarding "$FIXTURE"
  [ "$status" -eq 1 ]

  run codebase lint:bash-empty-array-expansions "$FIXTURE"
  [ "$status" -eq 1 ]
}

@test "inline ignores must name the rule and explain the exception" {
  write_task wrapper <<'BASH'
#!/usr/bin/env bash
set -u
child "${@}" # codebase:ignore bash-empty-argv-forwarding
child "${args[@]}" # codebase:ignore bash-empty-array-expansions -- args is initialized nonempty above
BASH

  run codebase lint:bash-empty-argv-forwarding "$FIXTURE"
  [ "$status" -eq 1 ]
  [[ "$output" == *'child "${@}"'* ]]

  run codebase lint:bash-empty-array-expansions "$FIXTURE"
  [ "$status" -eq 0 ]
}

@test "file-level ignores remain rule-specific" {
  write_task wrapper <<'BASH'
#!/usr/bin/env bash
set -u
child "${@}" "${args[@]}"
BASH
  cat > "$FIXTURE/mise.toml" <<'TOML'
# codebase:ignore bash-empty-array-expansions -- generated compatibility fixture
TOML

  run codebase lint:bash-empty-array-expansions "$FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP  repo"* ]]

  run codebase lint:bash-empty-argv-forwarding "$FIXTURE"
  [ "$status" -eq 1 ]
}

@test "discovery checks shell files outside mise tasks" {
  mkdir -p "$FIXTURE/lib"
  cat > "$FIXTURE/lib/delegate.sh" <<'BASH'
#!/usr/bin/env bash
set -u
child "${@}" "${args[@]}"
BASH

  run codebase lint:bash-empty-argv-forwarding "$FIXTURE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lib/delegate.sh"* ]]

  run codebase lint:bash-empty-array-expansions "$FIXTURE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lib/delegate.sh"* ]]
}

@test "quoted multi-target paths survive public usage parsing" {
  local dirty="$BATS_TEST_TMPDIR/dirty repo"
  local clean="$BATS_TEST_TMPDIR/clean repo"
  mkdir -p "$dirty/.mise/tasks" "$clean/.mise/tasks"
  cat > "$dirty/.mise/tasks/wrapper" <<'BASH'
#!/usr/bin/env bash
set -u
child "${@}"
BASH
  cat > "$clean/.mise/tasks/wrapper" <<'BASH'
#!/usr/bin/env bash
set -u
child "$@"
BASH

  run codebase lint:bash-empty-argv-forwarding "$dirty" "$clean"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  dirty repo"* ]]
  [[ "$output" == *"OK    clean repo"* ]]
}

@test "two dirty targets return the number of failing targets" {
  local other="$BATS_TEST_TMPDIR/other"
  mkdir -p "$other/.mise/tasks"
  write_task wrapper <<'BASH'
#!/usr/bin/env bash
set -u
child "${args[@]}"
BASH
  cat > "$other/.mise/tasks/wrapper" <<'BASH'
#!/usr/bin/env bash
set -u
child "${other[@]}"
BASH

  run codebase lint:bash-empty-array-expansions "$FIXTURE" "$other"

  [ "$status" -eq 2 ]
}

@test "guarded and unsafe expansions on one line are classified independently" {
  write_task wrapper <<'BASH'
#!/usr/bin/env bash
  set -u
child ${args[@]+"${args[@]}"} "${other[@]}"
child ${@+"${@}"} "${@}"
BASH

  run codebase lint:bash-empty-array-expansions "$FIXTURE"
  [ "$status" -eq 1 ]
  [[ "$output" == *'FAIL  repo: 1 empty-array expansion'* ]]

  run codebase lint:bash-empty-argv-forwarding "$FIXTURE"
  [ "$status" -eq 1 ]
  [[ "$output" == *'FAIL  repo: 1 braced empty-argv expansion'* ]]
}

@test "macOS system Bash proves the compatibility boundary" {
  [[ "$OSTYPE" == darwin* ]] || skip "requires macOS system Bash 3.2"

  run /bin/bash -uc 'set --; printf x "$@"'
  [ "$status" -eq 0 ]

  run -127 /bin/bash -uc 'set --; printf x "${@}"'
  [ "$status" -eq 127 ]

  run -127 /bin/bash -uc 'set --; printf x ${@}'
  [ "$status" -eq 127 ]

  run -127 /bin/bash -uc 'args=(); printf x "${args[@]}"'
  [ "$status" -eq 127 ]
}

@test "missing targets fail through the public task contract" {
  run codebase lint:bash-empty-array-expansions

  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required arg"* ]]
  [[ "$output" == *"<targets>"* ]]
}

@test "nonexistent targets fail clearly" {
  run codebase lint:bash-empty-argv-forwarding "$FIXTURE/missing"

  [ "$status" -ne 0 ]
  [[ "$output" == *"target does not exist"* ]]
}
