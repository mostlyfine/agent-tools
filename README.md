# agent-tools

Claude Code / GitHub Copilot CLI を使った AI エージェント開発を効率化するツール集。

## 構成

```
.
├── scripts/
│   ├── agent-ps          # tmux 上のエージェントセッション監視ツール
│   ├── claude-save-log.sh   # Claude Code セッションログ保存フック
│   └── copilot-save-log.sh  # Copilot CLI セッションログ保存フック
├── copilot/
│   └── skills/           # GitHub Copilot CLI 用スキル定義
├── ghc.sh                # Copilot CLI エイリアス・tmux セッション管理
├── hooks.json            # Copilot CLI フック設定
└── .mcp.json             # MCP サーバー設定
```

## ツール詳細

### agent-ps

tmux セッション内で動作中の Claude Code / Copilot CLI プロセスを一覧表示するモニタリングツール。

**機能:**
- 各エージェントの状態（running / idle / waiting_for_input）をリアルタイム表示
- ウォッチモードで一定間隔ごとに自動更新
- エージェントが完了・入力待ちになるとターミナル通知を送信
- キーボード操作で対象 pane へフォーカス移動（`↑↓` / `jk` で選択、`Enter` でフォーカス）

**使い方:**

```bash
# 一覧を表示して終了
scripts/agent-ps

# ウォッチモード（1秒間隔）
scripts/agent-ps -w

# ウォッチモード + 状態変化通知
scripts/agent-ps -w -n

# ウォッチモード（3秒間隔）
scripts/agent-ps -w 3
```

**動作要件:** tmux セッション内から実行する必要があります。

### claude-save-log.sh

Claude Code の `sessionEnd` フックとして使用するログ保存スクリプト。会話内容を Markdown 形式で保存します。

**保存先:** `$CLAUDE_LOG_DIR`（未設定時は `/tmp/claude-logs`）

**ファイル構成:** `{YYYYMMDD}/{HHMMSS}_{session_id}.md`

**フロントマター:**
- 日時、セッション ID、会話の概要
- 作業ディレクトリ、使用モデル
- Write / Edit ツールで変更されたファイル一覧

**Claude Code への設定:**

`.claude/settings.json` に以下を追加:

```json
{
  "hooks": {
    "sessionEnd": [
      {
        "type": "command",
        "bash": "/path/to/scripts/claude-save-log.sh"
      }
    ]
  }
}
```

### copilot-save-log.sh

GitHub Copilot CLI の `sessionEnd` フックとして使用するログ保存スクリプト。

**保存先:** `$COPILOT_LOG_DIR`（未設定時は `/tmp/copilot-logs`）

**フック設定:** `~/.copilot/hooks.json` に以下を追加:

```json
{
  "version": 1,
  "hooks": {
    "sessionEnd": [
      {
        "type": "command",
        "bash": "/path/to/scripts/copilot-save-log.sh",
        "timeoutSec": 30
      }
    ]
  }
}
```

### ghc.sh

Copilot CLI の安全なエイリアスと tmux 開発セッションのセットアップ関数。

**セットアップ:**

```bash
source ghc.sh
```

**提供するコマンド:**

- `ghc` — 許可ツールを限定した Copilot CLI エイリアス  
  - 破壊的な操作（`sudo`, `rm -rf`, `terraform apply` 等）はデフォルトで拒否
- `dev-session [name]` — agent-ps + エディタ + Claude Code の 3 ペイン tmux セッションを起動

```bash
# デフォルト名 "dev-session" で起動
dev-session

# 名前を指定して起動
dev-session my-project
```

**tmux ペイン構成:**

```
┌─────────────────────────┐
│ agent-ps -w -n          │  ← エージェント監視
├─────────────┬───────────┤
│ (作業ペイン) │ claude    │  ← Claude Code
└─────────────┴───────────┘
```

## MCP サーバー設定 (.mcp.json)

| サーバー | 用途 |
|---------|------|
| fetch | URL コンテンツの取得 |
| context7 | ライブラリドキュメントの参照 |
| filesystem | ローカルファイルシステムへのアクセス |

## 必要な環境

- Python 3.11+
- tmux
- [Claude Code](https://github.com/anthropics/claude-code)
- [GitHub Copilot CLI](https://docs.github.com/en/copilot/github-copilot-in-the-cli) (オプション)
- `jq`（ログ保存スクリプトで使用）
