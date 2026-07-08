#!/usr/bin/env bats

load "helpers/common"

setup() {
    setup_mock_bin
}

# _classify_key: SGR マウスシーケンスの判定

@test "_classify_key: 左クリック press は click イベントとして認識される" {
    run call_python classify_key_hex "1b5b3c303b31323b354d"
    [ "$status" -eq 0 ]
    [ "$output" = "click:12:5" ]
}

@test "_classify_key: 左クリック release は無視される（other）" {
    run call_python classify_key_hex "1b5b3c303b31323b356d"
    [ "$status" -eq 0 ]
    [ "$output" = "other" ]
}

@test "_classify_key: 右クリックは無視される（other）" {
    run call_python classify_key_hex "1b5b3c323b31323b354d"
    [ "$status" -eq 0 ]
    [ "$output" = "other" ]
}

@test "_classify_key: ホイールイベントは無視される（other）" {
    run call_python classify_key_hex "1b5b3c36343b31323b354d"
    [ "$status" -eq 0 ]
    [ "$output" = "other" ]
}

@test "_classify_key: 矢印キーは従来通り認識される（回帰確認）" {
    run call_python classify_key_hex "1b5b41"
    [ "$status" -eq 0 ]
    [ "$output" = "up" ]
}

# _pane_at_row: 行番号 -> pane_id_num の直接解決

@test "_pane_at_row: テーブルモードではヘッダー2行の後にpaneが1行ずつ並ぶ" {
    run call_python pane_at_row 0 2 "42,43"
    [ "$status" -eq 0 ]
    [ "$output" = "42" ]
    run call_python pane_at_row 0 3 "42,43"
    [ "$status" -eq 0 ]
    [ "$output" = "43" ]
}

@test "_pane_at_row: horizontalモードではpane毎に3行がクリック可能、4行目(区切り線)はNone" {
    run call_python pane_at_row 1 0 "42,43"
    [ "$status" -eq 0 ]
    [ "$output" = "42" ]
    run call_python pane_at_row 1 2 "42,43"
    [ "$status" -eq 0 ]
    [ "$output" = "42" ]
    run call_python pane_at_row 1 3 "42,43"
    [ "$status" -eq 0 ]
    [ "$output" = "None" ]
    run call_python pane_at_row 1 4 "42,43"
    [ "$status" -eq 0 ]
    [ "$output" = "43" ]
    run call_python pane_at_row 1 6 "42,43"
    [ "$status" -eq 0 ]
    [ "$output" = "43" ]
}

# handle_click: クリック座標 -> (selected, action)

@test "handle_click: テーブル行をクリックすると選択+即フォーカスになる" {
    run call_python handle_click 5 "42,43" "-" 0
    [ "$status" -eq 0 ]
    [ "$output" = "42,focus" ]
}

@test "handle_click: 2行目のpaneをクリックすると2行目が選択+フォーカスされる" {
    run call_python handle_click 6 "42,43" "-" 0
    [ "$status" -eq 0 ]
    [ "$output" = "43,focus" ]
}

@test "handle_click: ヘッダー行をクリックしても選択状態は変わらない" {
    run call_python handle_click 4 "42,43" "42" 0
    [ "$status" -eq 0 ]
    [ "$output" = "42,None" ]
}

@test "handle_click: horizontalモードでも正しいpaneに当たる" {
    run call_python handle_click 7 "42,43" "-" 1
    [ "$status" -eq 0 ]
    [ "$output" = "43,focus" ]
}

# handle_key: h キーでヘルプ表示のトグルアクションを返す

@test "handle_key: h キーで toggle_help アクションを返す" {
    run call_python handle_key h "" -
    [ "$status" -eq 0 ]
    [ "$output" = "None,toggle_help" ]
}

# CLI レベル: ウォッチモードのヒント行はデフォルト非表示、h でトグル可能

@test "-w のヒント行はデフォルトでヘルプが非表示になる" {
    create_tmux_mock "pane_list_empty.txt"
    run timeout 2 python3 "$AGENT_PS" -w
    [[ "$output" == *"h help"* ]]
    [[ "$output" != *"click select+focus"* ]]
}
