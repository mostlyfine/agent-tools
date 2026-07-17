#!/usr/bin/env bash
# Custom statusline for Claude Code
# Reads JSON from stdin and outputs formatted status line.

# --- Display flags (デフォルトは全項目表示) ---
show_model=1
show_branch=1
show_repo=1
show_cost=1
show_diff=1
show_current_context=1
show_weekly_context=1

while [ $# -gt 0 ]; do
  case "$1" in
    --no-model|-m) show_model=0 ;;
    --no-branch|-b) show_branch=0 ;;
    --no-repo|-r) show_repo=0 ;;
    --no-cost|-c) show_cost=0 ;;
    --no-diff|-d) show_diff=0 ;;
    --no-current-context|-cc) show_current_context=0 ;;
    --no-weekly-context|-wc) show_weekly_context=0 ;;
  esac
  shift
done

input=$(cat)

# --- Extract fields from input JSON (1回のjq呼び出しにまとめてプロセス起動を削減) ---
# 区切り文字はタブではなくUnit Separator(\x1f)を使う。タブはbashのIFSホワイトスペース
# として連続区切りが圧縮されるため、空文字フィールドがあるとフィールドがずれてしまう。
field_sep=$'\x1f'
IFS="$field_sep" read -r model cost_usd lines_added lines_removed transcript cwd \
  cw_total_in cw_total_out ctx_remaining_raw ctx_used_raw \
  rl_five_pct rl_five_resets_epoch rl_seven_pct repo_name \
  <<< "$(jq -r --arg sep "$field_sep" '[
    (.model.display_name // "Claude"),
    (.cost.total_cost_usd // 0),
    (.cost.total_lines_added // 0),
    (.cost.total_lines_removed // 0),
    (.transcript_path // ""),
    (.workspace.current_dir // .cwd // ""),
    (.context_window.total_input_tokens // ""),
    (.context_window.total_output_tokens // ""),
    (.context_window.remaining_percentage // ""),
    (.context_window.used_percentage // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.workspace.repo.name // "")
  ] | join($sep)' <<< "$input")"

is_vertex=0
[ "$CLAUDE_CODE_USE_VERTEX" = "1" ] && is_vertex=1

# --- ANSI colors ---
RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
MAGENTA=$'\033[35m'
GRAY=$'\033[90m'
WHITE=$'\033[97m'

# --- Context window usage (backend非依存: JSON直値を優先) ---
if [ -n "$cw_total_in" ] || [ -n "$cw_total_out" ]; then
  ctx_tokens=$(awk -v a="${cw_total_in:-0}" -v b="${cw_total_out:-0}" 'BEGIN { printf "%d", a + b }')
else
  ctx_tokens=0
  if [ -f "$transcript" ]; then
    ctx_tokens=$(jq -r 'select(.message.usage) | (.message.usage.input_tokens // 0) + (.message.usage.cache_read_input_tokens // 0) + (.message.usage.cache_creation_input_tokens // 0)' "$transcript" 2>/dev/null | tail -1)
    if [ -z "$ctx_tokens" ] || [ "$ctx_tokens" = "null" ]; then
      ctx_tokens=0
    fi
  fi
fi

ctx_pct=""
if [ -n "$ctx_remaining_raw" ]; then
  ctx_pct=$(awk -v v="$ctx_remaining_raw" 'BEGIN { printf "%.0f", v }')
elif [ -n "$ctx_used_raw" ]; then
  ctx_pct=$(awk -v v="$ctx_used_raw" 'BEGIN { printf "%.0f", 100 - v }')
fi

if [ -n "$ctx_pct" ]; then
  ctx_pct_display="${ctx_pct}%"
  if [ "$ctx_pct" -gt 50 ]; then
    ctx_color="$GREEN"
  elif [ "$ctx_pct" -gt 20 ]; then
    ctx_color="$YELLOW"
  else
    ctx_color="$RED"
  fi
else
  ctx_pct_display="--%"
  ctx_color="$GRAY"
fi

# --- Usage window (5時間/7日) の Keychain + Anthropic OAuth Usage API フォールバック ---
# rate_limits がJSONに存在しない旧バージョンのClaude Code、かつVertex AI以外の場合のみ使用する。
_get_claude_token() {
  local raw
  raw=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null) || return 1
  if echo "$raw" | grep -qE '^[0-9a-f]+$'; then
    raw=$(echo "$raw" | xxd -r -p 2>/dev/null) || return 1
  fi
  echo "$raw" | jq -r '.claudeAiOauth.accessToken // .accessToken // empty' 2>/dev/null
}

_iso8601_to_epoch() {
  local normalized
  normalized=$(echo "$1" | sed 's/\.[0-9]*//' | sed 's/+00:00$/+0000/')
  date -jf "%Y-%m-%dT%H:%M:%S%z" "$normalized" "+%s" 2>/dev/null
}

_remaining_pct() {
  awk -v u="$1" -v fmt="$2" 'BEGIN { printf fmt, 100 - u }'
}

_get_usage_resets_at() {
  local cache="/tmp/oauth-usage-cache.json"
  local now_epoch
  now_epoch=$(date "+%s")
  if [ -f "$cache" ]; then
    local cached_time
    cached_time=$(jq -r '.cached_at // 0' "$cache" 2>/dev/null)
    if [ $(( now_epoch - cached_time )) -lt 60 ]; then
      jq -r '.resets_at // empty' "$cache" 2>/dev/null
      return
    fi
  fi
  local token
  token=$(_get_claude_token) || return 1
  local response
  response=$(curl -s --max-time 3 \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null) || return 1
  local resets_at
  resets_at=$(echo "$response" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)
  [ -z "$resets_at" ] && return 1
  local utilization
  utilization=$(echo "$response" | jq -r '(.seven_day.utilization // .five_hour.utilization // "null")' 2>/dev/null)
  local five_hour_util
  five_hour_util=$(echo "$response" | jq -r '(.five_hour.utilization // "null")' 2>/dev/null)
  jq -n --arg r "$resets_at" --arg t "$now_epoch" --arg u "$utilization" --arg f "$five_hour_util" \
    '{
      "resets_at": $r,
      "cached_at": ($t | tonumber),
      "utilization": ($u | if . == "null" then null else tonumber end),
      "five_hour_utilization": ($f | if . == "null" then null else tonumber end)
    }' > "$cache" 2>/dev/null
  echo "$resets_at"
}

# --- Rate limits (5時間/7日ウィンドウ) ---
five_hour_remaining=""
five_hour_time_left=""
remaining_pct=""
reset_epoch=""

if [ -n "$rl_five_pct" ] || [ -n "$rl_five_resets_epoch" ]; then
  # Claude Code自身がJSONに含めたrate_limitsを最優先で使う（Vertex AI/通常認証どちらでも有効）。
  if [ -n "$rl_five_pct" ]; then
    five_hour_remaining=$(_remaining_pct "$rl_five_pct" "%.1f")
  fi
  if [ -n "$rl_five_resets_epoch" ]; then
    reset_epoch="$rl_five_resets_epoch"
  fi
  if [ -n "$rl_seven_pct" ]; then
    remaining_pct=$(_remaining_pct "$rl_seven_pct" "%.0f")
  fi
elif [ "$is_vertex" -ne 1 ]; then
  # rate_limitsを返さない旧バージョン向けの救済経路(Vertex AIはClaude.ai OAuthの使用量ウィンドウを持たないため対象外)。
  resets_at=$(_get_usage_resets_at 2>/dev/null)
  if [ -n "$resets_at" ]; then
    reset_epoch=$(_iso8601_to_epoch "$resets_at")
  fi
  cache_file="/tmp/oauth-usage-cache.json"
  if [ -f "$cache_file" ]; then
    utilization_raw=$(jq -r '.utilization // empty' "$cache_file" 2>/dev/null)
    if [ -n "$utilization_raw" ] && [ "$utilization_raw" != "null" ]; then
      remaining_pct=$(_remaining_pct "$utilization_raw" "%.0f")
    fi
    fh_util=$(jq -r '.five_hour_utilization // empty' "$cache_file" 2>/dev/null)
    if [ -n "$fh_util" ] && [ "$fh_util" != "null" ]; then
      five_hour_remaining=$(_remaining_pct "$fh_util" "%.1f")
    fi
  fi
fi

if [ -n "$reset_epoch" ]; then
  now_epoch=$(date "+%s")
  secs_left=$(( reset_epoch - now_epoch ))
  if [ "$secs_left" -gt 0 ]; then
    h=$(( secs_left / 3600 ))
    m=$(( (secs_left % 3600) / 60 ))
    if [ "$h" -gt 0 ]; then
      five_hour_time_left="${h}h ${m}m left"
    else
      five_hour_time_left="${m}m left"
    fi
  fi
fi

# --- Git branch ---
git_branch=""
repo_str=""
if { [ "$show_branch" -eq 1 ] || [ "$show_repo" -eq 1 ]; } && [ -n "$cwd" ] && [ -d "$cwd" ]; then
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
  if [ -n "$branch" ]; then
    # workspace.repo.name (originリモートから解析済み) を優先し、
    # 無ければメインリポジトリの .git ディレクトリの親ディレクトリ名にフォールバックする。
    # git worktree 配下では --show-toplevel が worktree 自身のパスを返してしまうため、
    # worktree でも常にメインリポジトリを指す --git-common-dir を使う。
    if [ -z "$repo_name" ]; then
      common_dir=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
      if [ -n "$common_dir" ]; then
        repo_root="${common_dir%/*}"
        repo_name="${repo_root##*/}"
      fi
    fi
    git_branch="${MAGENTA} ${branch}${RESET}"
    [ -n "$repo_name" ] && repo_str="${CYAN}  ${repo_name}${RESET}"
  fi
fi

# --- Format helpers ---
[ "$show_current_context" -eq 1 ] && ctx_tokens_fmt=$(awk -v t="$ctx_tokens" 'BEGIN {
  if (t >= 1000) printf "%.1fk", t/1000;
  else printf "%d", t;
}')
[ "$show_cost" -eq 1 ] && cost_fmt=$(awk -v c="$cost_usd" 'BEGIN { printf "%.4f", c }')

# --- Build output ---
# outputが空の間は sep を付けず、次の追加時には sep を付ける。
# 先頭ブロック（mode）が非表示でも余計な" | "が付かないようこの関数で判定する。
sep="${DIM} | ${RESET}"
output=""
_append_segment() {
  if [ -z "$output" ]; then
    output="$1"
  else
    output="${output}${sep}${1}"
  fi
}

[ "$show_model" -eq 1 ] && _append_segment "${CYAN}󰚩${RESET}  ${BOLD}${model}${RESET}"
[ "$show_branch" -eq 1 ] && [ -n "$git_branch" ] && _append_segment "$git_branch"
[ "$show_repo" -eq 1 ] && [ -n "$repo_str" ] && _append_segment "$repo_str"
[ "$show_diff" -eq 1 ] && { [ "$lines_added" -gt 0 ] || [ "$lines_removed" -gt 0 ]; } && _append_segment "${GREEN}+${lines_added}${RESET}/${RED}-${lines_removed}${RESET}"
[ "$show_cost" -eq 1 ] && _append_segment "${BOLD}\$${cost_fmt}${RESET}"
[ "$show_current_context" -eq 1 ] && _append_segment "${ctx_color}  ${ctx_pct_display} (${ctx_tokens_fmt})${RESET}"
if [ -n "$five_hour_remaining" ]; then
  fh_int=$(printf "%.0f" "$five_hour_remaining")
  if   [ "$fh_int" -gt 60 ]; then fh_color="$GREEN"
  elif [ "$fh_int" -gt 40 ]; then fh_color="$YELLOW"
  elif [ "$fh_int" -gt 20 ]; then fh_color="$YELLOW"
  else fh_color="$RED"; fi
  fh_str="⏱ ${five_hour_remaining}%"
  [ -n "$five_hour_time_left" ] && fh_str="${fh_str} (${five_hour_time_left})"
  _append_segment "${fh_color}${fh_str}${RESET}"
fi
if [ "$show_weekly_context" -eq 1 ] && [ -n "$remaining_pct" ]; then
  if [ "$remaining_pct" -ge 80 ]; then
    rate_color="$GREEN"
  elif [ "$remaining_pct" -ge 40 ]; then
    rate_color="$YELLOW"
  else
    rate_color="$RED"
  fi
  _append_segment "${rate_color} ${remaining_pct}%${RESET}"
fi

printf "%b" "$output"
