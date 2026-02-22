#!/usr/bin/env bats

setup()    { load '../test_helper'; common_setup; }
teardown() { common_teardown; }

@test "make_db_name simple domain produces name_wp" {
    run make_db_name "example.test" "wp"
    [[ "$output" == "example_wp" ]]
}

@test "make_db_name subdomain produces main_sub_db" {
    run make_db_name "sub.example.test" "laravel"
    [[ "$output" == "example_sub_db" ]]
}

@test "make_db_name known SLD co.uk strips TLD correctly" {
    run make_db_name "example.co.uk" "wp"
    [[ "$output" == "example_wp" ]]
}

@test "make_db_name leading digit gets db_ prefix" {
    run make_db_name "3oak.test" "wp"
    [[ "$output" == "db_3oak_wp" ]]
}

@test "make_db_name single-label host" {
    run make_db_name "localhost" "wp"
    [[ "$output" == "localhost_wp" ]]
}

@test "make_db_name deep subdomain" {
    run make_db_name "a.b.example.test" "laravel"
    [[ "$output" == "example_a_b_db" ]]
}

@test "make_db_name wordpress type alias" {
    run make_db_name "site.test" "wordpress"
    [[ "$output" == "site_wp" ]]
}

@test "sanitize_db_identifier strips special chars" {
    run sanitize_db_identifier "my-site.name"
    [[ "$output" == "my_site_name" ]]
}

@test "sanitize_db_identifier handles leading underscores" {
    run sanitize_db_identifier "__test"
    [[ "$output" == "test" ]]
}

@test "sanitize_db_identifier handles empty input" {
    run sanitize_db_identifier ""
    [[ "$output" == "db" ]]
}

@test "sanitize_db_identifier prefixes leading digit" {
    run sanitize_db_identifier "9lives"
    [[ "$output" == "db_9lives" ]]
}
