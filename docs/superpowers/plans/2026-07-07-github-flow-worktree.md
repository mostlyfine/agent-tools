# github-flow worktree 統合 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** github-flow スキルの Step 1 を worktree ベースに置き換え、作業開始から PR 作成までを `.worktrees/<branch-dir>` 内で完結させる。

**Architecture:** SKILL.md は手順の骨子のみを持ち、worktree の作成・移送・後始末・エラー対処の詳細は新設の `references/worktree-workflow.md` に分離する（既存リファレンス構造と同じパターン）。

**Tech Stack:** Markdown（スキル定義）、git worktree / git stash。自動テストは無いため、scratch リポジトリでのコマンド列実行を検証とする。

**Spec:** `docs/superpowers/specs/2026-07-07-github-flow-worktree-design.md`

## Global Constraints

- 作業はすべて worktree `.worktrees/feature-github-flow-worktree/` 内で行う（ファイルパスはすべてこの worktree からの相対パス）
- 配置規約: worktree は `.worktrees/<branch-dir>`、`<branch-dir>` はブランチ名の `/` を `-` に置換したもの
- **設計書からの変更点（1件）:** ignore 登録は `.gitignore` への直接コミットではなく `.git/info/exclude` への追記を第一手段とする。理由: (1) main に直接コミットせずに済む、(2) 即時有効なので `git stash push -u` が `.worktrees/` を巻き込む事故を防げる。リポジトリで恒久化したい場合のみ `.gitignore` 追記を worktree 内でコミットして PR に含める
- コミットメッセージは Conventional Commits（subject は英語・WHY 重視・72文字以内）

---

### Task 1: `references/worktree-workflow.md` の新設

**Files:**
- Create: `skills/github-flow/references/worktree-workflow.md`

**Interfaces:**
- Produces: SKILL.md（Task 2）が参照するリファレンスファイル。ファイル名 `worktree-workflow.md` とセクション名「状態判定」「worktree の作成」「既存変更の移送」「マージ後の後始末」「エラー対処」を Task 2 の記述が前提にする。

- [ ] **Step 1: ファイルを以下の内容で作成する**

````markdown
# worktree ワークフロー

作業開始前に `git worktree` で独立した作業ディレクトリを作り、その中で実装からPR作成までを完結させる。メインの checkout は常に main のまま保つ。

## 目次

- [基本方針](#基本方針)
- [状態判定](#状態判定)
- [worktree の作成](#worktree-の作成)
- [既存変更の移送](#既存変更の移送)
- [マージ後の後始末](#マージ後の後始末)
- [エラー対処](#エラー対処)

## 基本方針

- 配置場所はリポジトリ内 `.worktrees/<branch-dir>`。`<branch-dir>` はブランチ名の `/` を `-` に置換したもの（例: ブランチ `feature/add-auth` → `.worktrees/feature-add-auth/`）
- worktree 作成より**前に** `.worktrees/` を ignore 登録する（後述）。登録漏れがあると `git stash push -u` が worktree ディレクトリを巻き込む
- メインの checkout では作業しない。実装・コミット・プッシュ・PR作成はすべて worktree 内で行う

## 状態判定

```bash
git branch --show-current                 # 現在のブランチ
git status --short                        # 変更の有無
git rev-parse --git-dir --git-common-dir  # 2行の出力が異なれば worktree 内
```

| 状態 | 対応 |
|------|------|
| 既に worktree 内、または feature ブランチ上 | 何もしない。そのまま作業を続行（二重に worktree 化しない） |
| main/master 上・クリーン | [worktree の作成](#worktree-の作成) へ |
| main/master 上・変更あり | [既存変更の移送](#既存変更の移送) へ |

## worktree の作成

事前に `.worktrees/` が ignore されているか確認し、されていなければ `.git/info/exclude` に追記する（コミット不要・即時有効）:

```bash
git check-ignore -q .worktrees || echo '.worktrees/' >> "$(git rev-parse --git-common-dir)/info/exclude"
```

リポジトリとして恒久化したい場合は、`.gitignore` への追記を worktree 内でコミットして PR に含める（main に直接コミットしない）。

ブランチ名を決めて（命名規則は `branching-strategies.md`）worktree を作成し、移動する:

```bash
git worktree add .worktrees/<branch-dir> -b <branch>
cd .worktrees/<branch-dir>
```

## 既存変更の移送

main 上に未コミットの変更がある状態で呼ばれた場合は、stash 経由で worktree に移送する:

```bash
git check-ignore -q .worktrees || echo '.worktrees/' >> "$(git rev-parse --git-common-dir)/info/exclude"
git stash push -u -m "github-flow: move to worktree"
git worktree add .worktrees/<branch-dir> -b <branch>
cd .worktrees/<branch-dir>
git stash pop
```

`git stash pop` が成功すれば移送完了。メインの checkout はクリーンな main に戻っている。

## マージ後の後始末

PR がマージされたら、メインの checkout に戻って worktree とブランチを削除する:

```bash
cd "$(git worktree list | head -1 | awk '{print $1}')"   # メインの checkout へ戻る
git worktree remove .worktrees/<branch-dir>
git branch -d <branch>
git pull origin main
```

worktree に未コミットの変更が残っていると `git worktree remove` は失敗する（安全装置）。中身を確認してから対処する。

## エラー対処

| 症状 | 原因 | 対処 |
|------|------|------|
| `git stash pop` でコンフリクト | stash の基点と worktree の基点がずれている | **stash は消えていない**。自動解決を試みず、作業を止めてユーザーに報告し指示を仰ぐ |
| `worktree add` が `already exists` | 同じパスの worktree が既に存在する | 新規作成せず `cd` してその worktree を再利用する |
| `worktree add` が `already checked out` | 同名ブランチが別の worktree でチェックアウト済み | `git worktree list` で場所を特定し、そちらで作業する |
| `worktree remove` が失敗 | 未コミットの変更が worktree に残っている | 変更内容を確認する。プッシュ済み・破棄してよい場合のみ `--force` を使う |
| stash に `.worktrees/` が混入した | ignore 登録前に `stash push -u` した | `git stash show --include-untracked` で確認し、ユーザーに報告して指示を仰ぐ |
````

- [ ] **Step 2: リンク整合を確認する**

Run: `grep -o '](#[^)]*)' skills/github-flow/references/worktree-workflow.md | sort -u`
Expected: `](#基本方針)` `](#状態判定)` `](#worktree-の作成)` `](#既存変更の移送)` `](#マージ後の後始末)` `](#エラー対処)` の6種のみが出力され、対応する見出しがすべて本文に存在する。

- [ ] **Step 3: コミット**

```bash
git add skills/github-flow/references/worktree-workflow.md
git commit -m "docs(github-flow): add worktree workflow reference"
```

---

### Task 2: SKILL.md の worktree 対応

**Files:**
- Modify: `skills/github-flow/SKILL.md`

**Interfaces:**
- Consumes: Task 1 の `references/worktree-workflow.md`（ファイル名・セクション構成）
- Produces: なし（最終成果物）

- [ ] **Step 1: frontmatter の description を置き換える**

現在の description（3〜9行目）を以下に置き換える:

```yaml
description: >
  GitHub Flowに従ってworktree作成・コミット・プッシュ・プルリクエスト作成を行う。
  「コミットして」「PRを作って」「ブランチ切ってPR」「git addからPR作成まで全部」
  「変更をまとめてPR」「実装が終わった、コミットして」など作業完了時の表現に加え、
  「作業を開始して」「ブランチ切って作業して」「worktreeで作業して」「実装を始めよう」
  など作業開始時の依頼でも必ずこのスキルを使う。worktreeによる作業分離・ブランチ戦略・
  Conventional Commits・選択的ステージング・gh CLIでのPR作成をカバーする。
  次の用途には使わない: git stash、rebase、diff/log閲覧、コンフリクト解決、
  CI/テスト失敗の調査、ブランチ削除（新しい変更を保存しない操作）。
```

- [ ] **Step 2: ワークフロー全体像の図を更新する**

`[ブランチ確認]` を `[worktree 準備]` に置き換える:

```
[worktree 準備] → [コミット範囲の決定] → ┌──────────────────────────────┐
                                          │ 論理単位ごとにコミット（ループ）│ → [プッシュ] → [PR作成]
                                          │  作業ツリーがクリーンになるまで │
                                          └──────────────────────────────┘
```

- [ ] **Step 3: リファレンス表に1行追加する**

`branching-strategies.md` の行の直後に追加:

```markdown
| `references/worktree-workflow.md` | worktreeの作成／既存変更の移送／マージ後の後始末／worktree関連のエラー対処 |
```

- [ ] **Step 4: Step 1 セクションを置き換える**

現在の「## Step 1: ブランチ確認・作成」セクション全体を以下に置き換える:

````markdown
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
````

- [ ] **Step 5: 「完了後」セクションを置き換える**

現在の「## 完了後」セクション全体を以下に置き換える:

````markdown
## 完了後

PR URL をユーザーに報告する。レビュー対応は同じブランチ（worktree 内）へ追加コミットして `git push`。
マージ後はメインの checkout に戻り、worktree とブランチを削除する:

```bash
git worktree remove .worktrees/<branch-dir>
git branch -d <branch>
```

トラブル時は `references/pull-request-workflow.md` と `references/worktree-workflow.md` のエラー表を参照。
````

- [ ] **Step 6: 参照整合を確認する**

Run: `grep -o 'references/[a-z-]*\.md' skills/github-flow/SKILL.md | sort -u` の各ファイルが `ls skills/github-flow/references/` に存在すること。
Expected: `branching-strategies.md` `commit-conventions.md` `pr-template-default.md` `pull-request-workflow.md` `worktree-workflow.md` がすべて存在。

- [ ] **Step 7: コミット**

```bash
git add skills/github-flow/SKILL.md
git commit -m "feat(github-flow): isolate work in git worktrees from step 1"
```

---

### Task 3: scratch リポジトリでのコマンド列検証

**Files:**
- なし（検証のみ。問題が見つかった場合のみ Task 1/2 のファイルを修正）

**Interfaces:**
- Consumes: Task 1・Task 2 に記載したコマンド列

- [ ] **Step 1: scratch リポジトリを作り、3シナリオを検証する**

scratchpad 配下に使い捨てリポジトリを作成:

```bash
cd <scratchpad>
mkdir wt-test && cd wt-test && git init -b main
echo hello > a.txt && git add a.txt && git commit -m "init"
```

**シナリオ1（main・クリーン → worktree 作成）:**

```bash
git check-ignore -q .worktrees || echo '.worktrees/' >> "$(git rev-parse --git-common-dir)/info/exclude"
git worktree add .worktrees/feature-x -b feature/x
cd .worktrees/feature-x
git rev-parse --git-dir --git-common-dir
```
Expected: `worktree add` 成功。`rev-parse` の2行が異なる値（worktree 内判定が機能）。

**シナリオ2（main・変更あり → stash 移送）:**

```bash
cd ../..
echo change >> a.txt && echo new > b.txt
git stash push -u -m "github-flow: move to worktree"
git worktree add .worktrees/feature-y -b feature/y
cd .worktrees/feature-y
git stash pop
git status --short
```
Expected: `stash pop` 成功。`git status --short` に ` M a.txt` と `?? b.txt` が表示され、`.worktrees/` は混入していない。メイン checkout（`cd ../.. && git status --short`）はクリーン。

**シナリオ3（後始末）:**

```bash
cd .worktrees/feature-x && cd ../..   # メイン checkout で実行
git worktree remove .worktrees/feature-x
git branch -d feature/x
```
Expected: 両コマンド成功。`git worktree list` に feature-x が残っていない。

- [ ] **Step 2: 検証結果を反映する**

3シナリオがすべて期待通りなら scratch リポジトリを削除して完了。期待と異なる挙動があった場合は Task 1/2 の該当記述を修正し、`fix(github-flow):` でコミットする。

---

## Self-Review 結果

- **Spec coverage:** Step 1 の3分岐（Task 2 Step 4）、リファレンス新設（Task 1）、description 拡張（Task 2 Step 1）、完了後の後始末（Task 2 Step 5）、エラー対処表（Task 1）、検証シナリオ（Task 3）— 設計書の全要件をカバー。
- **設計書との差分:** ignore 登録方式のみ `.gitignore` → `.git/info/exclude` 第一に変更（理由は Global Constraints に記載）。
- **Placeholder:** なし（全ファイル内容・全コマンド・期待出力を記載済み）。
- **整合性:** `worktree-workflow.md` のセクション名と SKILL.md からの参照が一致することを Task 1 Step 2 / Task 2 Step 6 で機械的に確認する。
