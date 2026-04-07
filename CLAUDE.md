# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The canonical agent guidance lives in [AGENTS.md](./AGENTS.md). Read it before making changes.

## Quick reference

- **Tests**: `make lint && make test` (unit) and `make test-integration` (live containers)
- **Single bats file**: `bats tests/unit/main.bats`
- **Filter by name**: `bats -f "main help" tests/unit/`
- **CLI dispatch**: `web.sh` `main()` function — case statement on the command name
- **Sourceable**: the `BASH_SOURCE != $0` guard at the bottom of `web.sh` lets tests source the script without executing `main`
- **Test stubs**: `tests/test_helper.bash` overrides `_has_gum`/`select_option`/`spin`/`redirect_*`/`db_*` after sourcing `web.sh` so unit tests never touch Docker, /etc/hosts, or the Windows hosts file

## Code style

- **No comments in code.** Never add inline, block, or trailing comments. The code must speak for itself through clear naming and structure. Applies to bash, YAML, Dockerfile, conf — every file type.

## Things to avoid

- Adding `command -v gum` calls inside log/spin functions. `_HAS_GUM` is memoized once at startup; reference it as `((_HAS_GUM))`.
- Per-host PowerShell elevation in `build_webconf`. Use `redirect_add_batch` so a single UAC prompt covers all hosts.
- Per-service `docker compose ps` calls. The fast path is one `$DC ps --format json` then jq.
- Runtime in-place sed of PHP `.ini` files. PHP supports `${ENV_VAR}` interpolation natively in ini files; pass env vars from `.env` via `docker-compose.yml`.
