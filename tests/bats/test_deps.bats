#!/usr/bin/env bats

load "helpers/common"

setup() {
    setup_mock_bin
}

@test "tmux が PATH にない場合は exit 1 でエラーを出力する" {
    # mock_bin に tmux を置かないまま、PATH から tmux を除外する
    local safe_path="$BATS_TEST_TMPDIR/mock_bin:/usr/bin:/bin"
    run bash -c "PATH=\"$safe_path\" python3 \"$AGENT_PS\" 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"tmux is not installed"* ]]
}

@test "TMUX 環境変数が未設定の場合は exit 1 でエラーを出力する" {
    create_tmux_mock "pane_list_empty.txt"
    run bash -c "env -u TMUX python3 \"$AGENT_PS\" 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"must be run inside a tmux session"* ]]
}

@test "tmux が存在して TMUX が設定されている場合は exit 0" {
    create_tmux_mock "pane_list_empty.txt"
    run python3 "$AGENT_PS"
    [ "$status" -eq 0 ]
}
