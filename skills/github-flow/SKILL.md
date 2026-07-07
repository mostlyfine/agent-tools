---
name: github-flow
description: >
  GitHub Flowに従ってworktree作成・コミット・プッシュ・プルリクエスト作成を行う。
  「コミットして」「PRを作って」「ブランチ切ってPR」「git addからPR作成まで全部」
  「変更をまとめてPR」「実装が終わった、コミットして」など作業完了時の表現に加え、
  「作業を開始して」「ブランチ切って作業して」「worktreeで作業して」「実装を始めよう」
  など作業開始時の依頼でも必ずこのスキルを使う。worktreeによる作業分離・ブランチ戦略・
  Conventional Commits・選択的ステージング・gh CLIでのPR作成をカバーする。
  次の用途には使わない: git stash、rebase、diff/log閲覧、コンフリクト解決、
  CI/テスト失敗の調査、ブランチ削除（新しい変更を保存しない操作）。
compatibility: "Requires: git, gh CLI (GitHub CLI)"
---

# GitHub Flow スキル

GitHub Flow + Conventional Commits に従い、コミットからPR作成までを完結させる。

## ワークフロー全体像

```
[worktree 準備] → [コミット範囲の決定] → ┌──────────────────────────────┐
                                        │ 論理単位ごとにコミット（ループ）│ → [プッシュ] → [PR作成]
                                        │  作業ツリーがクリーンになるまで │
                                        └──────────────────────────────┘
```

コミットは「意味のある論理単位」ごとに分け、作業ツリーがクリーンになるまで繰り返す。
各ステップの詳細は下記のリファレンスを必要に応じて読み込む。

## リファレンス

| リファレンス | 読むタイミング |
|------------|--------------|
| `references/branching-strategies.md` | ブランチを作成する／命名規則を確認する／GitHub Flowの原則 |
| `references/worktree-workflow.md` | worktreeの作成／既存変更の移送／マージ後の後始末／worktree関連のエラー対処 |
| `references/commit-conventions.md` | コミットメッセージを書く／タイプ・スコープ・BREAKING CHANGE／ステージングの作法 |
| `references/pull-request-workflow.md` | プッシュ／PR作成／PR本文の組み立て／マージ後の後始末／エラー対処 |
| `references/pr-template-default.md` | `.github/pull_request_template.md` が無い場合のPR本文テンプレート |

## Step 1: worktree 準備

```bash
git branch --show-current
git status --short
git rev-parse --git-dir --git-common-dir   # 2行の出力が異なれば worktree 内
```

現在の状態に応じて分岐する:

| 状態 | 対応 |
|------|------|
| 既に worktree 内、または feature ブランチ上 | そのまま Step 2 へ（二重に worktree 化しない） |
| main/master 上・クリーン | worktree を作成して移動 |
| main/master 上・変更あり | stash で変更を worktree に移送 |

**main / master 上で直接作業・コミットしない。作業は必ず `.worktrees/<branch-dir>` 内で行う。**

```bash
git check-ignore -q .worktrees || echo '.worktrees/' >> "$(git rev-parse --git-common-dir)/info/exclude"
git worktree add .worktrees/<branch-dir> -b feature/my-feature   # <branch-dir> は / を - に置換
cd .worktrees/<branch-dir>
```

ブランチ命名規則は `references/branching-strategies.md`、変更の移送手順とエラー対処は
`references/worktree-workflow.md` を参照。**以降の Step 2〜6 はすべて worktree 内で実行する。**

## Step 2: コミット範囲の決定

まずステージング状態を確認し、コミット範囲を決める。

```bash
git diff --cached --stat   # ステージング済みの変更概要
git status                 # Staged/Unstaged/Untracked を確認
```

- **ステージング済みの変更がある** → それがコミット範囲。未ステージング・未追跡は無視して **Step 4（コミット）** へ。ユーザーは `git add` 済みの内容で意図を示している。
- **何もステージングされていない** → 未ステージング＋未追跡すべてを候補として **Step 3（ループ）** へ。

会話のコンテキストから変更の背景（intent）を把握する。詳細な判断基準は `references/commit-conventions.md`（Phase A）を参照。

> コミットメッセージは範囲内の**すべての変更**をカバーする。自分が触った分だけでなく無関係な変更も簡潔に言及する。

## Step 3: 論理単位ごとにコミット（作業ツリーがクリーンになるまでループ）

`git status` がクリーンになるまで以下を繰り返す。

1. **未追跡ファイル**があれば `AskUserQuestion` でコミットに含めるか確認する（初回のみ）
2. `git diff HEAD` を分析し、変更を**論理単位（単一責任）**にグルーピングする。提案メッセージとともに計画を提示して確認を待つ
3. 次の単位をステージングする
   - ファイル単位: `git add <file1> <file2>` / 削除は `git rm <file>`
   - ハンク単位: `git apply --cached <patch-file>` でハンクを自動ステージング（ユーザー操作不要）
4. **Step 4** でコミット → 変更が残っていれば 2 へ戻る

`git add .` / `git add -A` は非推奨。`.env`・認証情報・秘密鍵はステージングしない。
手順の詳細は `references/commit-conventions.md`（Phase B）を参照。

## Step 4: コミット

`git diff --staged` で意図した変更だけがステージされていることを検証してからコミットする。

Conventional Commits 形式（`<type>(<scope>): <description>`）。詳細は `references/commit-conventions.md`（Phase C）。

- **subject は WHY（背景・理由）を表す**。英語の命令形・小文字始まり・最大72文字
  - ❌ `fix(auth): fix null pointer error`
  - ✅ `fix(auth): prevent crash when session expires without refresh`
- `body` は subject だけで不十分なとき、WHY を箇条書きで（日本語可）

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <why-description>

[body - 省略可]
EOF
)"
```

コミット後にメッセージ修正を依頼されたら `git commit --amend`（未プッシュのみ）。
コミット前にフックの有無を確認しておくとエラー時に原因を特定しやすい:

```bash
ls lefthook.yml .lefthook.yml captainhook.json .husky/pre-commit .pre-commit-config.yaml 2>/dev/null
```

## Step 5: プッシュ

```bash
git push -u origin <branch-name>
```

フォースプッシュは `--force-with-lease` のみ使用（`--force` は禁止）。詳細は `references/pull-request-workflow.md`。

## Step 6: プルリクエスト作成

PRタイトルは英語のConventional Commits形式、PR本文は日本語。
`.github/pull_request_template.md` があればそれを、無ければ `references/pr-template-default.md` を使う。
手順とオプションの詳細は `references/pull-request-workflow.md` を参照。

```bash
gh pr create --title "<type>[scope]: <description in English>" --body "<日本語の本文>"
```

## 完了後

PR URL をユーザーに報告する。レビュー対応は同じブランチ（worktree 内）へ追加コミットして `git push`。
マージ後はメインの checkout に戻り、worktree とブランチを削除する:

```bash
git worktree remove .worktrees/<branch-dir>
git branch -d <branch>
```

トラブル時は `references/pull-request-workflow.md` と `references/worktree-workflow.md` のエラー表を参照。
