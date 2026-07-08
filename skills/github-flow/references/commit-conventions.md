# コミット規約（Conventional Commits）

意味のある論理単位ごとに、Conventional Commits 形式（コミットメッセージは英語）でコミットする。コミットすべき変更がなくなるまで繰り返す。

## 目次

- [コミットワークフロー](#コミットワークフロー)
  - [Phase A: コミット範囲の決定](#phase-a-コミット範囲の決定)
  - [Phase B: コミットすべき変更がなくなるまでループ](#phase-b-コミットすべき変更がなくなるまでループ)
  - [Phase C: コミットメッセージの生成と実行](#phase-c-コミットメッセージの生成と実行)
- [形式](#形式)
- [タイプ一覧](#タイプ一覧)
- [ルール](#ルール)
- [破壊的変更（BREAKING CHANGE）](#破壊的変更breaking-change)
- [メッセージ例](#メッセージ例)
- [フッターの例](#フッターの例)

---

## コミットワークフロー

### Phase A: コミット範囲の決定

**A-1. ステージング状態を確認する**

```bash
git diff --cached --stat
```

- **ステージング済みの変更がある場合** → それがコミット範囲。未ステージング・未追跡ファイルは一切無視する。ユーザーは `git add` 済みの内容で意図を示している。**Phase C へ進む**。
- **何もステージングされていない場合** → 未ステージングの変更と未追跡ファイルすべてを候補とする。**Phase B へ進む**。

**A-2. セッションコンテキストを把握する**

現在の会話を見て、変更の背景（intent）を識別する:
- このセッションで行った／議論した／観測した変更（intent の文脈を持つ）
- このセッションと無関係な変更（過去のセッション、他エージェント、手動編集）

**A-3. メッセージの根拠を決める**
- セッションコンテキストから変更理由が明確 → その文脈をコミットメッセージに使う
- 不明（会話の文脈がない） → diff が示す事実のみを記述する

> **ルール**: コミットメッセージは範囲内の**すべての変更**をカバーすること。自分が触った変更だけを書くのではなく、無関係な変更も簡潔に言及する。無視するより言及するほうが良い。

---

### Phase B: コミットすべき変更がなくなるまでループ

コミットに含めるべき変更（未ステージングの変更・取り込むべき未追跡ファイル）が `git status` に残らなくなるまで、以下を繰り返す。

**B-1. 未追跡ファイルの扱い（初回のみ）**

```bash
git status
```

未追跡ファイルは次の基準で振り分ける:

- **明らかな生成物**（`__pycache__/`・`dist/`・`node_modules/` などのビルド成果物・キャッシュ。作業中のテスト実行で生まれたものも含む）→ 確認不要。コミットせず ignore に登録して `git status` から消す:

  ```bash
  echo '<pattern>' >> "$(git rev-parse --git-common-dir)/info/exclude"
  ```

- **今回の変更が参照・前提とする新規ファイル**（例: 変更後の README が参照する docs）→ コミットに含める
- **どちらとも判断できないもの** → `AskUserQuestion` でコミットに含めるか確認し、明示的に確認が取れたファイルのみ含める

**ユーザーに確認できない環境**（サブエージェントとしての実行・自動実行など）では確認をスキップし、上記の基準で自律的に判断する。判断できなかったファイルはコミットに含めず、スキップした確認と判断の理由を最終報告に記録する。

**B-2. コミット単位を計画する**

```bash
git diff HEAD
```

変更を論理単位にグルーピングする。各単位は1つの一貫した変更（単一責任）を表すこと。**Conventional Commits の type が異なる変更は別コミットに分ける**のが基準（例: 実装＋その検証テスト = `feat` の1コミット、README・ドキュメント追加 = `docs` の別コミット。実装とそれを検証するテストは一体なので分割しない）。提案するConventional Commitメッセージとともに計画を提示し、確認を待ってから進む（確認できない環境では B-1 のフォールバックと同様に自律判断して進む）。

**B-3. 次のコミット単位をステージングする（自動化）**

- **ファイル単位**: `git add <file1> <file2> ...`
- **特定のハンクのみ**: `git apply --cached` でハンクを自動ステージングする:
  1. 全体の diff を取得: `git diff <file>`
  2. このコミット単位に属するハンクだけを抽出してパッチテキストを構成する
  3. インデックスに適用: 一時ファイルに書き出して `git apply --cached <patch-file>`

  ユーザー操作は不要。ハンク選択はエージェントが行う。

Phase C に進み、変更が残っていればここへ戻る。

---

### Phase C: コミットメッセージの生成と実行

**C-1. ステージ内容を検証する**

```bash
git diff --staged
```

意図した変更だけがステージされていることを確認する。

**C-2. コミットメッセージを書く**

形式・タイプ・ルールは下記セクション参照。特に **subject は WHY（背景・理由）を表す**こと。

**C-3. コミットする**

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <why-description>

[body - 省略可]
EOF
)"
```

**C-3b. ユーザーがメッセージ修正を求めた場合**

コミット後にメッセージ変更を依頼されたら `git commit --amend -m "..."` を使う（**未プッシュのコミットのみ**）。同じ subject/body ルールを適用する。

**C-4. 残りの変更を確認する（Phase B ループ）**

```bash
git status
git diff HEAD
```

変更が残っていれば B-2 へ戻る。

---

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
