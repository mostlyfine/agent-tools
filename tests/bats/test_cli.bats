#!/usr/bin/env bats

load "helpers/common"

setup() {
    setup_mock_bin
    create_tmux_mock "pane_list_empty.txt"
}

@test "--help で使用方法を表示して exit 0" {
    run python3 "$AGENT_PS" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Claude Code"* ]]
    [[ "$output" == *"GitHub Copilot"* ]]
}

@test "未知のフラグはエラー終了する" {
    run bash -c "python3 \"$AGENT_PS\" --unknown-flag 2>&1"
    [ "$status" -ne 0 ]
}

@test "--watch に非整数を渡すとエラー終了する" {
    run bash -c "python3 \"$AGENT_PS\" --watch foo 2>&1"
    [ "$status" -ne 0 ]
}

@test "--notify フラグは受け付けて exit 0" {
    run python3 "$AGENT_PS" --notify
    [ "$status" -eq 0 ]
}

@test "-w（引数なし）を受け付ける" {
    run timeout 2 python3 "$AGENT_PS" -w
    # timeout(124) または正常終了(0) のどちらも許容
    [[ "$status" -eq 0 || "$status" -eq 124 ]]
}

@test "-w に整数値を渡すと受け付ける" {
    run timeout 2 python3 "$AGENT_PS" -w 3
    [[ "$status" -eq 0 || "$status" -eq 124 ]]
}
