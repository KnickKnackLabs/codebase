#!/usr/bin/env bats
# Public-path contract for credential-bearing Git remote URL output risks.

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

@test "reports direct remote variable output and naked git remote get-url" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
printf 'remote: %s\n' "$remote_url"
echo "${origin_url}"
mixed_url="$remote_url $(redact_url "$remote_url")"
printf '%s\n' "$mixed_url"
printf '%s\n' "$(obscure_filter "$remote_url")"
git remote get-url origin
git -C . remote get-url origin
other=public; git remote get-url origin
command -- git remote get-url origin
BASH

  run codebase lint:remote-url-output "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo: 8 credential-bearing remote URL output risk(s)"* ]]
  [[ "$output" == *"probe:2: prints a remote URL"* ]]
  [[ "$output" == *"probe:7: writes git remote get-url directly"* ]]
  [[ "$output" == *"probe:8: writes git remote get-url directly"* ]]
  [[ "$output" == *"probe:9: writes git remote get-url directly"* ]]
  [[ "$output" == *"probe:10: writes git remote get-url directly"* ]]
}

@test "follows a captured remote URL through a generically named variable" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
value=$(git -C . remote get-url origin)
copy="${value}"
printf '%s\n' "$value"
printf '%s\n' "$copy"
BASH

  run codebase lint:remote-url-output "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo: 2 credential-bearing remote URL output risk(s)"* ]]
  [[ "$output" == *"probe:4:"* ]]
  [[ "$output" == *"probe:5:"* ]]
}

@test "later assignments replace earlier taint and safety provenance" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
value=$(git remote get-url origin)
safe=$(redact_url "$value")
safe="$value"
printf '%s\n' "$safe"
value=public
printf '%s\n' "$value"
same=$(git remote get-url origin); same=public; printf '%s\n' "$same"
BASH

  run codebase lint:remote-url-output "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo: 1 credential-bearing remote URL output risk(s)"* ]]
  [[ "$output" == *"probe:5: prints a remote URL"* ]]
  [[ "$output" != *"probe:7:"* ]]
  [[ "$output" != *"probe:8:"* ]]
}

@test "propagates known captured output without guessing helper return semantics" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
probe() {
  local remote_url="$1"
  local tag captured result
  tag=$(release_tag_for "$remote_url")
  printf '%s\n' "$tag"
  captured=$(printf '%s' "$remote_url")
  printf '%s\n' "$captured"
  result=$(git ls-remote "$remote_url" 2>&1)
  printf '%s\n' "$result"
}
BASH

  run codebase lint:remote-url-output "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo: 2 credential-bearing remote URL output risk(s)"* ]]
  [[ "$output" != *"probe:6:"* ]]
  [[ "$output" == *"probe:8: prints a remote URL"* ]]
  [[ "$output" == *"probe:9: runs git ls-remote"* ]]
  [[ "$output" != *"probe:10:"* ]]
}

@test "accepts recognized redaction calls and nonexecuted lookalikes" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
remote_url=$(git remote get-url origin)
safe_url=$(redact_github_tokens "$remote_url")
printf '%s\n' "$safe_url"
printf '%s\n' "$(sanitize_url "$remote_url")"
printf '%s\n' "$(homes_redact_url "$remote_url")"
printf '%s\n' "$remote_url" | mask_credentials
captured=$(printf '%s' "$remote_url")
printf '%s\n' "$(scrub_tokens "$captured")"
printf '%s\n' "$remote_url" >/dev/null
git remote get-url origin >/dev/null
origin='ssh://git@github.com/owner/home.git'
path=${origin#ssh://git@github.com/}
login=${path%%/*}
printf '%s\n' "$login"
# printf '%s\n' "$remote_url"
printf '%s\n' '$remote_url'
printf '%s\n' 'git remote get-url origin'
BASH

  run codebase lint:remote-url-output "$REPO"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OK    repo"* ]]
}

@test "reports Git network commands whose remote-bearing stderr is exposed or captured" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
git clone "$remote_url" target
git fetch "$origin_url"
result=$(git ls-remote --tags "$repo_url" 2>&1)
git push "$remote_url" main 2>error.log
git -c protocol.version=2 ls-remote "$repo_url"
git clone "$remote_url" target; true 2>/dev/null
git fetch "$origin_url"; printf 'unrelated\n' | mask_credentials
command -p git clone "$remote_url" target
BASH

  run codebase lint:remote-url-output "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo: 8 credential-bearing remote URL output risk(s)"* ]]
  [[ "$output" == *"runs git clone"* ]]
  [[ "$output" == *"runs git ls-remote"* ]]
  [[ "$output" == *"runs git push"* ]]
}

@test "does not mistake later Git arguments for subcommands" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
git show clone "$remote_url"
git config remote get-url "$remote_url"
printf '%s\n' 'https://secret-token@github.example/repo.git'
printf '%s\n' 'ssh://git@github.example/owner/repo.git'
BASH

  run codebase lint:remote-url-output "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo: 1 credential-bearing remote URL output risk(s)"* ]]
  [[ "$output" == *"probe:4: prints a remote URL"* ]]
  [[ "$output" != *"runs git clone"* ]]
  [[ "$output" != *"writes git remote get-url"* ]]
  [[ "$output" != *"probe:5:"* ]]
}

@test "accepts named remotes and recognized Git stderr redaction" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
git fetch origin
git push "$remote_url" main 2> >(redact_github_tokens >&2)
git fetch "$origin_url" 2>/dev/null
git clone "$remote_url" target >/dev/null 2>&1
git ls-remote "$remote_url" 2>&1 | scrub_tokens
BASH

  run codebase lint:remote-url-output "$REPO"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OK    repo"* ]]
}

@test "reasoned inline and repository ignores remain explicit escape hatches" {
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
printf '%s\n' "$remote_url" # codebase:ignore remote-url-output -- fixture contains a public URL only
printf '%s\n' "$origin_url" # codebase:ignore remote-url-output
BASH

  run codebase lint:remote-url-output "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo: 1 credential-bearing remote URL output risk(s)"* ]]
  [[ "$output" != *"remote_url"* ]]
  [[ "$output" == *"origin_url"* ]]

  cat > "$REPO/mise.toml" <<'TOML'
# codebase:ignore remote-url-output -- generated fixture owns redaction elsewhere
TOML
  run codebase lint:remote-url-output "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP  repo (codebase:ignore)"* ]]
}

@test "discovers library and extensionless shell files" {
  mkdir -p "$REPO/lib" "$REPO/bin"
  cat > "$REPO/lib/probe.sh" <<'BASH'
#!/usr/bin/env bash
printf '%s\n' "$remote_url"
BASH
  cat > "$REPO/bin/tool" <<'BASH'
#!/bin/sh
git fetch "$origin_url"
BASH

  run codebase lint:remote-url-output "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo: 2 credential-bearing remote URL output risk(s)"* ]]
  [[ "$output" == *"lib/probe.sh"* ]]
  [[ "$output" == *"bin/tool"* ]]
}

@test "quoted multi-target paths survive public Usage parsing" {
  local dirty="$BATS_TEST_TMPDIR/dirty repo"
  local clean="$BATS_TEST_TMPDIR/clean repo"
  write_shell "$dirty" probe <<'BASH'
#!/usr/bin/env bash
printf '%s\n' "$remote_url"
BASH
  write_shell "$clean" probe <<'BASH'
#!/usr/bin/env bash
safe_url=$(project_redact_url "$remote_url")
printf '%s\n' "$safe_url"
BASH

  run codebase lint:remote-url-output "$dirty" "$clean"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  dirty repo"* ]]
  [[ "$output" == *"OK    clean repo"* ]]
}

@test "two dirty targets return the number of failing targets" {
  local other="$BATS_TEST_TMPDIR/other"
  write_shell "$REPO" probe <<'BASH'
#!/usr/bin/env bash
printf '%s\n' "$remote_url"
BASH
  write_shell "$other" probe <<'BASH'
#!/usr/bin/env bash
git remote get-url origin
BASH

  run codebase lint:remote-url-output "$REPO" "$other"

  [ "$status" -eq 2 ]
}

@test "ast-grep failures fail closed" {
  local mock_bin="$BATS_TEST_TMPDIR/mock-bin"
  export TMPDIR="$BATS_TEST_TMPDIR"
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

  run codebase lint:remote-url-output "$REPO"

  [ "$status" -ne 0 ]
  [[ "$output" == *"ast-grep could not inspect shell-file candidates"* ]]
  [[ "$output" == *"injected ast-grep failure"* ]]
  [[ "$output" != *"OK    repo"* ]]
  run find "$TMPDIR" -maxdepth 1 -name 'codebase-remote-url-output.*' -print
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "missing, nonexistent, and shell-free targets report clearly" {
  run codebase lint:remote-url-output
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required arg"* ]]
  [[ "$output" == *"<targets>"* ]]

  run codebase lint:remote-url-output "$REPO/missing"
  [ "$status" -ne 0 ]
  [[ "$output" == *"target does not exist"* ]]

  rm -rf "$REPO/.mise"
  printf 'plain\n' > "$REPO/README.md"
  run codebase lint:remote-url-output "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK    repo (no shell files found)"* ]]
}

@test "task help states the bounded credential-output contract" {
  run bash -c 'cd "$REPO_DIR" && mise tasks info lint:remote-url-output'

  [ "$status" -eq 0 ]
  [[ "$output" == *"credential-bearing Git remote URLs"* ]]
  [[ "$output" == *"output"* ]]
}
