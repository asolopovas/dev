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
