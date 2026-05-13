---
name: create-pr
description: >
  Create a pull request from the current (or specified) branch. Use this skill whenever
  the user wants to open a PR, submit a pull request, create a PR, or push changes for
  review — even if they just say "PRを作って", "プルリク出して", "レビュー依頼したい", or "submit my
  changes". Also trigger when the user mentions a branch name alongside a request that
  implies review (e.g., "feat/xxx のPRを出して"). This skill handles the full workflow:
  uncommitted changes → commit → push → fill template → Conventional Commit title →
  confirm preview → create PR.
---

# create-pr skill

## 目標

最小限の手間でプルリクエストを作成する。以下の規約に従うこと：
- **タイトル**: Conventional Commit 形式（`type(scope): description`）
- **本文**: リポジトリの PR テンプレートを git 履歴を元に埋める
- **フロー**: 状態検出 → 未コミット変更の処理 → push → プレビュー → 作成

---

## ステップ 1: 対象ブランチの確認

ユーザーがブランチ名を指定した場合はそのブランチに切り替え（または `--head` で指定）する。
それ以外は現在のブランチを使用する：

```bash
git branch --show-current
```

**ベースブランチ**（PRのマージ先）を特定する — 通常は `main` または `dev`：

```bash
git remote show origin | grep 'HEAD branch'
# または一般的なブランチ名を確認: main, dev, master
```

---

## ステップ 2: 未コミットの変更を処理する

```bash
git status --short
```

未コミット（または未追跡）の変更がある場合、**ユーザーに確認する**：

> "以下の未コミットの変更があります：\n[ファイル一覧]\n\nコミットして続けますか？それともこのままPRを作成しますか？"

提示する選択肢：
- **コミットしてPRを作成** → 以下のコミットフローへ
- **このまま作成（変更は含まれない）** → ステップ 3 へスキップ
- **キャンセル** → 中断

### コミットフロー

ユーザーがコミットに同意した場合、変更ファイルをもとに Conventional Commit メッセージを生成し、実行前に確認を取る：

```bash
git add -A
git commit -m "<生成したメッセージ>"
```

**Conventional Commit 形式：**

```
type(scope): description

# Type: feat | fix | docs | style | refactor | perf | test | build | ci | chore | revert
# Scope: (optional) 変更ファイルのパスから推測（例: env/prod/main → prod, env/dev → dev）
# Description: 日本語で短い説明・命令形・末尾句点なし・全体で72文字以内
```

例：
- `chore(prod): store_tfstate モジュールのソース URL を更新`
- `feat(composer): Airflow のシークレットバックエンドに Cloud Secret Manager を設定`
- `fix(dev): BigQuery データセットのリソース参照を修正`

---

## ステップ 3: ブランチをリモートに push する

```bash
git status -sb
```

上流トラッキングがない、またはブランチが origin より先行している場合は push する：

```bash
git push -u origin <ブランチ名>
```

---

## ステップ 4: PR コンテンツ用のコンテキストを収集する

このブランチにあってベースブランチにないコミットを収集する：

```bash
git log --oneline origin/<base>..HEAD
git diff --stat origin/<base>..HEAD
```

意図を把握するためにコミットメッセージ全文も確認する：

```bash
git log --format="%s%n%b" origin/<base>..HEAD
```

---

## ステップ 5: PR テンプレートを読み込む

以下の順でテンプレートを探す：
1. `.github/pull_request_template.md`
2. `.github/PULL_REQUEST_TEMPLATE.md`
3. `docs/pull_request_template.md`

見つからない場合は以下のテンプレートを使用する：
```markdown
## 概要
<!-- base branchとのgit diffの差分を分析、どのような変更を行っているか、その核心を捉えて一文でわかりやすく簡潔に記述してください。-->

## 詳細
<!--
base branchとのgit diffの差分を詳細に分析し、この変更がどういった背景で(Why)、どんな問題を解決するために必要なのか(What/Problem)、どのように解決するのか(How)を推測し、箇条書きで構造化して説明してください。
その変更の必要性が読者にすんなり伝わるように、また、その目的が達成できる限り記述量は最小限にしてください。
-->

## 影響の内容・範囲
<!--
base branchとのgit diffの差分を分析し、どの環境（例: dev, sb, prod）の、何に対する変更なのかを1行で記述してください。
環境は変更差分のファイルパスや変更内容から推測してください。
-->

## 動作確認
<!--
base branchとのgit diffの差分と「影響の内容・範囲」を考慮し、
この変更を安全にリリースするために担保されているべきだと思われる確認項目をチェックボックス形式（`- [ ]`）で箇条書きで記述してください。
例:
- [ ] ローカル環境で該当箇所が意図通り動作することを確認（具体的な確認手順も追記推奨）
- [ ] （もしあれば）関連するユニットテストが全て成功することを確認
-->

```

---

## ステップ 6: PR タイトルと本文を生成する

### タイトル（Conventional Commit）

ブランチ名とコミット履歴から単一のタイトルを生成する：
- Type: コミットから推測（feat > fix > refactor > chore の優先順）
- Scope: (オプション) 変更ディレクトリまたはコミットメッセージの明示的なスコープから推測
- Description: **日本語**で変更内容を端的に要約

同じ type のコミットが複数ある場合はまとめて要約する。

### 本文

ステップ 4 で収集した内容をもとに PR テンプレートの各セクションを埋める。
オプション項目は持っている情報で埋められるもののみ埋める。
空白のセクションがあればセクションごと削除する。

**テンプレート記入ガイド：**

| セクション | 記入方法 |
|---|---|
| issueリンク | ブランチ名から検索（例: `fix/123-...` → `#123`）または削除 |
| なぜやったのか | コミット本文またはブランチ名のコンテキストから記載；具体的な内容がなければ省略 |
| やったこと | git diff の統計とコミットメッセージをもとに具体的な変更内容を列挙 |
| やらなかったこと | コミットメッセージから推測できなければ削除 |
| 特にみてほしい観点 | コミットメッセージに不確実性が示されていなければ削除 |
| 動作確認方法 | Terraform リポジトリ: `tf plan` / `tf apply` を記載；それ以外はファイル種別から推測 |
| その他・特記事項 | コミットに特筆すべき内容がなければ削除 |

記述内容がないセクションはセクションごと削除。

---

## ステップ 7: プレビューを表示して確認する

生成したタイトルと本文をユーザーに分かりやすく表示する：

```
─────────────────────────────────────
📋 PRプレビュー
─────────────────────────────────────
タイトル: feat(prod): モジュールのソース URL を github.com 形式に移行

本文:
## 概要
env/prod/main 配下の全モジュールの source URLをgithub.dena.jp から github.com 形式に変更

...
─────────────────────────────────────
```

その後、確認を取る：

> "このPRを作成してよいですか？タイトルや本文を修正したい場合は教えてください。"

修正を依頼された場合は変更を適用し、再度プレビューを表示してから進める。

---

## ステップ 8: PR を作成する

確認後：

```bash
gh pr create \
  --title "<タイトル>" \
  --body "<本文>" \
  --base <ベースブランチ>
```

成功したら PR の URL と簡単なサマリーを表示する。

---

## エラー処理

| 状況 | 対応 |
|---|---|
| git リポジトリでない | その旨を伝えて中断する |
| `gh` が未認証 | `gh auth status` を実行してユーザーをガイドする |
| ブランチにすでにオープンな PR がある | 既存の PR の URL を表示し、代わりに更新するか確認する |
| push が拒否された（例: 保護ブランチ） | エラーを分かりやすく説明する |
