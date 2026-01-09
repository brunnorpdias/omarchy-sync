#!/bin/bash
# test-config.sh - Unit tests for lib/config.sh

# Test: config_exists returns false when no config
test_config_exists_no_config() {
    assert_true "[[ ! -f \"\$CONFIG_FILE\" ]]" "Config should not exist initially"
    local result
    result=$(config_exists && echo "true" || echo "false")
    assert_eq "false" "$result" "config_exists should return false"
}
run_test "config_exists returns false when no config" test_config_exists_no_config

# Test: create_default_config creates config file
test_create_default_config() {
    create_default_config
    assert_true "[[ -f \"\$CONFIG_FILE\" ]]" "Config file should be created"
    assert_true "grep -q 'size_limit_mb = 20' \"\$CONFIG_FILE\"" "Config should have default size_limit"
}
run_test "create_default_config creates config file" test_create_default_config

# Test: get_config_value returns default for missing key
test_get_config_value_default() {
    create_default_config
    local result
    result=$(get_config_value "nonexistent_key" "mydefault")
    assert_eq "mydefault" "$result" "get_config_value should return default for missing key"
}
run_test "get_config_value returns default for missing key" test_get_config_value_default

# Test: get_config_value returns actual value
test_get_config_value_actual() {
    create_default_config
    local result
    result=$(get_config_value "size_limit_mb" "99")
    assert_eq "20" "$result" "get_config_value should return actual value"
}
run_test "get_config_value returns actual value" test_get_config_value_actual

# Test: get_config_value handles values with spaces
test_get_config_value_with_spaces() {
    create_default_config
    echo 'test_key = "value with spaces"' >> "$CONFIG_FILE"
    local result
    result=$(get_config_value "test_key" "")
    assert_eq "value with spaces" "$result" "get_config_value should handle spaces in values"
}
run_test "get_config_value handles values with spaces" test_get_config_value_with_spaces

# Test: set_config_value adds new key
test_set_config_value_new() {
    create_default_config
    set_config_value "new_key" "new_value"
    local result
    result=$(get_config_value "new_key" "")
    assert_eq "new_value" "$result" "set_config_value should add new key"
}
run_test "set_config_value adds new key" test_set_config_value_new

# Test: set_config_value updates existing key
test_set_config_value_update() {
    create_default_config
    set_config_value "size_limit_mb" "50"
    local result
    result=$(get_config_value "size_limit_mb" "")
    assert_eq "50" "$result" "set_config_value should update existing key"
}
run_test "set_config_value updates existing key" test_set_config_value_update

# Test: get_local_path returns correct path
test_get_local_path() {
    create_default_config
    local result
    result=$(get_local_path)
    assert_eq "$DEFAULT_LOCAL_PATH" "$result" "get_local_path should return default path"
}
run_test "get_local_path returns correct path" test_get_local_path

# Test: get_size_limit returns correct value
test_get_size_limit() {
    create_default_config
    local result
    result=$(get_size_limit)
    assert_eq "20" "$result" "get_size_limit should return default value"
}
run_test "get_size_limit returns correct value" test_get_size_limit

# Test: get_config_value handles keys with special regex chars
test_get_config_value_special_chars() {
    create_default_config
    echo 'key.with.dots = "dotted_value"' >> "$CONFIG_FILE"
    local result
    result=$(get_config_value "key.with.dots" "")
    assert_eq "dotted_value" "$result" "get_config_value should handle dots in key"
}
run_test "get_config_value handles keys with special regex chars" test_get_config_value_special_chars

# Test: get_internal_drives returns empty when no drives configured
test_get_internal_drives_empty() {
    create_default_config
    local result
    result=$(get_internal_drives)
    assert_eq "" "$result" "get_internal_drives should return empty when none configured"
}
run_test "get_internal_drives returns empty when none configured" test_get_internal_drives_empty

# Test: get_internal_drives returns configured drives
test_get_internal_drives_configured() {
    create_default_config
    cat >> "$CONFIG_FILE" << 'EOF'

[[internal_drives]]
path = "/mnt/data"
label = "Data Drive"
EOF
    local result
    result=$(get_internal_drives)
    assert_contains "$result" "/mnt/data/omarchy-backup|Data Drive" \
        "get_internal_drives should return configured drive with /omarchy-backup appended"
}
run_test "get_internal_drives returns configured drives" test_get_internal_drives_configured
