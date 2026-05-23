#!/usr/bin/env bats

setup()    { load '../test_helper'; common_setup; }
teardown() { common_teardown; }

@test "main help shows usage" {
    run main help
    [[ "$output" == *"Usage: web"* ]]
}

@test "main with no args shows usage" {
    run main
    [[ "$output" == *"Usage: web"* ]]
}

@test "main dir prints SCRIPT_DIR" {
    run main dir
    [[ "$output" == "$SCRIPT_DIR" ]]
}

@test "main debug sets XDEBUG_MODE in .env" {
    printf 'XDEBUG_MODE=off\n' > "$SCRIPT_DIR/.env"
    DC="true"

    main debug profile >/dev/null 2>&1

    grep -q "XDEBUG_MODE=profile" "$SCRIPT_DIR/.env"
}

@test "unknown command shows help" {
    run main nonexistent-command
    [[ "$output" == *"Usage: web"* ]]
}

@test "main down rejects service argument" {
    DC="true"
    require_docker() { :; }
    run main down franken_php
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"down operates on the entire stack"* ]]
}

@test "main down with no args succeeds" {
    DC="true"
    require_docker() { :; }
    run main down
    [[ "$status" -eq 0 ]]
}

@test "main up removes orphan containers" {
    cat > "$SCRIPT_DIR/dc-capture" <<-'SH'
printf '%s\n' "$*" > "$SCRIPT_DIR/dc-args"
SH
    chmod +x "$SCRIPT_DIR/dc-capture"
    DC="$SCRIPT_DIR/dc-capture"
    require_docker() { :; }
    dc_ps() { :; }

    run main up

    [[ "$status" -eq 0 ]]
    [[ "$(<"$SCRIPT_DIR/dc-args")" == "up -d --remove-orphans" ]]
}

@test "stale templates file is ignored" {
    local dir="$TEST_TMPDIR/stale-compose"
    mkdir -p "$dir"
    cat > "$dir/templates.yml" <<-'YAML'
services:
  nginx:
    networks:
      nginx:
        aliases:
          - stale.test
YAML

    run bash -c "export SCRIPT_DIR='$dir'; source '$PROJECT_ROOT/web.sh'; [[ \"\$DC\" == \"docker compose -f $dir/docker-compose.yml\" ]]"

    [[ "$status" -eq 0 ]]
}
