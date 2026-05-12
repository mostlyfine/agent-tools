#!/usr/bin/env bash
# sessionEnd hook: save formatted conversation log to COPILOT_LOG_DIR

set -euo pipefail

INPUT=$(cat)
IFS=$'\t' read -r SESSION_ID TIMESTAMP < <(jq -r '[.sessionId // "", (.timestamp // 0 | tostring)] | @tsv' <<<"$INPUT")
UNIX_SECS=$((TIMESTAMP / 1000))

DEST_DIR="${COPILOT_LOG_DIR:-/tmp/copilot-logs}"
DEST_DIR="${DEST_DIR/#\~/$HOME}"

if [ -z "$SESSION_ID" ]; then
  exit 0
fi

EVENTS_FILE="${HOME}/.copilot/session-state/${SESSION_ID}/events.jsonl"
if [ ! -f "$EVENTS_FILE" ]; then
  exit 0
fi

COMBINED=$(TZ=Asia/Tokyo date -r "$UNIX_SECS" "+%Y%m%d|%H%M%S|%Y-%m-%d %H:%M:%S" 2>/dev/null || TZ=Asia/Tokyo date "+%Y%m%d|%H%M%S|%Y-%m-%d %H:%M:%S")
IFS='|' read -r DATE_DIR TIME_STR DATE_DISPLAY <<<"$COMBINED"

OUT_FILE="${DEST_DIR}/${DATE_DIR}/${TIME_STR}_${SESSION_ID:0:8}.md"
mkdir -p "${OUT_FILE%/*}"

if ! jq -rs \
  --arg date "$DATE_DISPLAY" \
  --arg session_id "$SESSION_ID" \
  '
  (map(select(.type == "session.start")) | first | .data.context.cwd // "") as $cwd |
  (map(select(.type == "session.shutdown")) | first) as $shutdown |
  ($shutdown.data.currentModel // "") as $model |
  ($shutdown.data.codeChanges.filesModified // []) as $changed_files |
  (map(select(.type == "user.message" and (.data.source == null or .data.source == "user")))
    | first | .data.content // "" | split("\n") | first // "") as $first_msg |
  ($first_msg | if length > 200 then .[0:200] + "..." else . end) as $description |

  "---\ndate: \"" + $date + "\"\nsession_id: \"" + $session_id + "\"\ndescription: " + ($description | tojson) + "\ndirectory: \"" + $cwd + "\"\nmodel: \"" + $model + "\"\n" +
  (if ($changed_files | length) > 0 then
    "changed_files:\n" + ($changed_files | map("  - " + .) | join("\n")) + "\n"
  else "changed_files: []\n" end) +
  "---\n\n",

  (.[] |
    if .type == "user.message" and (.data.source == null or .data.source == "user") then
      "## User\n\n" + .data.content + "\n\n---\n"

    elif .type == "assistant.message" and (.data.content // "") != "" and (.agentId == null) then
      "## Copilot\n\n" +
      .data.content + "\n\n---\n"

    else empty
    end
  )
  ' "$EVENTS_FILE" 2>/dev/null \
  | perl -pe 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b[@-Z\\-_]//g' \
  > "$OUT_FILE"; then
    rm -f "$OUT_FILE"
fi
