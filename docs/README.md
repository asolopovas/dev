# Documentation map

This directory is the project knowledge base. Prefer short, linked documents over one large instruction file.

## Read order

| Reader | Start here | Then read |
|---|---|---|
| User running the stack | [`../README.md`](../README.md) | [`OPERATIONS.md`](./OPERATIONS.md) |
| Agent or contributor editing code | [`../AGENTS.md`](../AGENTS.md) | [`ENGINEERING.md`](./ENGINEERING.md), [`ARCHITECTURE.md`](./ARCHITECTURE.md) |
| Maintainer changing Docker, host generation, SSL, or WSL behavior | [`ARCHITECTURE.md`](./ARCHITECTURE.md) | [`ENGINEERING.md`](./ENGINEERING.md) |

## Documents

- [`OPERATIONS.md`](./OPERATIONS.md): installation, commands, host lifecycle, SSL, database, Redis, Xdebug, `.env`, and troubleshooting.
- [`ARCHITECTURE.md`](./ARCHITECTURE.md): CLI shape, Docker service layout, generated files, host JSON model, database naming, WSL host mapping, PHP config, and container runtime.
- [`ENGINEERING.md`](./ENGINEERING.md): test commands, CI, Go formatting, test isolation, style rules, implementation patterns, and traps to avoid.

## Maintenance rules

- Keep `AGENTS.md` compact. It should point to source-of-truth docs, not repeat them.
- Keep `README.md` user-facing. It should help someone start the stack quickly.
- Put durable project behavior in this directory when it affects future changes.
- Remove scratch output and stale notes instead of preserving them as documentation.
- Update docs in the same change as behavior, command, or architecture changes.
