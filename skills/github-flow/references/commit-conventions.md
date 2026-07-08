# コミット規約（Conventional Commits）

コミットメッセージの形式・ルールと、ハンク単位ステージングの詳細手順。
ワークフロー本体（範囲決定・計画・ループ）は SKILL.md の Step 2〜4 が正。

## 目次

- [形式](#形式)
- [タイプ一覧](#タイプ一覧)
- [ルール](#ルール)
- [破壊的変更（BREAKING CHANGE）](#破壊的変更breaking-change)
- [メッセージ例](#メッセージ例)
- [フッターの例](#フッターの例)
- [ハンク単位ステージング](#ハンク単位ステージング)

## 形式

```
<type>(<scope>): <description>

[body]

[footer]
```

## タイプ一覧

| type | 用途 | SemVer影響 |
|------|------|-----------|
| `feat` | 新機能追加 | MINOR |
| `fix` | バグ修正 | PATCH |
| `docs` | ドキュメントのみ変更 | なし |
| `style` | 動作に影響しない整形 | なし |
| `refactor` | リファクタリング | なし |
| `perf` | パフォーマンス改善 | PATCH |
| `test` | テストの追加・修正 | なし |
| `build` | ビルドシステム・依存関係 | なし |
| `ci` | CI設定の変更 | なし |
| `chore` | その他（雑務） | なし |
| `revert` | コミットの取り消し | - |

## ルール

### Subject（1行目）

- **subject は WHY を表す** — 何を変えたかではなく、変更の背景・理由を書く
  - ❌ Bad: `fix(auth): fix null pointer error`
  - ✅ Good: `fix(auth): prevent crash when session expires without refresh`
- 英語の命令形（imperative mood）・小文字始まり・末尾にピリオドなし・最大72文字
- `scope` は影響するモジュール／エリア（不明なら省略）

### Body（任意・subjectだけで不十分なときに追加）

- subject とは1行空けて区切る
- 箇条書き（`-`）を使い、論理的な理由ごとに1項目
- 各項目は WHAT ではなく **WHY** に答える — diff が示す内容の繰り返しは避ける
- 日本語可

例:

```
refactor(recommendation): move task DAGs into recommendation/ subdirectory

- recommendation_daily/hourly now invokes dbt_run and dump_gcs as separate
  steps, making the monolithic dbt_run_and_dump_gcs DAG redundant
- move surviving task DAGs under recommendation/ for clearer namespacing
- remove obsolete trigger_dump_gcs test DAG
```

## 破壊的変更（BREAKING CHANGE）

後方互換性を壊す変更は SemVer の MAJOR に対応する。2通りの表記がある。

**型に `!` を付ける:**

```
feat(api)!: migrate users endpoint from v1 to v2
```

**フッターに `BREAKING CHANGE:` を書く:**

```
feat!: remove legacy API endpoints

BREAKING CHANGE: The /v1/users endpoint has been removed. Use /v2/users instead.
```

両方併記すると、`!` で機械的に検出可能にしつつ詳細を補足できる（推奨）。

## メッセージ例

```
feat(auth): add JWT-based authentication

JWTによるトークンリフレッシュフローとセキュアなCookie処理を実装。
セッション固定攻撃対策のため、ログイン時にトークンを再生成する。
Closes #42
```

```
fix: prevent crash when session expires without refresh

リフレッシュトークンが無い状態でのセッション切れ時にnull参照で
クラッシュしていた。期限切れを検知して再ログインへ誘導する。
Refs: #78
```

## フッターの例

```
Closes #42                    # Issueをクローズ
Refs: #78                     # Issue参照（クローズしない）
Reviewed-by: @username        # レビュー者
Co-authored-by: Name <email>  # 共同作業者
```

## ハンク単位ステージング

1ファイル内に複数の論理単位が混在する場合のみ使う（通常はファイル単位の `git add <file>` で足りる）。
`git apply --cached` を使えばユーザー操作なしでハンクを選択的にステージングできる。

1. 対象ファイルの diff 全体を取得する:

   ```bash
   git diff <file>
   ```

2. このコミット単位に属するハンクだけを抽出し、パッチテキストを構成する（diff ヘッダー `diff --git ...` / `--- ` / `+++ ` 行は残し、不要なハンクを取り除く）
3. パッチを一時ファイルに書き出し、インデックスに適用する:

   ```bash
   git apply --cached <patch-file>
   ```

4. `git diff --staged` で意図したハンクだけがステージされたことを確認する

ハンク選択はエージェントが行う。`git add -p` のような対話操作は不要。
