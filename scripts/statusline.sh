#!/usr/bin/env bash
# Custom statusline for Claude Code
# Reads JSON from stdin and outputs formatted status line.

input=$(cat)

# --- Extract fields from input JSON ---
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
transcript=$(echo "$input" | jq -r '.transcript_path // ""')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')

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
cw_total_in=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
cw_total_out=$(echo "$input" | jq -r '.context_window.total_output_tokens // empty')
ctx_remaining_raw=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
ctx_used_raw=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

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
rl_five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rl_five_resets_epoch=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
rl_seven_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

five_hour_remaining=""
five_hour_time_left=""
remaining_pct=""
reset_epoch=""

if [ -n "$rl_five_pct" ] || [ -n "$rl_five_resets_epoch" ]; then
  # Claude Code自身がJSONに含めたrate_limitsを最優先で使う（Vertex AI/通常認証どちらでも有効）。
  if [ -n "$rl_five_pct" ]; then
    five_hour_remaining=$(awk -v u="$rl_five_pct" 'BEGIN { printf "%.1f", 100 - u }')
  fi
  if [ -n "$rl_five_resets_epoch" ]; then
    reset_epoch="$rl_five_resets_epoch"
  fi
  if [ -n "$rl_seven_pct" ]; then
    remaining_pct=$(awk -v u="$rl_seven_pct" 'BEGIN { printf "%.0f", 100 - u }')
  fi
elif [ "$is_vertex" -eq 1 ]; then
  # Vertex AIはClaude.ai OAuthの使用量ウィンドウを持たないため、この欄自体を省略する。
  :
else
  # rate_limitsを返さない旧バージョン向けの救済経路。
  resets_at=$(_get_usage_resets_at 2>/dev/null)
  if [ -n "$resets_at" ]; then
    reset_epoch=$(_iso8601_to_epoch "$resets_at")
  fi
  cache_file="/tmp/oauth-usage-cache.json"
  if [ -f "$cache_file" ]; then
    utilization_raw=$(jq -r '.utilization // empty' "$cache_file" 2>/dev/null)
    if [ -n "$utilization_raw" ] && [ "$utilization_raw" != "null" ]; then
      remaining_pct=$(awk -v u="$utilization_raw" 'BEGIN { printf "%.0f", 100 - u }')
    fi
    fh_util=$(jq -r '.five_hour_utilization // empty' "$cache_file" 2>/dev/null)
    if [ -n "$fh_util" ] && [ "$fh_util" != "null" ]; then
      five_hour_remaining=$(awk -v u="$fh_util" 'BEGIN { printf "%.1f", 100 - u }')
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
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
  if [ -n "$branch" ]; then
    # workspace.repo.name (originリモートから解析済み) を優先し、
    # 無ければトップレベルディレクトリ名にフォールバックする。
    repo_name=$(echo "$input" | jq -r '.workspace.repo.name // empty')
    if [ -z "$repo_name" ]; then
      toplevel=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
      [ -n "$toplevel" ] && repo_name=$(basename "$toplevel")
    fi
    if [ -n "$repo_name" ]; then
      git_branch="${MAGENTA} ${branch}${RESET}${DIM} | ${RESET}${CYAN}  ${repo_name}${RESET}"
    else
      git_branch="${MAGENTA} ${branch}${RESET}"
    fi
  fi
fi

# --- Format helpers ---
ctx_tokens_fmt=$(awk -v t="$ctx_tokens" 'BEGIN {
  if (t >= 1000) printf "%.1fk", t/1000;
  else printf "%d", t;
}')
cost_fmt=$(awk -v c="$cost_usd" 'BEGIN { printf "%.4f", c }')

# --- Build output ---
sep="${DIM} | ${RESET}"
output="${CYAN}󰚩${RESET}  ${BOLD}${model}${RESET}"
[ -n "$git_branch" ] && output="${output}${sep}${git_branch}"
if [ "$lines_added" -gt 0 ] || [ "$lines_removed" -gt 0 ]; then
  output="${output}${sep}${GREEN}+${lines_added}${RESET}/${RED}-${lines_removed}${RESET}"
fi
output="${output}${sep}${BOLD}\$${cost_fmt}${RESET}"
output="${output}${sep}${ctx_color}  ${ctx_pct_display} (${ctx_tokens_fmt})${RESET}"
if [ -n "$five_hour_remaining" ]; then
  fh_int=$(printf "%.0f" "$five_hour_remaining")
  if   [ "$fh_int" -gt 60 ]; then fh_color="$GREEN"
  elif [ "$fh_int" -gt 40 ]; then fh_color="$YELLOW"
  elif [ "$fh_int" -gt 20 ]; then fh_color="$YELLOW"
  else fh_color="$RED"; fi
  fh_str="⏱ ${five_hour_remaining}%"
  [ -n "$five_hour_time_left" ] && fh_str="${fh_str} (${five_hour_time_left})"
  output="${output}${sep}${fh_color}${fh_str}${RESET}"
fi
if [ -n "$remaining_pct" ]; then
  if [ "$remaining_pct" -ge 80 ]; then
    rate_color="$GREEN"
  elif [ "$remaining_pct" -ge 40 ]; then
    rate_color="$YELLOW"
  else
    rate_color="$RED"
  fi
  output="${output}${sep}${rate_color} ${remaining_pct}%${RESET}"
fi

printf "%b" "$output"
