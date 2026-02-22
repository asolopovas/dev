#!/usr/bin/env bats

setup()    { load '../test_helper'; common_setup; }
teardown() { common_teardown; }

@test "hosts_json_add creates host entry" {
    hosts_json_add "alpha.test" "wp" "alpha_wp"
    run hosts_json_get_db "alpha.test"
    [[ "$output" == "alpha_wp" ]]
}

@test "hosts_json_add rejects duplicate host" {
    hosts_json_add "alpha.test" "wp" "alpha_wp"
    run hosts_json_add "alpha.test" "wp" "alpha_wp"
    [[ "$status" -eq 1 ]]
}

@test "hosts_json_remove deletes host entry" {
    hosts_json_add "alpha.test" "wp" "alpha_wp"
    hosts_json_remove "alpha.test"
    run hosts_json_get_host "alpha.test"
    [[ -z "$output" ]]
}

@test "hosts_json_ensure_defaults creates valid JSON when missing" {
    rm -f "$HOSTS_JSON"
    hosts_json_ensure_defaults >/dev/null 2>&1 || true
    [[ -f "$HOSTS_JSON" ]]
    jq empty "$HOSTS_JSON" >/dev/null 2>&1
}

@test "hosts_json_get_host returns full host object" {
    hosts_json_add "beta.test" "laravel" "beta_db"
    run hosts_json_get_host "beta.test"
    [[ "$output" == *"beta.test"* ]]
    [[ "$output" == *"laravel"* ]]
    [[ "$output" == *"beta_db"* ]]
}

@test "hosts_json_add stores correct type" {
    hosts_json_add "gamma.test" "laravel" "gamma_db"
    local host_type
    host_type=$(jq -r '.hosts[] | select(.name == "gamma.test") | .type' "$HOSTS_JSON")
    [[ "$host_type" == "laravel" ]]
}
