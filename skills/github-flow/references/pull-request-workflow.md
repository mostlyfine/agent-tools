# プルリクエストワークフロー

gh CLI を使ったプッシュからPR作成、マージ後の後始末まで。

## 目次

- [リモートへプッシュ](#リモートへプッシュ)
- [PRの作成](#prの作成)
- [PR本文の組み立て](#pr本文の組み立て)
- [gh pr create のオプション](#gh-pr-create-のオプション)
- [完了後の対応](#完了後の対応)
- [よくあるエラーと対処](#よくあるエラーと対処)

## リモートへプッシュ

```bash
git push -u origin <branch-name>
```

`-u`（`--set-upstream`）で追跡ブランチを設定すると、以降は `git push` だけで済む。

フォースプッシュが必要な場合（rebase後など）は **必ず** `--force-with-lease` を使う。`--force` はリモートの他者の変更を無条件に上書きするため禁止。

```bash
git push --force-with-lease origin <branch-name>
```

## PRの作成

PRタイトルはコミットメッセージの1行目と同じ形式（Conventional Commits）にする。

- **PRタイトルは英語**（コミットの description と同じ）。日本語にしない。
- **PR本文のセクションタイトルは日本語**で統一し、内容も日本語で記述する。

```bash
gh pr create \
  --title "<type>[scope]: <description in English>" \
  --body "$(cat <<'EOF'
（本文）
EOF
)"
```

## PR本文の組み立て

まず `.github/pull_request_template.md` が存在するか確認する。

```bash
cat .github/pull_request_template.md 2>/dev/null || echo "TEMPLATE_NOT_FOUND"
```

- **テンプレートがある場合**: そのテンプレートの構成・セクション・チェックリストをベースに本文を作成する。プレースホルダーや空欄を実際の内容で埋める。
- **テンプレートがない場合**: `pr-template-default.md`（このディレクトリ内）を読み込んでデフォルトテンプレートとして使用する。

本文はコミット内容と `git diff <base-branch>...HEAD` の差分を分析して各セクションを埋める。テンプレート内のコメント（`<!-- -->`）はそのまま残さず、実際の内容に置き換えること。

## gh pr create のオプション

```bash
--draft          # ドラフトPRとして作成
--reviewer @name # レビュアーを指定
--label "bug"    # ラベルを付ける
--base main      # マージ先ブランチを指定（デフォルトはmain）
--web            # ブラウザで編集画面を開く
```

## 完了後の対応

1. PR URL をユーザーに報告する
2. レビューコメントへの対応は同じブランチで追加コミットして `git push` すれば、PRが自動的に更新される
3. マージ後はブランチを削除する（GitHubのUIで自動削除するか `git branch -d <branch>` で手動削除）

## よくあるエラーと対処

| エラー | 対処 |
|--------|------|
| `main is protected` | ブランチを作成して作業する |
| `pre-commit hook failed` | エラーメッセージを読んで根本原因を修正する。`--no-verify` は使わない |
| `push rejected (non-fast-forward)` | `git pull --rebase` してから再プッシュ |
| `gh: not authenticated` | `gh auth login` でログインする |
| ステージング済みに不要なファイルが混入 | `git restore --staged <file>` で取り消してから整理する |
| 直前のローカルコミットに漏れがあった | `git commit --amend` で修正（リモートにプッシュ済みなら使わない） |
