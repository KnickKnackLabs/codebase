# CI lint enforcement

`codebase lint:ci-lint-enforcement .` checks repositories with a configured lint
portfolio for a failure-propagating GitHub Actions declaration.
It is a structural policy check, not an execution or workflow-reachability proof.

## Default: direct lint

Without additional configuration, a complete workflow `run` value must contain
only `codebase lint ...` or `mise exec -- codebase lint ...`.
For example:

```yaml
- run: codebase lint "$PWD"
```

The rule rejects surrounding commands, functions, pipelines, `|| true`, and
GitHub expression interpolation. It accepts the default shell or GitHub's
built-in `bash` and `sh`, not custom shell templates. Neither the step nor its
job may set `continue-on-error` to anything other than literal false.

## Opt-in: repository-owned aggregate gate

Requires Codebase **0.5 or later**. A `0.4` tool pin will not pick up this option.

A repository whose tested aggregate owns lint may declare its exact CI command
in `mise.toml`:

```toml
[_.codebase]
name = "example"
lint = ["@all"]
ci_lint_gate = "mise run validate --verbose"
```

Then CI may use:

```yaml
- run: mise run validate --verbose
```

This adds an accepted alternative; direct lint remains valid. The same shell,
expression, and failure-propagation restrictions apply. The command must match
exactly, apart from whitespace surrounding the entire run value. Added flags,
wrappers, comments, or additional commands do not match. YAML block/folded scalars
are decoded before comparison.

`ci_lint_gate` must be a nonempty string containing one literal command with
single-space-separated, unquoted words. Words may use ASCII letters, digits,
`_ . / : @ % + = , -`; the executable has the narrower path/name spelling
`A-Z a-z 0-9 _ . / -` and cannot begin with a digit or hyphen. Quotes, variables,
substitutions, redirections, shell control flow, newlines, and wildcard patterns
are not supported. Put complex behavior inside the declared command, not in this
setting. Invalid declarations fail the rule even if CI also contains direct lint.

The declaration is a **trust boundary**: the repository asserts that this gate
runs its configured Codebase lint portfolio and propagates failure. Codebase
never executes or follows the task while checking this rule, and does not prove
its internals or even task existence. The repository should test its aggregate's
command inventory, nonzero propagation, and interruption behavior. Success
output makes the configured trust explicit; naming a task `validate` alone does
not opt in.

Both modes inspect workflow structure only. They do not prove triggers,
conditions, branch protection, workflow reachability, installed-tool identity,
or successful execution. Use hosted CI results as separate evidence.
