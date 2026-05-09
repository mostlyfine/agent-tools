#!/usr/bin/env bash
# sessionEnd hook: save formatted conversation log to COPILOT_LOG_DIR

set -euo pipefail

INPUT=$(cat)
IFS=$'\t' read -r TIMESTAMP REASON SESSION_ID < <(jq -r '[.timestamp, .reason, .sessionId // ""] | @tsv' <<<"$INPUT")

[ -n "$SESSION_ID" ] || exit 0

DEST_DIR="${COPILOT_LOG_DIR:-/tmp/copilot-logs}"
DEST_DIR="${DEST_DIR/#\~/$HOME}"

UNIX_SECS=$((TIMESTAMP / 1000))
COMBINED=$(date -r "$UNIX_SECS" "+%Y%m%d|%H%M%S|%Y-%m-%d %H:%M:%S" 2>/dev/null \
           || date "+%Y%m%d|%H%M%S|%Y-%m-%d %H:%M:%S")
IFS='|' read -r DATE_DIR TIME_STR DATE_DISPLAY <<<"$COMBINED"

OUT_FILE="${DEST_DIR}/${DATE_DIR}/${TIME_STR}_${SESSION_ID:0:8}.md"
mkdir -p "${OUT_FILE%/*}"

EVENTS_FILE="${HOME}/.copilot/session-state/${SESSION_ID}/events.jsonl"
jq -rs \
  --arg date "$DATE_DISPLAY" \
  --arg reason "$REASON" \
  '
  (map(select(.type == "session.start")) | first | .data.context.cwd // "") as $cwd |
  (map(select(.type == "tool.execution_complete")) | INDEX(.data.toolCallId)) as $tools |

  "# Copilot Session: \($date)\n\n- **CWD:** \($cwd)\n- **Reason:** \($reason)\n\n---\n",

  (.[] |
    if .type == "user.message" then
      "## User\n\n" + .data.content + "\n\n---\n"

    elif .type == "assistant.message" then
      "## Copilot\n\n" +
      (if (.data.reasoningText // "") != "" then
        "> **Thinking:** " + (.data.reasoningText | gsub("\n"; "\n> ")) + "\n\n"
      else "" end) +
      (if (.data.content // "") != "" then .data.content + "\n\n" else "" end) +
      ([ .data.toolRequests[]? |
          select(.name != "report_intent") |
          . as $req |
          ($tools[$req.toolCallId]) as $result |
          "#### Tool: " + $req.name + "\n\n" +
          "**Args:** `" + (($req.arguments | tojson) | if length > 500 then .[0:500] + "…" else . end) + "`\n\n" +
          (if $result != null then
            (if $result.data.success
             then "**Result (✓):**\n```\n"
             else "**Result (✗):**\n```\n" end) +
            (($result.data.result.content // "") |
              if length > 500 then .[0:500] + "\n*(truncated)*" else . end) +
            "\n```\n\n"
          else "" end)
       ] | join("")) +
      "---\n"

    else empty
    end
  )
  ' "$EVENTS_FILE" > "$OUT_FILE" 2>/dev/null || rm -f "$OUT_FILE"
