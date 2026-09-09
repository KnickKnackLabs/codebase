<div align="center">

<img src="assets/logo.jpg" alt="Pink and lime open-book emblem with a quill, torch, and EDUKASHUN lettering" width="800">

# codebase

[![tests: 423](https://img.shields.io/badge/tests-423-brightgreen?style=flat)](test/)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue?style=flat)](LICENSE)

</div>

Repository conventions, written down and checked. Codebase runs the rules declared in `mise.toml` against Bash, mise tasks, BATS tests, and GitHub Actions. Pick individual rules or groups, then run one command.

## Install

```bash
shiv install codebase
```

Or declare it for a project in `mise.toml`:

```toml
[plugins]
shiv = "https://github.com/KnickKnackLabs/vfox-shiv"

[tools]
"shiv:codebase" = "0.5"
```

```bash
mise install
```

## Run

Choose the conventions for your repository in `mise.toml`:

```toml
[_.codebase]
name = "my-tool"
lint = ["@shell", "@mise"]
```

```bash
codebase lint .          # run the configured rules
codebase lint:groups     # inspect available groups and their members
codebase pre-commit      # optionally install a clone-local lint hook
```

Group membership evolves when you upgrade Codebase.

## Documentation

Commands include examples in `--help`. See [CI lint enforcement](docs/ci-lint-enforcement.md) for direct lint steps and the explicitly trusted aggregate-gate option introduced in Codebase 0.5.

From a prepared source checkout, `mise run test` runs the suite. Edit `README.tsx` and run `readme build` to update this page.
