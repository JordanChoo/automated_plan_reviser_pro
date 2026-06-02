#!/usr/bin/env bats
# test_manifest.bats - Unit tests for prompt manifest helpers

load '../helpers/test_helper'

setup() {
    setup_test_environment
    load_apr_functions
    log_test_start "${BATS_TEST_NAME}"
    cd "$TEST_PROJECT" || return 1
}

teardown() {
    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

@test "manifest_file_sha256: computes stable sha256 for bytes" {
    printf 'hello\n' > hello.txt

    run manifest_file_sha256 hello.txt

    assert_success
    assert_output "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"
}

@test "manifest_file_size_bytes: computes exact byte size" {
    printf 'hello\n' > hello.txt

    run manifest_file_size_bytes hello.txt

    assert_success
    assert_output "6"
}

@test "manifest helpers: handle non-UTF8 content as bytes" {
    printf '\377\000A' > binary.dat

    run manifest_file_size_bytes binary.dat
    assert_success
    assert_output "3"

    run manifest_file_sha256 binary.dat
    assert_success
    assert_output --regexp '^[0-9a-f]{64}$'
}

@test "manifest_normalize_path: strips project-root absolute paths" {
    mkdir -p docs
    printf 'spec\n' > docs/spec.md

    run manifest_normalize_path "$TEST_PROJECT/docs/spec.md"

    assert_success
    assert_output "docs/spec.md"
}

@test "manifest_inclusion_reason: distinguishes implementation triggers" {
    run manifest_inclusion_reason implementation false
    assert_success
    assert_output "not_requested"

    run manifest_inclusion_reason implementation true explicit
    assert_success
    assert_output "explicit_include_impl"

    run manifest_inclusion_reason implementation true impl_every_n
    assert_success
    assert_output "impl_every_n"
}

@test "manifest_render_text: renders deterministic compact manifest" {
    printf 'hello\n' > README.md
    printf 'spec\n' > SPECIFICATION.md

    local readme_hash spec_hash entries expected
    readme_hash=$(manifest_file_sha256 README.md)
    spec_hash=$(manifest_file_sha256 SPECIFICATION.md)
    entries=$(manifest_collect_documents README.md SPECIFICATION.md IMPLEMENTATION.md false)
    expected="APR DOCUMENT MANIFEST
- readme: README.md [included; required; 6B; sha256=$readme_hash]
- implementation: IMPLEMENTATION.md [skipped; not_requested]
- spec: SPECIFICATION.md [included; required; 5B; sha256=$spec_hash]
END APR DOCUMENT MANIFEST"

    run manifest_render_text "$entries"

    assert_success
    assert_output "$expected"
}

@test "manifest_collect_documents: records missing requested implementation as skipped" {
    printf 'hello\n' > README.md
    printf 'spec\n' > SPECIFICATION.md

    local entries
    entries=$(manifest_collect_documents README.md SPECIFICATION.md IMPLEMENTATION.md true explicit)

    run manifest_render_text "$entries"

    assert_success
    [[ "$output" == *"- implementation: IMPLEMENTATION.md [skipped; missing_optional]"* ]]
}

@test "manifest_render_json: emits stable machine-readable entries" {
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq not available"
    fi

    printf 'hello\n' > README.md
    printf 'spec\n' > SPECIFICATION.md

    local entries
    entries=$(manifest_collect_documents README.md SPECIFICATION.md IMPLEMENTATION.md false)

    run manifest_render_json "$entries"

    assert_success
    assert_valid_json "$output"
    assert_json_value "$output" "length" "3"
    assert_json_value "$output" ".[0].role" "readme"
    assert_json_value "$output" ".[0].status" "included"
    assert_json_value "$output" ".[0].bytes" "6"
    assert_json_value "$output" ".[1].role" "implementation"
    assert_json_value "$output" ".[1].status" "skipped"
    assert_json_value "$output" ".[1].sha256" "null"
    assert_json_value "$output" ".[2].role" "spec"
}
