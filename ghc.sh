#!/usr/bin/env bash
# 使い方: source scripts/ghc.sh

alias ghc="copilot \
  --allow-tool='write' \
  --allow-tool='read' \
  --allow-tool='grep' \
  --allow-tool='glob' \
  --allow-tool='web_fetch' \
  --allow-tool='web_search' \
  --allow-tool='shell(git show)' \
  --allow-tool='shell(git log)' \
  --allow-tool='shell(git status)' \
  --allow-tool='shell(git diff)' \
  --allow-tool='shell(git branch)' \
  --allow-tool='shell(git --no-pager:*)' \
  --allow-tool='shell(uv add)' \
  --allow-tool='shell(uv sync)' \
  --allow-tool='shell(npm run build)' \
  --allow-tool='shell(npm run lint)' \
  --allow-tool='shell(npm run test:*)' \
  --allow-tool='shell(terraform plan:*)' \
  --allow-tool='shell(terraform init:*)' \
  --allow-tool='shell(terraform fmt:*)' \
  --allow-tool='shell(terraform validate:*)' \
  --allow-tool='shell(terraform state:*)' \
  --allow-tool='shell(echo)' \
  --allow-tool='shell(grep)' \
  --allow-tool='shell(find)' \
  --allow-tool='shell(ls)' \
  --allow-tool='shell(cat)' \
  --allow-tool='shell(head)' \
  --allow-tool='shell(tail)' \
  --allow-tool='shell(sed)' \
  --allow-tool='shell(awk)' \
  --allow-tool='shell(sort)' \
  --allow-tool='shell(uniq)' \
  --allow-tool='shell(wc)' \
  --allow-tool='shell(jq)' \
  --allow-tool='shell(rg)' \
  --allow-tool='shell(fd)' \
  --deny-tool='shell(sudo:*)' \
  --deny-tool='shell(rm -rf:*)' \
  --deny-tool='shell(dbt run)' \
  --deny-tool='shell(uv run dbt run:*)' \
  --deny-tool='shell(terraform apply:*)' \
  --deny-tool='shell(terraform destroy:*)' \
  --deny-tool='shell(terraform force-unlock:*)' \
  --deny-tool='shell(terraform state rm:*)' \
"

function dev-session() {
  local SESSION_NAME=${1:-"dev-session"} WINDOW_INDEX=0 PANE_COUNT

  if [ -n "$TMUX" ]; then
    read -r SESSION_NAME WINDOW_INDEX PANE_COUNT < <(tmux display-message -p '#{session_name} #{window_index} #{window_panes}')
  else
    tmux new-session -d -s "$SESSION_NAME" 2>/dev/null || true
    PANE_COUNT=$(tmux display-message -p -t "$SESSION_NAME:0" '#{window_panes}')
  fi

  local TARGET="$SESSION_NAME:$WINDOW_INDEX"

  if [ "$PANE_COUNT" -eq 1 ]; then
    tmux split-window -v -t "$TARGET.0" -p 80
    tmux split-window -h -t "$TARGET.1" -p 50
    tmux send-keys -t "$TARGET.0" "scripts/agent-ps -w -n" Enter
    tmux send-keys -t "$TARGET.1" "claude" Enter
    tmux select-pane -t "$TARGET.0"
  fi

  [ -z "$TMUX" ] && tmux attach-session -t "$SESSION_NAME"
}

