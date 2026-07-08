#!/usr/bin/env bats

load "helpers/common"

@test "is_claude_pane: バージョン形式のコマンドはマッチする" {
    run call_python is_claude_pane "1.3.0" ""
    [ "$status" -eq 0 ]
    [ "$output" = "True" ]
}

@test "is_claude_pane: タイトルに 'Claude Code' を含む場合マッチする" {
    run call_python is_claude_pane "bash" "✺ Claude Code doing work"
    [ "$status" -eq 0 ]
    [ "$output" = "True" ]
}

@test "is_claude_pane: 無関係なコマンドとタイトルはマッチしない" {
    run call_python is_claude_pane "node" "node server"
    [ "$status" -eq 0 ]
    [ "$output" = "False" ]
}

@test "is_claude_pane: 部分的なバージョン文字列('1.3')はマッチしない" {
    run call_python is_claude_pane "1.3" ""
    [ "$status" -eq 0 ]
    [ "$output" = "False" ]
}

@test "is_claude_pane: 空のコマンドとタイトルはマッチしない" {
    run call_python is_claude_pane "" ""
    [ "$status" -eq 0 ]
    [ "$output" = "False" ]
}

@test "is_copilot_pane: cmd=copilot は直接マッチする" {
    run call_python is_copilot_pane "copilot" "99999"
    [ "$status" -eq 0 ]
    [ "$output" = "True" ]
}

@test "is_copilot_pane: cmd=bash はマッチしない" {
    run call_python is_copilot_pane "bash" "99999"
    [ "$status" -eq 0 ]
    [ "$output" = "False" ]
}

@test "is_copilot_pane: cmd=python はマッチしない" {
    run call_python is_copilot_pane "python" "99999"
    [ "$status" -eq 0 ]
    [ "$output" = "False" ]
}

@test "is_codex_pane: cmd=codex は直接マッチする" {
    run call_python is_codex_pane "codex" "99999"
    [ "$status" -eq 0 ]
    [ "$output" = "True" ]
}

@test "is_codex_pane: cmd=bash はマッチしない" {
    run call_python is_codex_pane "bash" "99999"
    [ "$status" -eq 0 ]
    [ "$output" = "False" ]
}

@test "is_codex_pane: cmd=node で子プロセスにcodexがなければマッチしない" {
    run call_python is_codex_pane "node" "99999"
    [ "$status" -eq 0 ]
    [ "$output" = "False" ]
}
