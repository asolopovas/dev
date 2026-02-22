#!/bin/bash

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

command -v bats &>/dev/null || { printf "bats is not installed. Install with: sudo apt install bats\n" >&2; exit 1; }

printf "\nunit tests\n==========\n\n"
bats "$SCRIPT_DIR/tests/unit/"
unit_result=$?

if docker compose -f "$SCRIPT_DIR/docker-compose.yml" ps --status running --format '{{.Service}}' 2>/dev/null | grep -q franken_php; then
    printf "\nintegration tests\n=================\n\n"
    bats "$SCRIPT_DIR/tests/integration/"
    integration_result=$?
else
    printf "\nSkipping integration tests (services not running)\n"
    integration_result=0
fi

((unit_result == 0 && integration_result == 0))
