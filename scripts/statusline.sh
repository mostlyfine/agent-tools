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

# --- ANSI colors ---
RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
MAGENTA=$'\033[35m'

# --- Context window usage ---
ctx_tokens=0
ctx_pct=0
ctx_limit=200000
if [ -f "$transcript" ]; then
  ctx_tokens=$(jq -r 'select(.message.usage) | (.message.usage.input_tokens // 0) + (.message.usage.cache_read_input_tokens // 0) + (.message.usage.cache_creation_input_tokens // 0)' "$transcript" 2>/dev/null | tail -1)
  if [ -z "$ctx_tokens" ] || [ "$ctx_tokens" = "null" ]; then
    ctx_tokens=0
  fi
  ctx_pct=$(awk -v t="$ctx_tokens" -v l="$ctx_limit" 'BEGIN { printf "%.0f", t * 100 / l }')
fi

# --- Weekly token usage (from ~/.claude/stats-cache.json) ---
week_tokens=0
stats_file="$HOME/.claude/stats-cache.json"
if [ -f "$stats_file" ]; then
  dow=$(TZ=Asia/Tokyo date +%u)  # 1=Mon ... 7=Sun
  week_start=$(TZ=Asia/Tokyo date -v-"$(( dow - 1 ))"d +%Y-%m-%d 2>/dev/null)
  if [ -n "$week_start" ]; then
    week_tokens=$(jq --arg from "$week_start" -r '
      [.dailyModelTokens[] | select(.date >= $from) | .tokensByModel | to_entries[] | .value] | add // 0
    ' "$stats_file" 2>/dev/null)
    [ -z "$week_tokens" ] || [ "$week_tokens" = "null" ] && week_tokens=0
  fi
fi

# --- Usage window reset time (first user message + 5h) ---
# /clear でトランスクリプトが切り替わっても正しいリセット時刻を表示するため
# プロジェクトディレクトリ内の全JSOLファイルから5時間以内の最古メッセージを使う
reset_str=""
if [ -f "$transcript" ]; then
  now_epoch=$(date "+%s")
  window_start_epoch=$(( now_epoch - 18000 ))
  window_start=$(TZ=UTC date -r "$window_start_epoch" "+%Y-%m-%dT%H:%M:%S" 2>/dev/null)
  project_dir=$(dirname "$transcript")
  first_ts=$(find "$project_dir" -maxdepth 1 -name "*.jsonl" -print0 2>/dev/null | \
    xargs -0 jq -r --arg from "$window_start" \
    'select(.type == "user" and ((.isSidechain // false) == false) and ((.timestamp // "") >= $from)) | .timestamp // ""' \
    2>/dev/null | grep -v '^$' | sort | head -1)
  if [ -n "$first_ts" ]; then
    first_epoch=$(TZ=UTC date -jf "%Y-%m-%dT%H:%M:%S" "${first_ts%%.*}" "+%s" 2>/dev/null)
    if [ -n "$first_epoch" ]; then
      reset_epoch=$(( first_epoch + 18000 ))
      if [ "$reset_epoch" -gt "$now_epoch" ]; then
        reset_str=$(TZ=Asia/Tokyo date -r "$reset_epoch" "+%H:%M" 2>/dev/null)
      fi
    fi
  fi
fi

# Color by usage
if [ "$ctx_pct" -lt 50 ]; then
  ctx_color="$GREEN"
elif [ "$ctx_pct" -lt 80 ]; then
  ctx_color="$YELLOW"
else
  ctx_color="$RED"
fi

# --- Git branch ---
git_branch=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
  if [ -n "$branch" ]; then
    git_branch="${MAGENTA} ${branch}${RESET}"
  fi
fi

# --- Format helpers ---
ctx_tokens_fmt=$(awk -v t="$ctx_tokens" 'BEGIN {
  if (t >= 1000) printf "%.1fk", t/1000;
  else printf "%d", t;
}')
cost_fmt=$(awk -v c="$cost_usd" 'BEGIN { printf "%.4f", c }')
week_tokens_fmt=$(awk -v t="$week_tokens" 'BEGIN {
  if (t >= 1000000) printf "%.1fM", t/1000000;
  else if (t >= 1000) printf "%.1fk", t/1000;
  else printf "%d", t;
}')

# --- Build output ---
sep="${DIM} | ${RESET}"
output="${CYAN}●${RESET} ${BOLD}${model}${RESET}"
[ -n "$git_branch" ] && output="${output}${sep}${git_branch}"
output="${output}${sep}${ctx_color}${ctx_pct}% (${ctx_tokens_fmt})${RESET}"
output="${output}${sep}${GREEN}\$${cost_fmt}${RESET}"
if [ "$lines_added" -gt 0 ] || [ "$lines_removed" -gt 0 ]; then
  output="${output}${sep}${GREEN}+${lines_added}${RESET}/${RED}-${lines_removed}${RESET}"
fi
output="${output}${sep}${CYAN}📊 ${week_tokens_fmt}${RESET}"
[ -n "$reset_str" ] && output="${output}${sep}${YELLOW}⏱ ${reset_str}${RESET}"

printf "%b" "$output"
