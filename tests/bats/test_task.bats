#!/usr/bin/env bats

load "helpers/common"

# claude_task

@test "claude_task: 'Claude Code' プレフィックスを除去する" {
    run call_python claude_task "Claude Code refactoring"
    [ "$status" -eq 0 ]
    [ "$output" = "refactoring" ]
}

@test "claude_task: アイドルマーク直後の 'Claude Code' プレフィックスを除去する" {
    run call_python claude_task "✺Claude Code doing work"
    [ "$status" -eq 0 ]
    [ "$output" = "doing work" ]
}

@test "claude_task: アイドルマークの後にスペースがある場合は 'Claude Code' が残る" {
    run call_python claude_task "✺ Claude Code doing work"
    [ "$status" -eq 0 ]
    [ "$output" = "Claude Code doing work" ]
}

@test "claude_task: 55文字を超えるタスクは省略記号で切り詰める" {
    local long_title
    long_title="Claude Code $(python3 -c "print('x' * 60)")"
    run call_python claude_task "$long_title"
    [ "$status" -eq 0 ]
    [ "${#output}" -le 55 ]
    [[ "$output" == *"..." ]]
}

@test "claude_task: 55文字以下のタスクはそのまま返す" {
    run call_python claude_task "Claude Code short task"
    [ "$status" -eq 0 ]
    [[ "$output" != *"..." ]]
}

@test "claude_task: 空のタイトルは空文字を返す" {
    run call_python claude_task ""
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# copilot_task

@test "copilot_task: ロボット絵文字プレフィックスを除去する" {
    run call_python copilot_task "🤖 doing work"
    [ "$status" -eq 0 ]
    [ "$output" = "doing work" ]
}

@test "copilot_task: プレフィックスなしのタイトルはそのまま返す" {
    run call_python copilot_task "plain task"
    [ "$status" -eq 0 ]
    [ "$output" = "plain task" ]
}

@test "copilot_task: 55文字を超えるタスクは省略記号で切り詰める" {
    local long_title
    long_title="🤖 $(python3 -c "print('x' * 60)")"
    run call_python copilot_task "$long_title"
    [ "$status" -eq 0 ]
    [ "${#output}" -le 55 ]
    [[ "$output" == *"..." ]]
}

@test "copilot_task: 空のタイトルは空文字を返す" {
    run call_python copilot_task ""
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}
