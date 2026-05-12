#!/usr/bin/env bash
# SessionEnd hook: save formatted conversation log to CLAUDE_LOG_DIR

set -euo pipefail

INPUT=$(cat)
IFS=$'\t' read -r SESSION_ID TRANSCRIPT_PATH < <(jq -r '[.session_id // "", .transcript_path // ""] | @tsv' <<<"$INPUT")

DEST_DIR="${CLAUDE_LOG_DIR:-/tmp/claude-logs}"
DEST_DIR="${DEST_DIR/#\~/$HOME}"

if [ -z "$SESSION_ID" ] || [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

TIMESTAMP=$(jq -rn 'first(inputs | select(.type == "user" and .isSidechain == false) | .timestamp // "") // ""' "$TRANSCRIPT_PATH")

if [ -n "$TIMESTAMP" ]; then
    EPOCH=$(TZ=UTC date -jf "%Y-%m-%dT%H:%M:%S" "${TIMESTAMP%%.*}" "+%s" 2>/dev/null)
    COMBINED=$(TZ=Asia/Tokyo date -r "$EPOCH" "+%Y%m%d|%H%M%S|%Y-%m-%d %H:%M:%S" 2>/dev/null || TZ=Asia/Tokyo date "+%Y%m%d|%H%M%S|%Y-%m-%d %H:%M:%S")
else
    COMBINED=$(TZ=Asia/Tokyo date "+%Y%m%d|%H%M%S|%Y-%m-%d %H:%M:%S")
fi
IFS='|' read -r DATE_DIR TIME_STR DATE_DISPLAY <<<"$COMBINED"

OUT_FILE="${DEST_DIR}/${DATE_DIR}/${TIME_STR}_${SESSION_ID:0:8}.md"
mkdir -p "${OUT_FILE%/*}"

if ! jq -rs \
  --arg date "$DATE_DISPLAY" \
  --arg session_id "$SESSION_ID" \
  '
  def extract_text:
    if type == "array" then map(select(.type == "text") | .text) | join("\n")
    else . // "" end;

  (map(select(.type == "user" and .isSidechain == false)) | first) as $first_user |
  ($first_user | .cwd // "") as $cwd |
  (map(select(.type == "assistant" and .isSidechain == false and (.message.model // "") != "")) | first | .message.model // "") as $model |
  ($first_user | .message.content |
    if type == "array" then map(select(.type == "text") | .text) | join("") else . // "" end |
    split("\n") | first // "" |
    if length > 200 then .[0:200] + "..." else . end) as $description |
  ([.[] | select(.type == "assistant" and .isSidechain == false) |
    .message.content // [] | .[] |
    select(.type == "tool_use" and (.name == "Write" or .name == "Edit")) |
    .input.file_path] | unique) as $changed_files |

  "---\ndate: \"" + $date + "\"\nsession_id: \"" + $session_id + "\"\ndescription: " + ($description | tojson) + "\ndirectory: \"" + $cwd + "\"\nmodel: \"" + $model + "\"\n" +
  (if ($changed_files | length) > 0 then
    "changed_files:\n" + ($changed_files | map("  - " + .) | join("\n")) + "\n"
  else "changed_files: []\n" end) +
  "---\n\n",

  (.[] |
    if .type == "user" and .isSidechain == false and (.isMeta // false) == false and (.message.role // "") == "user" then
      (.message.content | if type == "array" and any(.[]; .type == "tool_result") then null
       elif type == "array" then map(select(.type == "text") | .text) | join("\n")
       elif type == "string" then .
       else null end) as $text |
      if $text == null or $text == "" then empty
      else "## User\n\n" + $text + "\n\n---\n" end
    elif .type == "assistant" and .isSidechain == false and (.message.role // "") == "assistant" then
      (.message.content | extract_text) as $text |
      if $text == "" then empty
      else "## Claude\n\n" + $text + "\n\n---\n" end
    else empty
    end
  )
  ' "$TRANSCRIPT_PATH" 2>/dev/null \
  | perl -pe 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b[@-Z\\-_]//g' \
  > "$OUT_FILE"; then
    rm -f "$OUT_FILE"
fi
