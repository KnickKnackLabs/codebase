# AGENTS.md — codebase

**Structural code analysis, linting & migrations.** A toolbox of convention lints, AST-based scanning, and codemod migrations for KnickKnackLabs repos. Designed to be used as a shiv dependency by other repos.

## Commands

| Command | Description |
|---------|-------------|
| `lint [target]` | Run all configured convention lints (from repo's `[_.codebase]` mise config) |
| `lint:<name> <targets...>` | Run a specific lint check by name |
| `scan <targets...> -p <pattern> -l <lang>` | AST pattern matching via ast-grep |
| `migrate task-pattern <target>` | Migrate mise run calls to `_task` pattern (or reverse) |
| `pre-commit [--check \| --revert]` | Install, check, or remove the codebase pre-commit hook |
| `test [args...]` | Run the BATS test suite |

### Available lint checks

| Lint | What it checks |
|------|---------------|
| `mise-settings` | `mise.toml` has required settings (`experimental`, `quiet`, `task_output`) |
| `gum-table` | Detects manual table formatting that should use `gum table` |
| `bats-test-helper` | Flags direct script invocation from BATS tests (should call the tool) |
| `bats-test-task` | Enforces canonical BATS test-task shape in `.mise/tasks/test` |
| `mcr-scope` | Forbids `MISE_CONFIG_ROOT` in `test/` and `lib/` |
| `or-true` | Classifies risky unannotated `\|\| true` / `\|\| :` failure suppression |
| `shellcheck` | Runs shellcheck against shell files |
| `caller-pwd-contract` | Checks shiv caller-cwd environment variable contract |
| `github-actions` | Lints workflows and creates a default KKL workflow when missing |
| `bash-empty-array-expansions` | Flags empty array expansions under nounset (macOS Bash 3.2 compat) |
| `usage-flag-naming` | Detects #USAGE flag directives where flag name and arg placeholder produce different `usage_*` env var names (flag silently does nothing) |

## Install

```bash
shiv install codebase
```

Projects add it to `mise.toml`:

```toml
[tools]
"shiv:codebase" = "latest"

[_.codebase]
lint = [
  "mise-settings",
  "bats-test-task",
  "or-true",
  "shellcheck",
  "caller-pwd-contract",
  "github-actions",
]
```

## Key patterns

- Lint checks are per-repo opt-in via `[_.codebase]` in `mise.toml`
- Uses `ast-grep` for structural pattern matching (not regex)
- Sub-commands: `lint/` directory contains individual lint scripts, `migrate/` contains codemod scripts