#!/usr/bin/env bats

load "helpers/common"

# claude_status

@test "claude_status: コンテンツにブレイユ文字があれば running" {
    # U+2801 = ⠁ (ブレイユ文字)
    run call_python claude_status "" $'⠁ processing'
    [ "$status" -eq 0 ]
    [ "$output" = "running" ]
}

@test "claude_status: タイトルにアイドルマーク、コンテンツにブレイユなし → idle" {
    run call_python claude_status "✺ idle" ""
    [ "$status" -eq 0 ]
    [ "$output" = "idle" ]
}

@test "claude_status: コンテンツに選択カーソル(❯ N.) があれば waiting_for_input" {
    run call_python claude_status "" $'❯  1. option one'
    [ "$status" -eq 0 ]
    [ "$output" = "waiting_for_input" ]
}

@test "claude_status: nav hint が末尾行にあれば waiting_for_input" {
    local content=$'│ Do you want to proceed? │\n╰─────────────────────────╯'
    run call_python claude_status "" "$content"
    [ "$status" -eq 0 ]
    [ "$output" = "waiting_for_input" ]
}

@test "claude_status: nav hint の後にコンテンツ行があれば waiting_for_input にならない" {
    local content=$'Do you want to proceed?\nsome other content'
    run call_python claude_status "" "$content"
    [ "$status" -eq 0 ]
    [ "$output" != "waiting_for_input" ]
}

@test "claude_status: タイトルもコンテンツも空なら unknown" {
    run call_python claude_status "" ""
    [ "$status" -eq 0 ]
    [ "$output" = "unknown" ]
}

@test "claude_status: タイトルがブレイユ文字で始まれば running" {
    run call_python claude_title_status $'⠁title'
    [ "$status" -eq 0 ]
    [ "$output" = "running" ]
}

# copilot_status

@test "copilot_status: ロボット絵文字のタイトルなら running" {
    run call_python copilot_status "🤖 doing task" ""
    [ "$status" -eq 0 ]
    [ "$output" = "running" ]
}

@test "copilot_status: ロボット絵文字なしのタイトルなら idle" {
    run call_python copilot_status "plain title" ""
    [ "$status" -eq 0 ]
    [ "$output" = "idle" ]
}

@test "copilot_status: コンテンツに nav hint があれば waiting_for_input" {
    local content=$'↑↓ to navigate options\n╰───────────────────────╯'
    run call_python copilot_status "" "$content"
    [ "$status" -eq 0 ]
    [ "$output" = "waiting_for_input" ]
}

@test "copilot_status: nav hint の後にコンテンツ行があれば waiting_for_input にならない" {
    local content=$'↑↓ to navigate options\nsome other content'
    run call_python copilot_status "" "$content"
    [ "$status" -eq 0 ]
    [ "$output" != "waiting_for_input" ]
}

@test "copilot_status: Setting workspace の選択プロンプトなら waiting_for_input" {
    local content=$'Do you want to run this command?\n\n❯ 1. Yes\n  2. No\n\n↑/↓ to navigate · enter to select · esc to cancel\n╰─────────────────────────╯'
    run call_python copilot_status "🤖 Setting workspace" "$content"
    [ "$status" -eq 0 ]
    [ "$output" = "waiting_for_input" ]
}

@test "copilot_status: 'Enter accept' の nav hint があれば waiting_for_input" {
    local content=$'Enter accept\n╰───────────────╯'
    run call_python copilot_status "" "$content"
    [ "$status" -eq 0 ]
    [ "$output" = "waiting_for_input" ]
}

# claude_status: 追加フレーズ

@test "claude_status: 'waiting for permission' があれば waiting_for_input" {
    local content=$'waiting for permission\n╰───────────────╯'
    run call_python claude_status "" "$content"
    [ "$status" -eq 0 ]
    [ "$output" = "waiting_for_input" ]
}

@test "claude_status: 'tab to amend' があれば waiting_for_input" {
    local content=$'tab to amend\n╰───────────────╯'
    run call_python claude_status "" "$content"
    [ "$status" -eq 0 ]
    [ "$output" = "waiting_for_input" ]
}

@test "claude_status: 'run a dynamic workflow?' があれば waiting_for_input" {
    local content=$'run a dynamic workflow?\n╰───────────────╯'
    run call_python claude_status "" "$content"
    [ "$status" -eq 0 ]
    [ "$output" = "waiting_for_input" ]
}

# codex_title_status

@test "codex_title_status: タイトルが空なら unknown" {
    run call_python codex_title_status ""
    [ "$status" -eq 0 ]
    [ "$output" = "unknown" ]
}

@test "codex_title_status: タイトルに 'Action Required' を含めば waiting_for_input" {
    run call_python codex_title_status "Action Required: approve command"
    [ "$status" -eq 0 ]
    [ "$output" = "waiting_for_input" ]
}

@test "codex_title_status: タイトルがブレイユ文字で始まれば running" {
    run call_python codex_title_status $'⠁title'
    [ "$status" -eq 0 ]
    [ "$output" = "running" ]
}

@test "codex_title_status: 通常タイトルなら idle" {
    run call_python codex_title_status "codex fixing bug"
    [ "$status" -eq 0 ]
    [ "$output" = "idle" ]
}

# codex_status

@test "codex_status: nav hint(allow command?)が末尾行にあれば waiting_for_input" {
    local content=$'│ Allow command? │\n╰─────────────────╯'
    run call_python codex_status "codex fixing bug" "$content"
    [ "$status" -eq 0 ]
    [ "$output" = "waiting_for_input" ]
}

@test "codex_status: nav hint の後にコンテンツ行があれば waiting_for_input にならない" {
    local content=$'Allow command?\nsome other content'
    run call_python codex_status "codex fixing bug" "$content"
    [ "$status" -eq 0 ]
    [ "$output" != "waiting_for_input" ]
}

@test "codex_status: コンテンツに nav hint が無ければタイトル判定にフォールバックする(running)" {
    run call_python codex_status $'⠁title' ""
    [ "$status" -eq 0 ]
    [ "$output" = "running" ]
}
