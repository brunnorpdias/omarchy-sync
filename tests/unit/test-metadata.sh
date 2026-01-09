#!/bin/bash
# test-metadata.sh - Unit tests for lib/metadata.sh

# Test: write_metadata creates metadata file
test_write_metadata_creates_file() {
    local test_dir="$TEST_HOME/test-metadata"
    mkdir -p "$test_dir"
    write_metadata "$test_dir"
    assert_true "[[ -f \"\$test_dir/.backup-meta\" ]]" "Metadata file should be created"
}
run_test "write_metadata creates metadata file" test_write_metadata_creates_file

# Test: write_metadata contains hostname
test_write_metadata_hostname() {
    local test_dir="$TEST_HOME/test-metadata"
    mkdir -p "$test_dir"
    write_metadata "$test_dir"
    local result
    result=$(get_metadata_field "$test_dir" "hostname")
    assert_eq "$(hostname)" "$result" "Metadata should contain current hostname"
}
run_test "write_metadata contains hostname" test_write_metadata_hostname

# Test: write_metadata contains user
test_write_metadata_user() {
    local test_dir="$TEST_HOME/test-metadata"
    mkdir -p "$test_dir"
    write_metadata "$test_dir"
    local result
    result=$(get_metadata_field "$test_dir" "user")
    assert_eq "$USER" "$result" "Metadata should contain current user"
}
run_test "write_metadata contains user" test_write_metadata_user

# Test: write_metadata contains timestamp
test_write_metadata_timestamp() {
    local test_dir="$TEST_HOME/test-metadata"
    mkdir -p "$test_dir"
    write_metadata "$test_dir"
    local result
    result=$(get_metadata_field "$test_dir" "timestamp")
    assert_not_empty "$result" "Metadata should contain timestamp"
}
run_test "write_metadata contains timestamp" test_write_metadata_timestamp

# Test: read_metadata returns {} for missing file
test_read_metadata_missing() {
    local test_dir="$TEST_HOME/empty-dir"
    mkdir -p "$test_dir"
    local result
    result=$(read_metadata "$test_dir")
    assert_eq "{}" "$result" "read_metadata should return {} for missing file"
}
run_test "read_metadata returns {} for missing file" test_read_metadata_missing

# Test: read_metadata returns file contents
test_read_metadata_contents() {
    local test_dir="$TEST_HOME/test-metadata"
    mkdir -p "$test_dir"
    write_metadata "$test_dir"
    local result
    result=$(read_metadata "$test_dir")
    assert_contains "$result" "hostname" "read_metadata should return file contents"
}
run_test "read_metadata returns file contents" test_read_metadata_contents

# Test: get_metadata_field returns unknown for missing field
test_get_metadata_field_unknown() {
    local test_dir="$TEST_HOME/empty-dir"
    mkdir -p "$test_dir"
    local result
    result=$(get_metadata_field "$test_dir" "nonexistent")
    assert_eq "unknown" "$result" "get_metadata_field should return 'unknown' for missing field"
}
run_test "get_metadata_field returns unknown for missing field" test_get_metadata_field_unknown

# Test: get_metadata_field returns unknown for missing dir
test_get_metadata_field_missing_dir() {
    local result
    result=$(get_metadata_field "$TEST_HOME/no-such-dir" "hostname")
    assert_eq "unknown" "$result" "get_metadata_field should return 'unknown' for missing dir"
}
run_test "get_metadata_field returns unknown for missing dir" test_get_metadata_field_missing_dir
