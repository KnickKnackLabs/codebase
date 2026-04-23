#!/usr/bin/env bats
# Tests for lint:or-true rule

load ../../test_helper

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# ============================================================================
# Detection
# ============================================================================

@test "or-true: passes on a clean codebase" {
  run codebase lint:or-true "$FIXTURES/clean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
}

@test "or-true: flags '|| true' as a violation" {
  run codebase lint:or-true "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty"* ]]
  [[ "$output" == *"|| true"* ]]
}

@test "or-true: flags '|| :' as a violation" {
  run codebase lint:or-true "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"|| :"* ]]
}

@test "or-true: flags '||:' (unspaced) as a violation" {
  run codebase lint:or-true "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"||:"* ]]
}

@test "or-true: fail output names seven occurrences in the dirty fixture" {
  run codebase lint:or-true "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"7 occurrence"* ]]
}

@test "or-true: flags '|| true>file' (redirect terminator)" {
  # Regression: terminator class was missing '>'/'<', so
  # 'cmd || true>/tmp/foo' (valid shell) went unflagged.
  run codebase lint:or-true "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"|| true>/tmp/discarded"* ]]
}

@test "or-true: flags '|| :>file' (colon-truncation trick)" {
  run codebase lint:or-true "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"|| :>/tmp/emptied"* ]]
}

@test "or-true: flags '|| true)' inside command substitution" {
  # Regression: earlier regex only terminated on whitespace/EOL/';'/'&',
  # missing the very common 'foo=\$(cmd || true)' shape.
  run codebase lint:or-true "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"|| true)"* ]]
}

@test "or-true: fail output includes the violating file path" {
  run codebase lint:or-true "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"broken"* ]]
}

@test "or-true: fail output includes the if-not remediation hint" {
  run codebase lint:or-true "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"if !"* ]]
}

# ============================================================================
# Ignore directives
# ============================================================================

@test "or-true: inline '# codebase:ignore' skips the line" {
  run codebase lint:or-true "$FIXTURES/ignored-inline"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"ignored-inline"* ]]
}

@test "or-true: 'codebase:ignore or-true' in mise.toml skips the whole target" {
  run codebase lint:or-true "$FIXTURES/ignored-file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"*"ignored-file"* ]]
}

# ============================================================================
# Scope / discovery
# ============================================================================

@test "or-true: walks the whole target — finds hits outside .mise/tasks and lib/" {
  run codebase lint:or-true "$FIXTURES/broad-walk"
  [ "$status" -ne 0 ]
  [[ "$output" == *"scripts/deploy.sh"* ]]
  [[ "$output" == *"bin/tool"* ]]
}

@test "or-true: works on a codebase with no mise.toml" {
  run codebase lint:or-true "$FIXTURES/no-toml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"no-toml"* ]]
}

@test "or-true: passes on a codebase with no shell files" {
  run codebase lint:or-true "$FIXTURES/empty"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"empty"* ]]
  [[ "$output" == *"no shell files"* ]]
}

# ============================================================================
# Discovery correctness
# ============================================================================

@test "or-true: discovery skips non-bash/sh shebangs (fish, zsh, …)" {
  # Regression: the shebang regex '^#!.*(bash|sh)\b' matched 'sh' as
  # a suffix of fish/zsh/csh/dash/ksh. Broaden-fix added a leading
  # word boundary. Fixture contains a fish script with '|| true';
  # if discovery emits it, the rule fails — we assert it passes.
  run codebase lint:or-true "$FIXTURES/shebang-overmatch"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"shebang-overmatch"* ]]
}

@test "or-true: discovery prunes .git/ (hooks with '|| true' are ignored)" {
  # Regression: a committed fixture can't contain a real .git/ directory
  # (git refuses). Build it inline. The hook contains '|| true' AND we
  # plant a clean shell file at the top of the target — if the prune
  # fails, the rule will flag the hook; if the walk silently skips
  # everything, the clean file wouldn't be reported as scanned either.
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.git/hooks" "$tmp/.mise/tasks"
  cat > "$tmp/.git/hooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
# If the prune fails, this '|| true' will be flagged.
echo pre-commit || true
EOF
  cat > "$tmp/.mise/tasks/greet" <<'EOF'
#!/usr/bin/env bash
echo hi
EOF

  run codebase lint:or-true "$tmp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  # One shell file scanned (the greet task), zero from .git— prove the
  # walk did find files, so the pass isn't vacuous.
  [[ "$output" == *"1 file(s) clean"* ]]
  rm -rf "$tmp"
}

# ============================================================================
# Comment handling
# ============================================================================

@test "or-true: does not flag '|| true' inside a single-quoted string" {
  # Accidental protection: the closing quote ''' is not in the
  # terminator class, so 'echo '"'"'foo || true'"'"'' goes unflagged.
  # Codifying this behavior so we notice if the regex changes.
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.mise/tasks"
  cat > "$tmp/.mise/tasks/t" <<'EOF'
#!/usr/bin/env bash
echo 'foo || true'
EOF
  run codebase lint:or-true "$tmp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  rm -rf "$tmp"
}

@test "or-true: does not flag '|| true' inside a full-line comment" {
  # Built inline to avoid a dedicated fixture dir — prove comment lines
  # are excluded from the scan.
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.mise/tasks"
  cat > "$tmp/.mise/tasks/t" <<'EOF'
#!/usr/bin/env bash
# Note: do not write 'foo || true' — prefer 'if !'.
echo ok
EOF
  run codebase lint:or-true "$tmp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  rm -rf "$tmp"
}

# ============================================================================
# Multi-target
# ============================================================================

@test "or-true: checks multiple targets and reports each" {
  run codebase lint:or-true "$FIXTURES/clean" "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
  [[ "$output" == *"FAIL"*"dirty"* ]]
}

@test "or-true: exit code is the number of failing targets" {
  run codebase lint:or-true "$FIXTURES/dirty" "$FIXTURES/broad-walk"
  [ "$status" -eq 2 ]
}

# ============================================================================
# Error paths
# ============================================================================

@test "or-true: fails when target does not exist" {
  run codebase lint:or-true "$FIXTURES/does-not-exist"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "or-true: fails when no targets given" {
  run codebase lint:or-true
  [ "$status" -ne 0 ]
  # Same convention as lint:shellcheck — asserting on mise USAGE's error
  # text so we break loudly if a mise upgrade reformats it.
  [[ "$output" == *"Missing required arg"* ]]
  [[ "$output" == *"<targets>"* ]]
}
