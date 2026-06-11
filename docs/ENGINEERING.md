# Engineering guide

Use this when changing code, tests, Docker files, generated-file behavior, or agent guidance.

## Validation commands

```sh
make check
make lint
make test
make test-integration
make test-all
```

| Command | Scope |
|---|---|
| `make check` | Lint plus all tests; integration tests run only when services are up |
| `make lint` | Go formatting, `go vet`, and shellcheck on shell scripts |
| `make test` | Go unit and E2E-style tests |
| `make test-integration` | Bats integration tests in `tests/integration/`; requires running services |
| `make test-all` | Runs Go tests and integration tests only when `franken_php` is up |
| `go test ./internal/web -run TestName` | Filtered Go test run |

CI should run `make lint` and `make test` on pushes and pull requests to `main`.

## Code style

- Do not add comments to code. This applies to Go, Bash, YAML, Dockerfile, Caddy config, INI, Fish, and test files.
- Prefer clear function and variable names over explanatory comments.
- Keep command behavior explicit in Cobra command handlers.
- Preserve non-interactive command paths for prompts and confirmations.
- Run `gofmt` on changed Go files.

## Go patterns

| Pattern | Use |
|---|---|
| `App` | Runtime dependencies and configuration |
| `Runner` | Stub external commands in tests |
| `LoadRegistry` / `EnsureRegistry` / `SaveRegistry` | Host-registry JSON access |
| `writeFileAtomic` | Atomic generated-file and registry writes |
| `requireDockerThen` | Docker precondition wrapper |

## Test isolation

Go unit tests must work inside temp directories and fake external commands through `Runner` or temporary executable stubs. They must not require Docker, `/etc/hosts`, the Windows hosts file, real certificates outside the temp tree, or network services unless the test is explicitly an integration test.

## Integration tests

Integration tests assume the stack is available. They verify installed PHP extensions and libraries, required CLI tools, FrankenPHP host serving, service status, MariaDB access, Redis ping, Mailpit, and Typesense health.

Run them after service or image changes:

```sh
web up
make test-integration
```

## Safe-change checklist

Before editing behavior, locate the owning function and related tests:

| Area | Primary code | Tests |
|---|---|---|
| Command dispatch | `commands.go` | `internal/web/commands_test.go` |
| Host registry | `registry.go` | `internal/web/registry_test.go` |
| Database naming | `MakeDBName`, `SanitizeDBIdentifier` | `internal/web/hostname_test.go` |
| Generated configs | `rebuildWebConfiguration` | `internal/web/site_config_test.go` |
| Host lifecycle | `host_workflow.go` | `internal/web/host_workflow_test.go` |
| Project scaffolding | `project_scaffold.go` | `internal/web/project_scaffold_test.go` |
| Container/runtime behavior | Docker files, compose, entrypoint | `tests/integration/` |

## Known traps

- Do not perform one PowerShell elevation per host in `rebuildWebConfiguration`. Use batched host redirects.
- Do not add per-service Docker Compose status calls for status rendering. Prefer a single Compose `ps` call.
- Do not rewrite PHP `.ini` files at runtime. PHP handles `${ENV_VAR}` interpolation from Compose-provided environment values.
- Do not hand-edit generated Caddy site files, certs, `templates.yml`, or `crontab` as durable source changes.

## Documentation updates

When behavior changes, update the smallest relevant document:

- User-facing command, setup, service, or troubleshooting changes: `README.md` and `docs/OPERATIONS.md`.
- Architecture, generated files, WSL, SSL, DB naming, or Docker layout changes: `docs/ARCHITECTURE.md`.
- Test, lint, style, or contributor workflow changes: `docs/ENGINEERING.md`.
- Agent entry-point changes: `AGENTS.md`, but keep it compact and link outward.
