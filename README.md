# agent-tools

Claude Code / GitHub Copilot CLI を使った AI エージェント開発を効率化するツール集。

## 構成

```
.
├── .claude/
│   └── settings.json        # Claude Code 設定ファイル（権限・モデル・フック）
├── .github/
│   ├── .mcp.json            # Copilot CLI 用 MCP サーバー設定
│   ├── hooks/
│   │   └── session-end.json # Copilot CLI sessionEnd フック設定
│   └── skills/              # GitHub Copilot CLI 用スキル定義
│       ├── simplify/        # コードレビュー・自動修正スキル
│       └── skill-creator/   # スキル作成・改修支援スキル
├── scripts/
│   ├── .claude/
│   │   └── settings.local.json  # スクリプト開発用 Claude Code 設定
│   ├── agent-ps             # tmux 上のエージェントセッション監視ツール
│   ├── claude-save-log.sh   # Claude Code セッションログ保存フック
│   ├── copilot-save-log.sh  # Copilot CLI セッションログ保存フック
│   └── statusline.sh        # Claude Code ステータスライン
├── tests/
│   ├── bats/                # agent-ps 用 Bats テスト
│   └── python/              # Python テスト
└── ghc.sh                   # Copilot CLI エイリアス・tmux セッション管理
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

**ファイル構成:** `{YYYYMMDD}/{HHMMSS}_{session_id_8文字}.md`

**フロントマター:**
- 日時、セッション ID、会話の概要
- 作業ディレクトリ、使用モデル
- Write / Edit ツールで変更されたファイル一覧

**Claude Code への設定:**

`.claude/settings.json` に以下を追加:

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/scripts/claude-save-log.sh"
          }
        ]
      }
    ]
  }
}
```

### copilot-save-log.sh

GitHub Copilot CLI の `sessionEnd` フックとして使用するログ保存スクリプト。

**保存先:** `$COPILOT_LOG_DIR`（未設定時は `/tmp/copilot-logs`）

**フック設定:** `.github/hooks/session-end.json` を参照。`~/.copilot/hooks/session-end.json` にコピーして使用:

```bash
cp /path/to/.github/hooks/session-end.json ~/.copilot/hooks/session-end.json
```

### statusline.sh

Claude Code のステータスラインに表示するカスタム情報を出力するスクリプト。

**表示内容:**
- 使用モデル名
- Git ブランチ名
- コンテキストウィンドウ使用率（トークン数 / 上限）
- 累計コスト（USD）
- 変更行数（追加 / 削除）

**Claude Code への設定:**

`.claude/settings.json` の `statusLine` に設定済み。パスを実際の場所に合わせて変更してください:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/path/to/scripts/statusline.sh"
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

## Claude Code 設定 (.claude/settings.json)

Claude Code の動作をカスタマイズする設定ファイル。`~/.claude/settings.json` や各プロジェクトの `.claude/settings.json` として配置して使用。

**主な設定内容:**

| 設定 | 内容 |
|------|------|
| `permissions.allow` | 許可するツール・コマンド（git, gh, terraform, npm 等） |
| `permissions.ask` | 実行前に確認を求めるコマンド（commit, apply, rm 等） |
| `permissions.deny` | 常に拒否するコマンド（curl, wget, sudo, rm -rf, git push, terraform apply 等の破壊的操作） |
| `model` | 使用モデル（`claude-sonnet-4-6`） |
| `alwaysThinkingEnabled` | 拡張思考モードの有効化 |
| `statusLine` | カスタムステータスライン（`scripts/statusline.sh`） |
| `hooks.SessionEnd` | セッション終了時のフック（`scripts/claude-save-log.sh`） |

**セットアップ:**

```bash
cp /path/to/.claude/settings.json ~/.claude/settings.json
# または各プロジェクトの .claude/settings.json として配置
```

パス指定箇所（`/path/to/scripts/...`）を実際のパスに変更してください。

## Copilot CLI / ClaudeCodeスキル (skills/)

GitHub Copilot CLI 用のエージェントスキル定義。

### simplify

コード変更を 3 つの観点（再利用性・品質・効率性）で並列レビューし、問題を自動修正するスキル。

**起動トリガー:** 「コードをレビューして」「変更を確認して」「diff をチェックして」

### skill-creator

GitHub Copilot 用スキルを新規作成・改修するためのスキル。要件ヒアリングから SKILL.md 作成・検証まで一貫してサポート。

**起動トリガー:** 「新しいスキルを作りたい」「既存スキルを改善したい」

**スキルのセットアップ:**

```bash
gh skill install mostlyfine/agent-tools simplify
gh skill install mostlyfine/agent-tools skill-creator
```

### その他よく使うスキル
```
gh skill install mattpocock/skills grilling

gh skill update --all
```

## MCP サーバー設定 (.github/.mcp.json)

| サーバー | 用途 |
|---------|------|
| context7 | ライブラリドキュメントの参照 |

### Claude Code へのインストール

```bash
claude mcp add context7 -- npx -y @upstash/context7-mcp
```

**スコープを指定する場合:**

```bash
# ユーザーレベル（全プロジェクトで使用）
claude mcp add -s user context7 -- npx -y @upstash/context7-mcp

# プロジェクトレベル（.mcp.json に保存）
claude mcp add -s project context7 -- npx -y @upstash/context7-mcp
```

**インストール確認:**

```bash
claude mcp list
```

### Copilot CLI へのインストール

```bash
gh copilot -- mcp add context7 -- npx -y @upstash/context7-mcp
```

**インストール確認:**

```bash
gh copilot -- mcp list
```

**または .mcp.json をコピー（ワークスペース設定として使用する場合）:**

```bash
cp /path/to/.github/.mcp.json .mcp.json
```

## 必要な環境

- Python 3.11+
- tmux
- [Claude Code](https://github.com/anthropics/claude-code)
- [GitHub Copilot CLI](https://docs.github.com/en/copilot/github-copilot-in-the-cli) (オプション)
- `jq`（ログ保存スクリプトで使用）

## Loop Engineering
```
/goal CLAUDE.mdのフローに従って、[実装したいタスクやバグの内容] を完了させて。
```

