# AGENTS.md — codebase

Structural code analysis, linting & migrations for KnickKnackLabs repos.

---

## Commands

All commands are mise tasks in `.mise/tasks/`:

| Command | Description |
|---------|-------------|
| `mise run lint [target]` | Run configured codebase convention lints against a repo |
| `mise run scan <target> -p <pattern> [-l lang] [-e glob]` | Scan codebase for AST pattern matches via ast-grep |
| `mise run migrate <target>` | Migrate `mise run` calls to `_task` pattern (or reverse with `--reverse`) |
| `mise run pre-commit [--check] [--revert]` | Install/check/remove codebase pre-commit hook |
| `mise run test [args...]` | Run BATS test suite |

---

## Environment

| Key | Value |
|---|---|
| Repo | `$HOME/codebase` |
| Fork | `https://github.com/olavostauros/codebase` |
| Upstream | `https://github.com/KnickKnackLabs/codebase` |
| Tools | `bats`, `ast-grep`, `shellcheck`, `actionlint`, `ripgrep`, `fd` (managed via mise) |

---

## Usage

### Lint a repo

```bash
cd /path/to/target-repo
codebase lint
# or from anywhere:
mise run lint /path/to/target-repo
```

Lint rules are configured in the target repo's `mise.toml` under `[_.codebase]`:

```toml
[_.codebase]
lint = ["mise-settings", "gum-table", "shellcheck"]
```

### Available lint rules

| Rule | Description |
|------|-------------|
| `mise-settings` | Check that `mise.toml` has required settings (`quiet=true`, `task_output=interleave`) |
| `gum-table` | Detect manual table formatting using `column -t` or `printf %-Ns` that should use `gum table` |
| `shellcheck` | Run shellcheck against shell files in a codebase |
| `bats-test-task` | Enforce the canonical BATS test-task shape in `.mise/tasks/test` |
| `bats-test-helper` | Flag direct invocation of `.mise/tasks/*` scripts from BATS tests |
| `mcr-scope` | Forbid `MISE_CONFIG_ROOT` in `test/` and `lib/` |
| `caller-pwd-contract` | Check shiv caller-cwd environment variable contract |
| `github-actions` | Lint GitHub Actions workflows and create a KKL default workflow when missing |
| `or-true` | Classify risky unannotated `\|\| true` / `\|\| :` failure suppression |
| `mise-usage-examples` | Enforce `#USAGE example` directives for public argument-bearing `mise` tasks |

### Scan for patterns

```bash
codebase scan /path/to/repo -p "some pattern" -l bash
```

### Install pre-commit hook

```bash
cd /path/to/target-repo
codebase pre-commit
```

### Run tests

```bash
mise run test
mise run test lint/bats-test-task   # specific suite
```

---

## Test structure

Tests live in `test/` organized by feature area:

| Directory | Tests |
|-----------|-------|
| `test/lib/` | Unit tests for shared lib functions |
| `test/lint/` | Lint rule tests (one subdir per rule) |
| `test/migrations/` | Migration task tests |
| `test/pre-commit/` | Pre-commit hook tests |
| `test/scan/` | Scan task tests (includes AST fixtures) |

---

## Shared libs

| File | Purpose |
|------|---------|
| `lib/codebase-config.sh` | Repo resolution, lint rule discovery from `mise.toml` |
| `lib/shell-files.sh` | File discovery, path resolution (`resolve_target`) |

---

## Conventions

- Bash-first (no Node/Python runtime dependencies)
- `test/test_helper.bash` provides common test bootstrapping
- CI runs on ubuntu-latest and macos-latest via GitHub Actions
- Lint rules are simple bash scripts that inspect repo structure
- Comments use single-line section headers (`# === Section title ===`), never multi-line ruler blocks