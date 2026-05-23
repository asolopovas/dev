# Engineering guide

Use this when changing code, tests, Docker files, generated-file behavior, or agent guidance.

## Validation commands

```sh
make lint
make test
make test-integration
make test-all
```

| Command | Scope |
|---|---|
| `make lint` | ShellCheck on `web.sh` |
| `make test` | Unit tests in `tests/unit/` |
| `make test-integration` | Integration tests in `tests/integration/`; requires running services |
| `make test-all` | Runs `tests.sh`; includes integration tests only when `franken_php` is up |
| `bats tests/unit/main.bats` | One unit file |
| `bats -f "main help" tests/unit/` | Filtered test run |

CI runs `make lint` and `make test` on pushes and pull requests to `main`.

## ShellCheck policy

The lint target intentionally disables these ShellCheck rules:

```text
SC2086, SC2016, SC2034, SC2029, SC2120, SC2119, SC2318
```

Match the project lint command when adding local checks or CI steps.

## Code style

- Do not add comments to code. This applies to Bash, YAML, Dockerfile, Caddy config, INI, Fish, and test files.
- Prefer clear function and variable names over explanatory comments.
- Keep `web.sh` as a sourceable script and executable CLI.
- Keep command behavior explicit in `main()`.
- Preserve non-interactive fallbacks for `gum` UI paths.

## Bash patterns

| Pattern | Use |
|---|---|
| `die()` | Fatal error and exit 1 |
| `warn()` | Non-fatal warning |
| `info()` / `log()` | User-visible progress |
| `require_*()` | Precondition checks |
| `spin "message" command args...` | Gum spinner with plain fallback |
| `$DC` | All Docker Compose calls |
| `hosts_json_*()` | All host-registry JSON access |

`$DC` starts as `docker compose -f $SCRIPT_DIR/docker-compose.yml` and includes `templates.yml` when that generated file exists.

## Test isolation

Unit tests source `web.sh` through `tests/test_helper.bash`. The helper redirects path globals into a temp directory:

- `SCRIPT_DIR`
- `WEB_ROOT`
- `BACKEND_DIR`
- `BACKEND_CONFIG_DIR`
- `BACKEND_SITES_DIR`
- `HOSTS_JSON`
- `CERTS_DIR`

After sourcing `web.sh`, unit tests stub external or interactive functions:

- `_has_gum`
- `_HAS_GUM=0`
- `select_option`
- `spin`
- `redirect_remove`
- `redirect_add`
- `redirect_add_batch`
- `db_remove`
- `db_exists`
- `db_create`

New unit tests must work inside this sandbox. Do not require Docker, `/etc/hosts`, the Windows hosts file, real certificates outside the temp tree, or network services unless the test is explicitly an integration test.

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
| Command dispatch | `main()` | `tests/unit/main.bats` |
| CLI argument parsing | `parse_new_host_args()` | `tests/unit/parse_args.bats` |
| Host registry | `hosts_json_*()` | `tests/unit/hosts_json.bats` |
| Database naming | `make_db_name()`, `sanitize_db_identifier()` | `tests/unit/db_name.bats` |
| Generated configs | `build_webconf()` | `tests/unit/config.bats` |
| SSL helpers | `ssl_*()` | `tests/unit/config.bats` |
| Container/runtime behavior | Docker files, compose, entrypoint | `tests/integration/` |

## Known traps

- Do not add `command -v gum` calls inside logging or spinner hot paths. `_HAS_GUM` is memoized at startup; reference it directly.
- Do not perform one PowerShell elevation per host in `build_webconf`. Use `redirect_add_batch`.
- Do not add per-service `docker compose ps` calls for status rendering. The fast path is one `$DC ps --format json` call and `jq` formatting.
- Do not rewrite PHP `.ini` files at runtime. PHP handles `${ENV_VAR}` interpolation from Compose-provided environment values.
- Do not hand-edit generated Caddy site files, certs, `templates.yml`, or `crontab` as durable source changes.
- Do not remove the `BASH_SOURCE` guard at the bottom of `web.sh`.

## Documentation updates

When behavior changes, update the smallest relevant document:

- User-facing command, setup, service, or troubleshooting changes: `README.md` and `docs/OPERATIONS.md`.
- Architecture, generated files, WSL, SSL, DB naming, or Docker layout changes: `docs/ARCHITECTURE.md`.
- Test, lint, style, or contributor workflow changes: `docs/ENGINEERING.md`.
- Agent entry-point changes: `AGENTS.md`, but keep it compact and link outward.
