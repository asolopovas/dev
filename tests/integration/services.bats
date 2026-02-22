#!/usr/bin/env bats

COMPOSE_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/docker-compose.yml"
DC="docker compose -f $COMPOSE_FILE"

@test "all services are running" {
    local status
    status=$($DC ps --status running --format '{{.Service}}' 2>/dev/null | sort)
    [[ "$status" == *"franken_php"* ]]
    [[ "$status" == *"mariadb"* ]]
    [[ "$status" == *"redis"* ]]
    [[ "$status" == *"phpmyadmin"* ]]
    [[ "$status" == *"mailpit"* ]]
    [[ "$status" == *"typesense"* ]]
}

@test "mariadb accepts connections" {
    local result
    result=$($DC exec -T mariadb mariadb -uroot -psecret -e "SELECT 1 AS ok" --skip-column-names 2>/dev/null)
    [[ "$(echo "$result" | tr -d '[:space:]')" == "1" ]]
}

@test "redis responds to ping" {
    local result
    result=$($DC exec -T redis redis-cli ping 2>/dev/null)
    [[ "$(echo "$result" | tr -d '[:space:]')" == "PONG" ]]
}

@test "mailpit is accessible on port 8025" {
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:8025 2>/dev/null)
    [[ "$code" == "200" ]]
}

@test "typesense health endpoint responds" {
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:8108/health 2>/dev/null)
    [[ "$code" == "200" ]]
}
