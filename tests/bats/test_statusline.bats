#!/usr/bin/env bats

load "helpers/common"

setup() {
    STATUSLINE="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/scripts/statusline.sh"
    setup_mock_bin
    export CALL_LOG="$BATS_TEST_TMPDIR/calls.log"
    rm -f /tmp/oauth-usage-cache.json
}

teardown() {
    rm -f /tmp/oauth-usage-cache.json
}

# security/curl 呼び出しを記録しつつ、Keychain 由来のフォールバック経路を模倣するモック
create_network_mocks() {
    local token_output="${1:-fake-token}"
    local curl_json="${2:-}"

    cat > "$BATS_TEST_TMPDIR/mock_bin/security" << MOCK_EOF
#!/usr/bin/env bash
echo "security \$*" >> "$CALL_LOG"
if [ -n "$token_output" ]; then
  cat << 'JSON_EOF'
{"claudeAiOauth":{"accessToken":"$token_output"}}
JSON_EOF
  exit 0
else
  exit 1
fi
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mock_bin/security"

    cat > "$BATS_TEST_TMPDIR/mock_bin/curl" << MOCK_EOF
#!/usr/bin/env bash
echo "curl \$*" >> "$CALL_LOG"
cat << 'JSON_EOF'
$curl_json
JSON_EOF
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mock_bin/curl"
}

@test "rate_limits がJSONにある場合はコンテキスト%とトークン数を表示する" {
    input='{
      "model": {"display_name": "Claude"},
      "cost": {"total_cost_usd": 1.2345, "total_lines_added": 3, "total_lines_removed": 1},
      "context_window": {"total_input_tokens": 1500, "total_output_tokens": 500, "remaining_percentage": 62.4},
      "rate_limits": {"five_hour": {"used_percentage": 30, "resets_at": 9999999999}}
    }'
    run bash -c "echo '$input' | \"$STATUSLINE\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"62%"* ]]
    [[ "$output" == *"2.0k"* ]]
}

@test "rate_limits がJSONにある場合は5時間ウィンドウの残量を表示する" {
    input='{
      "model": {"display_name": "Claude"},
      "context_window": {"total_input_tokens": 100, "total_output_tokens": 0, "remaining_percentage": 90},
      "rate_limits": {"five_hour": {"used_percentage": 30, "resets_at": 9999999999}}
    }'
    run bash -c "echo '$input' | \"$STATUSLINE\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"70.0%"* ]]
}

@test "rate_limits がJSONにある場合はKeychain/curlを呼ばない" {
    create_network_mocks "fake-token" "{}"
    input='{
      "model": {"display_name": "Claude"},
      "context_window": {"total_input_tokens": 100, "total_output_tokens": 0, "remaining_percentage": 90},
      "rate_limits": {"five_hour": {"used_percentage": 30, "resets_at": 9999999999}}
    }'
    run bash -c "echo '$input' | \"$STATUSLINE\""
    [ "$status" -eq 0 ]
    [ ! -f "$CALL_LOG" ]
}

@test "rate_limitsが無くVertexでない場合はKeychain経由のフォールバックを使う" {
    future_epoch=$(($(date "+%s") + 7200))
    future_iso=$(TZ=UTC date -r "$future_epoch" "+%Y-%m-%dT%H:%M:%S+00:00")
    curl_json="{\"five_hour\":{\"resets_at\":\"$future_iso\",\"utilization\":25}}"
    create_network_mocks "fake-token" "$curl_json"
    input='{
      "model": {"display_name": "Claude"},
      "context_window": {"total_input_tokens": 100, "total_output_tokens": 0, "remaining_percentage": 90}
    }'
    run bash -c "unset CLAUDE_CODE_USE_VERTEX; echo '$input' | \"$STATUSLINE\""
    [ "$status" -eq 0 ]
    [ -f "$CALL_LOG" ]
    grep -q "security" "$CALL_LOG"
    grep -q "curl" "$CALL_LOG"
}

@test "Vertex環境でrate_limitsが無い場合は5時間ウィンドウ欄を省略しKeychainを呼ばない" {
    create_network_mocks "fake-token" "{}"
    input='{
      "model": {"display_name": "Claude"},
      "context_window": {"total_input_tokens": 100, "total_output_tokens": 0, "remaining_percentage": 90}
    }'
    run env CLAUDE_CODE_USE_VERTEX=1 bash -c "echo '$input' | \"$STATUSLINE\""
    [ "$status" -eq 0 ]
    [ ! -f "$CALL_LOG" ]
    [[ "$output" != *"⏱"* ]]
}

@test "context_windowのパーセンテージがnullの場合は0%ではなく--を表示する" {
    input='{
      "model": {"display_name": "Claude"},
      "context_window": {"total_input_tokens": null, "total_output_tokens": null, "remaining_percentage": null, "used_percentage": null}
    }'
    run env CLAUDE_CODE_USE_VERTEX=1 bash -c "echo '$input' | \"$STATUSLINE\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"--%"* ]]
    [[ "$output" != *"0%"* ]]
}

@test "remaining_percentageがnullでもused_percentageから残量%を逆算する" {
    input='{
      "model": {"display_name": "Claude"},
      "context_window": {"total_input_tokens": 100, "total_output_tokens": 0, "remaining_percentage": null, "used_percentage": 35}
    }'
    run env CLAUDE_CODE_USE_VERTEX=1 bash -c "echo '$input' | \"$STATUSLINE\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"65%"* ]]
}

# ANSIエスケープシーケンスを除去して素のテキストで比較するためのヘルパー
strip_ansi() {
    sed -E $'s/\x1b\\[[0-9;]*m//g' <<< "$1"
}

# git branch --show-current / rev-parse --git-common-dir の呼び出しを固定応答で模倣するモック
create_git_mock() {
    local branch_output="$1"
    local common_dir_output="$2"
    cat > "$BATS_TEST_TMPDIR/mock_bin/git" << MOCK_EOF
#!/usr/bin/env bash
case "\$3" in
  branch) echo "$branch_output" ;;
  rev-parse)
    if [ -n "$common_dir_output" ]; then
      echo "$common_dir_output"
    else
      exit 1
    fi
    ;;
  *) exit 1 ;;
esac
MOCK_EOF
    chmod +x "$BATS_TEST_TMPDIR/mock_bin/git"
}

@test "workspace.repo.nameとbranchが取得できる場合はbranch | repo-name形式で表示する" {
    create_git_mock "main" "/fake/agent-tools/.git"
    input=$(jq -n --arg cwd "$BATS_TEST_TMPDIR" '{
      "model": {"display_name": "Claude"},
      "workspace": {"current_dir": $cwd, "repo": {"name": "agent-tools"}},
      "context_window": {"total_input_tokens": 100, "total_output_tokens": 0, "remaining_percentage": 90}
    }')
    run env CLAUDE_CODE_USE_VERTEX=1 bash -c "echo '$input' | \"$STATUSLINE\""
    [ "$status" -eq 0 ]
    plain=$(strip_ansi "$output")
    [[ "$plain" == *"main | "$'\xef\x90\x93'"  agent-tools"* ]]
}

@test "workspace.repoが無くgit-common-dirが絶対パスで取れる場合はメインリポジトリ名で表示する" {
    create_git_mock "main" "/fake/other-repo/.git"
    input=$(jq -n --arg cwd "$BATS_TEST_TMPDIR" '{
      "model": {"display_name": "Claude"},
      "workspace": {"current_dir": $cwd},
      "context_window": {"total_input_tokens": 100, "total_output_tokens": 0, "remaining_percentage": 90}
    }')
    run env CLAUDE_CODE_USE_VERTEX=1 bash -c "echo '$input' | \"$STATUSLINE\""
    [ "$status" -eq 0 ]
    plain=$(strip_ansi "$output")
    [[ "$plain" == *"main | "$'\xef\x90\x93'"  other-repo"* ]]
}

@test "git worktree配下(cwdとリポジトリ名が異なる)でもgit-common-dirの親ディレクトリ名を表示する" {
    # linked worktree では git-common-dir がメインリポジトリの絶対パスを返す。
    # cwd (worktree自身のパス) の basename とは異なる名前になることを検証する。
    local worktree_dir="$BATS_TEST_TMPDIR/agent-ps-worktree-display"
    mkdir -p "$worktree_dir"
    create_git_mock "feature/x" "/fake/agent-tools/.git"
    input=$(jq -n --arg cwd "$worktree_dir" '{
      "model": {"display_name": "Claude"},
      "workspace": {"current_dir": $cwd},
      "context_window": {"total_input_tokens": 100, "total_output_tokens": 0, "remaining_percentage": 90}
    }')
    run env CLAUDE_CODE_USE_VERTEX=1 bash -c "echo '$input' | \"$STATUSLINE\""
    [ "$status" -eq 0 ]
    plain=$(strip_ansi "$output")
    [[ "$plain" == *"feature/x | "$'\xef\x90\x93'"  agent-tools"* ]]
    [[ "$plain" != *"agent-ps-worktree-display"* ]]
}

@test "workspace.repoもgit-common-dirも取得できずbranchのみ取得できる場合はブランチ名のみ表示する(後方互換)" {
    create_git_mock "main" ""
    input=$(jq -n --arg cwd "$BATS_TEST_TMPDIR" '{
      "model": {"display_name": "Claude"},
      "workspace": {"current_dir": $cwd},
      "context_window": {"total_input_tokens": 100, "total_output_tokens": 0, "remaining_percentage": 90}
    }')
    run env CLAUDE_CODE_USE_VERTEX=1 bash -c "echo '$input' | \"$STATUSLINE\""
    [ "$status" -eq 0 ]
    plain=$(strip_ansi "$output")
    [[ "$plain" == *"main"* ]]
    # branchの直後にリポジトリ名用のCYANカラーが続かないこと（repo_name未解決時に付与されないことの確認）
    [[ "$output" != *$'\033[35m\xef\x84\xa6 main\033[0m\033[2m | \033[0m\033[36m'* ]]
}
