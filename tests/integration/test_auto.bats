#!/usr/bin/env bats
# test_auto.bats - Integration tests for APR autonomous loop mode

load '../helpers/test_helper'

setup() {
    setup_test_environment
    log_test_start "${BATS_TEST_NAME}"

    cd "$TEST_PROJECT" || return 1
    setup_test_workflow "default"
    setup_auto_oracle
}

teardown() {
    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

setup_auto_oracle() {
    local bin_dir="$TEST_DIR/bin"
    mkdir -p "$bin_dir"

    cat > "$bin_dir/oracle" << 'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "--version" ]]; then
    echo "oracle 0.9.0 (mock)"
    exit 0
fi

if [[ "${1:-}" == "--help" ]]; then
    echo "Usage: oracle [options]"
    echo "  --notify"
    exit 0
fi

if [[ "${1:-}" == "status" ]]; then
    echo "No active sessions"
    exit 0
fi

if [[ "${1:-}" == "session" ]]; then
    # `apr run --wait` may attempt recovery with `oracle session <slug> --write-output ...`.
    # Reuse the same write-output parser below.
    shift 2 || true
fi

write_output=""
prev=""
for arg in "$@"; do
    if [[ "$prev" == "--write-output" ]]; then
        write_output="$arg"
        break
    fi
    prev="$arg"
done

if [[ -n "$write_output" ]]; then
    mkdir -p "$(dirname "$write_output")"
    {
        echo "# Mock Oracle Output"
        echo ""
        for n in {1..320}; do
            echo "Feedback line $n: deterministic content to satisfy APR output validation checks."
        done
    } > "$write_output"
fi

exit 0
EOF

    chmod +x "$bin_dir/oracle"
    export PATH="$bin_dir:$PATH"
}

@test "apr auto: runs integration each iteration and stops on max iterations" {
    local integration_log="$TEST_PROJECT/integration.log"
    local integration_cmd
    integration_cmd="printf '%s\n' \"\$APR_AUTO_ROUND\" >> \"$integration_log\""

    capture_streams "$APR_SCRIPT" auto 1 \
        --workflow default \
        --integration-agent shell \
        --integration-command "$integration_cmd" \
        --convergence-threshold 1 \
        --max-iterations 2

    log_test_actual "exit code" "$CAPTURED_STATUS"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ "$CAPTURED_STATUS" -eq 0 ]]
    [[ "$CAPTURED_STDERR" == *"Stop reason: max_iterations_reached"* ]]
    [[ -f ".apr/rounds/default/round_1.md" ]]
    [[ -f ".apr/rounds/default/round_2.md" ]]
    [[ -f "$integration_log" ]]
    run wc -l "$integration_log"
    assert_success
    [[ "$output" == *"2"* ]]
}

@test "apr auto: stops on convergence threshold before max iterations" {
    local integration_log="$TEST_PROJECT/integration_conv.log"
    local integration_cmd
    integration_cmd="printf '%s\n' \"\$APR_AUTO_ROUND\" >> \"$integration_log\""

    capture_streams "$APR_SCRIPT" auto 1 \
        --workflow default \
        --integration-agent shell \
        --integration-command "$integration_cmd" \
        --convergence-threshold 0 \
        --max-iterations 5

    log_test_actual "exit code" "$CAPTURED_STATUS"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ "$CAPTURED_STATUS" -eq 0 ]]
    [[ "$CAPTURED_STDERR" == *"Stop reason: convergence_reached"* ]]
    [[ -f "$integration_log" ]]
    run wc -l "$integration_log"
    assert_success
    [[ "$output" == *"1"* ]]
}

@test "apr auto: --json emits machine-readable stop summary" {
    local integration_log="$TEST_PROJECT/integration_json.log"
    local integration_cmd
    integration_cmd="printf '%s\n' \"\$APR_AUTO_ROUND\" >> \"$integration_log\""

    capture_streams "$APR_SCRIPT" auto 1 \
        --workflow default \
        --integration-agent shell \
        --integration-command "$integration_cmd" \
        --convergence-threshold 0 \
        --max-iterations 4 \
        --json

    log_test_actual "exit code" "$CAPTURED_STATUS"
    log_test_actual "stdout" "$CAPTURED_STDOUT"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ "$CAPTURED_STATUS" -eq 0 ]]
    echo "$CAPTURED_STDOUT" | jq -e . >/dev/null
    assert_json_value "$CAPTURED_STDOUT" ".stop_reason" "convergence_reached"
    assert_json_value "$CAPTURED_STDOUT" ".iterations" "1"
}

@test "manual run ignores auto-only config keys even when invalid" {
    cat >> .apr/workflows/default.yaml << 'EOF'
auto_integration_agent: shell
auto_integration_command: "echo should-not-run"
auto_convergence_threshold: banana
auto_max_iterations: nope
EOF

    capture_streams "$APR_SCRIPT" run 1 --dry-run --workflow default

    log_test_actual "exit code" "$CAPTURED_STATUS"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ "$CAPTURED_STATUS" -eq 0 ]]
    [[ "$CAPTURED_STDERR" == *"Would execute"* ]]
}

@test "apr auto: fails fast on unsupported integration agent" {
    capture_streams "$APR_SCRIPT" auto 1 \
        --workflow default \
        --integration-agent unsupported \
        --convergence-threshold 0.5 \
        --max-iterations 2

    log_test_actual "exit code" "$CAPTURED_STATUS"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ "$CAPTURED_STATUS" -eq 4 ]]
    [[ "$CAPTURED_STDERR" == *"Unsupported integration agent"* ]]
}

@test "apr loop: alias executes autonomous mode" {
    local integration_log="$TEST_PROJECT/integration_loop_alias.log"
    local integration_cmd
    integration_cmd="printf '%s\n' \"\$APR_AUTO_ROUND\" >> \"$integration_log\""

    capture_streams "$APR_SCRIPT" loop 1 \
        --workflow default \
        --integration-agent shell \
        --integration-command "$integration_cmd" \
        --convergence-threshold 0 \
        --max-iterations 4

    log_test_actual "exit code" "$CAPTURED_STATUS"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ "$CAPTURED_STATUS" -eq 0 ]]
    [[ "$CAPTURED_STDERR" == *"Stop reason: convergence_reached"* ]]
    [[ -f "$integration_log" ]]
}

@test "apr auto: integration command supports {prompt} placeholder" {
    local captured_prompt="$TEST_PROJECT/integration_prompt_placeholder.log"
    local integration_cmd
    integration_cmd="cat {prompt} > \"$captured_prompt\""

    capture_streams "$APR_SCRIPT" auto 1 \
        --workflow default \
        --integration-agent shell \
        --integration-command "$integration_cmd" \
        --convergence-threshold 0 \
        --max-iterations 3

    log_test_actual "exit code" "$CAPTURED_STATUS"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ "$CAPTURED_STATUS" -eq 0 ]]
    [[ "$CAPTURED_STDERR" == *"Stop reason: convergence_reached"* ]]
    [[ -s "$captured_prompt" ]]
}

@test "apr auto: codex agent requires explicit integration command" {
    capture_streams "$APR_SCRIPT" auto 1 \
        --workflow default \
        --integration-agent codex \
        --convergence-threshold 0.5 \
        --max-iterations 2

    log_test_actual "exit code" "$CAPTURED_STATUS"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ "$CAPTURED_STATUS" -eq 4 ]]
    [[ "$CAPTURED_STDERR" == *"integration agent 'codex' requires a non-interactive command"* ]]
}

@test "apr auto: gemini agent requires explicit integration command" {
    capture_streams "$APR_SCRIPT" auto 1 \
        --workflow default \
        --integration-agent gemini \
        --convergence-threshold 0.5 \
        --max-iterations 2

    log_test_actual "exit code" "$CAPTURED_STATUS"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ "$CAPTURED_STATUS" -eq 4 ]]
    [[ "$CAPTURED_STDERR" == *"integration agent 'gemini' requires a non-interactive command"* ]]
}
