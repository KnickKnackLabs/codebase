#!/usr/bin/env bats
# Public-path contract for hidden process-substitution command statuses.

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

@test "reports input and output process substitutions in common contexts" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
while IFS= read -r path; do
  printf '%s\n' "$path"
done < <(git diff --name-only)
diff <(generate expected) <(generate actual)
tee >(compress >archive.gz) <input
BASH

  run codebase lint:process-substitution-status "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo: 4 hidden process-substitution command status(es)"* ]]
  [[ "$output" == *"probe:4: done < <(git diff --name-only)"* ]]
  [[ "$output" == *"probe:5: diff <(generate expected) <(generate actual)"* ]]
  [[ "$output" == *"probe:6: tee >(compress >archive.gz) <input"* ]]
  [[ "$output" == *"directly checked commands"* ]]
  [[ "$output" == *"intermediate snapshot"* ]]
}

@test "reports multiline process substitutions at their opening line" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
consume < <(
  producer \
    --flag
)
BASH

  run codebase lint:process-substitution-status "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"probe:2: consume < <("* ]]
}

@test "accepts checked snapshot producers and textual lookalikes" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
snapshot=$(mktemp)
if ! git diff --cached --name-only -z > "$snapshot"; then
  printf '%s\n' 'failed to inspect staged paths' >&2
  exit 1
fi
while IFS= read -r -d '' path; do
  printf '%s\n' "$path"
done < "$snapshot"
# while read -r value; do :; done < <(producer)
printf '%s\n' 'cat <(producer)'
BASH

  run codebase lint:process-substitution-status "$REPO"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OK    repo"* ]]
}

@test "inline ignores must name the rule and include a reason" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
cat <(best_effort) # codebase:ignore process-substitution-status -- absence is an accepted result
cat <(unchecked) # codebase:ignore process-substitution-status
cat <(wrong_rule) # codebase:ignore shellcheck -- intentional
BASH

  run codebase lint:process-substitution-status "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo: 2 hidden process-substitution command status(es)"* ]]
  [[ "$output" != *"best_effort"* ]]
  [[ "$output" == *"unchecked"* ]]
  [[ "$output" == *"wrong_rule"* ]]
}

@test "a reason on the final line classifies a multiline process substitution" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
consume < <(
  best_effort
) # codebase:ignore process-substitution-status -- empty input is explicitly acceptable
BASH

  run codebase lint:process-substitution-status "$REPO"

  [ "$status" -eq 0 ]
}

@test "reasoned repository ignore skips the target" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
cat <(producer)
BASH
  cat > "$REPO/mise.toml" <<'TOML'
# codebase:ignore process-substitution-status -- generated compatibility fixture
TOML

  run codebase lint:process-substitution-status "$REPO"

  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP  repo (codebase:ignore)"* ]]
}

@test "unreasoned repository ignore does not suppress findings" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
cat <(producer)
BASH
  cat > "$REPO/mise.toml" <<'TOML'
# codebase:ignore process-substitution-status
TOML

  run codebase lint:process-substitution-status "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo"* ]]
}

@test "discovers shell files outside mise tasks and extensionless shebang files" {
  mkdir -p "$REPO/lib" "$REPO/bin"
  cat > "$REPO/lib/probe.sh" <<'BASH'
#!/usr/bin/env bash
cat <(producer)
BASH
  cat > "$REPO/bin/tool" <<'BASH'
#!/bin/sh
cat <(producer)
BASH

  run codebase lint:process-substitution-status "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo: 2 hidden process-substitution command status(es)"* ]]
  [[ "$output" == *"lib/probe.sh"* ]]
  [[ "$output" == *"bin/tool"* ]]
}

@test "quoted multi-target paths survive public Usage parsing" {
  local dirty="$BATS_TEST_TMPDIR/dirty repo"
  local clean="$BATS_TEST_TMPDIR/clean repo"
  write_shell "$dirty" probe <<'BASH'
#!/usr/bin/env bash
cat <(producer)
BASH
  write_shell "$clean" probe <<'BASH'
#!/usr/bin/env bash
snapshot=$(mktemp)
producer > "$snapshot"
cat "$snapshot"
BASH

  run codebase lint:process-substitution-status "$dirty" "$clean"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  dirty repo"* ]]
  [[ "$output" == *"OK    clean repo"* ]]
}

@test "caller-relative targets resolve through the public shim contract" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
cat <(producer)
BASH
  CODEBASE_CALLER_PWD="$BATS_TEST_TMPDIR" run codebase lint:process-substitution-status repo

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo"* ]]
}

@test "a target with no shell files passes clearly" {
  rm -rf "$REPO/.mise"
  printf 'plain\n' > "$REPO/README.md"

  run codebase lint:process-substitution-status "$REPO"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OK    repo (no shell files found)"* ]]
}

@test "two dirty targets return the number of failing targets" {
  local other="$BATS_TEST_TMPDIR/other"
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
cat <(producer)
BASH
  write_shell "$other" probe <<'BASH'
#!/usr/bin/env bash
cat <(producer)
BASH

  run codebase lint:process-substitution-status "$REPO" "$other"

  [ "$status" -eq 2 ]
}

@test "ast-grep failures fail closed" {
  local mock_bin="$BATS_TEST_TMPDIR/mock-bin"
  mkdir -p "$mock_bin"
  cat > "$mock_bin/ast-grep" <<'BASH'
#!/usr/bin/env bash
printf '%s\n' 'injected ast-grep failure' >&2
exit 42
BASH
  chmod +x "$mock_bin/ast-grep"
  PATH="$mock_bin:$PATH"
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
printf 'clean\n'
BASH

  run codebase lint:process-substitution-status "$REPO"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ast-grep could not scan"* ]]
  [[ "$output" == *"injected ast-grep failure"* ]]
  [[ "$output" != *"OK    repo"* ]]
}

@test "missing and nonexistent targets fail through the public contract" {
  run codebase lint:process-substitution-status
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required arg"* ]]
  [[ "$output" == *"<targets>"* ]]

  run codebase lint:process-substitution-status "$REPO/missing"
  [ "$status" -ne 0 ]
  [[ "$output" == *"target does not exist"* ]]
}

@test "task help states the status-loss boundary" {
  run bash -c 'cd "$REPO_DIR" && mise tasks info lint:process-substitution-status'

  [ "$status" -eq 0 ]
  [[ "$output" == *"process substitutions"* ]]
  [[ "$output" == *"command status is hidden"* ]]
}
