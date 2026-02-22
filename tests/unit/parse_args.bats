#!/usr/bin/env bats

setup()    { load '../test_helper'; common_setup; }
teardown() { common_teardown; }

@test "parse_new_host_args parses -t flag and hostname" {
    parse_new_host_args -t laravel "mysite.test"
    [[ "$HOST" == "mysite.test" ]]
    [[ "$TYPE" == "laravel" ]]
}

@test "parse_new_host_args defaults type to wp" {
    parse_new_host_args "mysite.test"
    [[ "$HOST" == "mysite.test" ]]
    [[ "$TYPE" == "wp" ]]
}

@test "parse_new_host_args hostname before -t flag" {
    parse_new_host_args "mysite.test" -t laravel
    [[ "$HOST" == "mysite.test" ]]
    [[ "$TYPE" == "laravel" ]]
}

@test "parse_new_host_args fails without hostname" {
    run parse_new_host_args
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"No hostname specified"* ]]
}

@test "parse_new_host_args fails when -t has no value" {
    run parse_new_host_args mysite.test -t
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Option -t requires a value"* ]]
}
