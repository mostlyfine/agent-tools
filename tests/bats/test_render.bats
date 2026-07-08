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
    [[ "$output" == *"ID"* ]]
    [[ "$output" == *"TASK"* ]]
    [[ "$output" == *"DIR"* ]]
}

@test "render: agent/pane_id/task/dir がこの順序で1行に表示される" {
    create_tmux_mock "pane_list_claude.txt" "capture_claude_idle.txt"
    run python3 "$AGENT_PS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude"*"42"*"doing work"*"project"* ]]
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

@test "render: Copilot pane の agent 名が表示される" {
    create_tmux_mock "pane_list_copilot.txt" "capture_empty.txt"
    run python3 "$AGENT_PS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"copilot"*"43"* ]]
}

@test "render: Claude と Copilot の混在 pane を両方表示する" {
    create_tmux_mock "pane_list_mixed.txt" "capture_claude_idle.txt"
    run python3 "$AGENT_PS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude"*"42"* ]]
    [[ "$output" == *"copilot"*"43"* ]]
}

@test "render: running 状態では '🟡' グリフが表示される" {
    create_tmux_mock "pane_list_claude.txt" "capture_claude_running.txt"
    run python3 "$AGENT_PS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"🟡"* ]]
}

@test "render: waiting_for_input 状態では '🔴' グリフが表示される" {
    create_tmux_mock "pane_list_claude.txt" "capture_claude_waiting.txt"
    run python3 "$AGENT_PS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"🔴"* ]]
}

@test "render --horizontal: 1行目に status グリフと agent: pane_id が表示される（%なし）" {
    create_tmux_mock "pane_list_claude.txt" "capture_claude_idle.txt"
    run python3 "$AGENT_PS" --horizontal
    [ "$status" -eq 0 ]
    id_line=$(echo "$output" | grep -m1 "42")
    [[ "$id_line" == *"claude: 42"* ]]
    [[ "$id_line" != *"%42"* ]]
    [[ "$id_line" != *"doing work"* ]]
}

@test "render --horizontal: ヘッダー行（AGENT）が表示されない" {
    create_tmux_mock "pane_list_claude.txt" "capture_claude_idle.txt"
    run python3 "$AGENT_PS" --horizontal
    [ "$status" -eq 0 ]
    [[ "$output" != *"AGENT"* ]]
}

@test "render --horizontal: 2行目にタスク名のみ表示される(アイコンなし)" {
    create_tmux_mock "pane_list_claude.txt" "capture_claude_idle.txt"
    run python3 "$AGENT_PS" --horizontal
    [ "$status" -eq 0 ]
    [[ "$output" == *"doing work"* ]]
    [[ "$output" != *"󱚣"* ]]
}

@test "render --horizontal: dir は task と同じ行ではなく改行して表示される" {
    create_tmux_mock "pane_list_claude.txt" "capture_claude_idle.txt"
    run python3 "$AGENT_PS" --horizontal
    [ "$status" -eq 0 ]
    [[ "$output" == *"project"* ]]
    dir_line=$(echo "$output" | grep "project")
    [[ "$dir_line" != *"doing work"* ]]
}

@test "render --horizontal: ブロック間に横罫線（─）が表示される" {
    create_tmux_mock "pane_list_claude.txt" "capture_claude_idle.txt"
    run python3 "$AGENT_PS" --horizontal
    [ "$status" -eq 0 ]
    [[ "$output" == *"─"* ]]
}

@test "render --horizontal: Claude/Copilot 混在時に両方がブロック表示される" {
    create_tmux_mock "pane_list_mixed.txt" "capture_claude_idle.txt"
    run python3 "$AGENT_PS" --horizontal
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude: 42"* ]]
    [[ "$output" == *"copilot: 43"* ]]
    [[ "$output" == *"doing work"* ]]
    [[ "$output" == *"fixing tests"* ]]
}

@test "render --horizontal: running 状態では '🟡' グリフが表示される" {
    create_tmux_mock "pane_list_claude.txt" "capture_claude_running.txt"
    run python3 "$AGENT_PS" --horizontal
    [ "$status" -eq 0 ]
    [[ "$output" == *"🟡"* ]]
}

@test "render --horizontal: 0件時に 'No agent sessions found' を表示する" {
    create_tmux_mock "pane_list_empty.txt"
    run python3 "$AGENT_PS" --horizontal
    [ "$status" -eq 0 ]
    [[ "$output" == *"No agent sessions found"* ]]
}

@test "render -H（短縮形）は --horizontal と同じ出力になる" {
    create_tmux_mock "pane_list_claude.txt" "capture_claude_idle.txt"
    run python3 "$AGENT_PS" --horizontal
    long_output="$output"
    run python3 "$AGENT_PS" -H
    [ "$status" -eq 0 ]
    [ "$output" = "$long_output" ]
}

@test "render: フラグなし時はdirがtaskと同じ行に表示される（horizontalとの違いを確認）" {
    create_tmux_mock "pane_list_claude.txt" "capture_claude_idle.txt"
    run python3 "$AGENT_PS"
    [ "$status" -eq 0 ]
    task_line=$(echo "$output" | grep "doing work")
    [[ "$task_line" == *"project"* ]]
}

@test "render: Codex pane の agent 名がテキストで表示される" {
    create_tmux_mock "pane_list_codex.txt" "capture_empty.txt"
    run python3 "$AGENT_PS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"codex"*"44"* ]]
}
