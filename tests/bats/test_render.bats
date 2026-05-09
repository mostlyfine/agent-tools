#!/usr/bin/env bats

load "helpers/common"

setup() {
    setup_mock_bin
}

@test "render: ヘッダーに AGENT, ID, TASK, DIR が含まれる" {
    create_tmux_mock "pane_list_claude.txt" "capture_claude_idle.txt"
    run python3 "$AGENT_PS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AGENT"* ]]
    [[ "$output" == *"TASK"* ]]
    [[ "$output" == *"DIR"* ]]
}

@test "render: Claude pane の agent 列に 'claude' が表示される" {
    create_tmux_mock "pane_list_claude.txt" "capture_claude_idle.txt"
    run python3 "$AGENT_PS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude"* ]]
}

@test "render: Claude pane の pane ID が表示される" {
    create_tmux_mock "pane_list_claude.txt" "capture_claude_idle.txt"
    run python3 "$AGENT_PS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"42"* ]]
}

@test "render: エージェントなしの場合は 'No agent sessions found' を表示する" {
    create_tmux_mock "pane_list_empty.txt"
    run python3 "$AGENT_PS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No agent sessions found"* ]]
}

@test "render: Copilot pane の agent 列に 'copilot' が表示される" {
    create_tmux_mock "pane_list_copilot.txt" "capture_empty.txt"
    run python3 "$AGENT_PS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"copilot"* ]]
}

@test "render: Claude と Copilot の混在 pane を両方表示する" {
    create_tmux_mock "pane_list_mixed.txt" "capture_claude_idle.txt"
    run python3 "$AGENT_PS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude"* ]]
    [[ "$output" == *"copilot"* ]]
}

@test "render: running 状態では '●' グリフが表示される" {
    create_tmux_mock "pane_list_claude.txt" "capture_claude_running.txt"
    run python3 "$AGENT_PS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"●"* ]]
}

@test "render: waiting_for_input 状態では '>' グリフが表示される" {
    create_tmux_mock "pane_list_claude.txt" "capture_claude_waiting.txt"
    run python3 "$AGENT_PS"
    [ "$status" -eq 0 ]
    [[ "$output" == *">"* ]]
}
