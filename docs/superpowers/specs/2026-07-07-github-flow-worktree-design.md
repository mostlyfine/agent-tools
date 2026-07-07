# github-flow スキルへの worktree 統合 — 設計書

日付: 2026-07-07
対象: `skills/github-flow/`

## 背景・目的

現状の github-flow スキルは Step 1 で `git checkout -b` を実行し、メインの checkout 上でブランチを切り替えて作業する。この方式には次の問題がある。

- 作業中、メインの checkout が main 以外のブランチに占有される
- 複数の作業を並行できない
- 作業途中の状態がメインの checkout を汚す

これを解決するため、作業開始前に `git worktree` で独立した作業ディレクトリを作成し、その中で実装からコミット・PR 作成までを完結させるフローに変更する。

## スコープ

変更対象は github-flow スキルのみ。

- `skills/github-flow/SKILL.md` — Step 1 の置き換え、description 更新、完了後セクションの拡張
- `skills/github-flow/references/worktree-workflow.md` — 新設（worktree の作成・移送・後始末・エラー対処の詳細）

スコープ外: 他スキルの変更、Claude Code ネイティブの EnterWorktree ツールの利用（汎用性のため git コマンドのみで実現する）。

## 決定事項

| 項目 | 決定 |
|------|------|
| 作成方式 | `git worktree` コマンド（エージェント非依存） |
| 配置場所 | リポジトリ内 `.worktrees/<branch-dir>`（`.gitignore` に要登録） |
| 既存変更の扱い | 常に worktree へ移送（`git stash -u` → worktree 内で `git stash pop`） |

ディレクトリ名はブランチ名の `/` を `-` に置換する（例: ブランチ `feature/add-auth` → `.worktrees/feature-add-auth/`）。

## 挙動仕様

### Step 1（新）: worktree 準備

呼び出し時の状態で3分岐する。

1. **既に worktree 内、または feature ブランチ上にいる**
   → 何もせずそのまま Step 2 へ。二重に worktree 化しない。
   判定: `git rev-parse --git-common-dir` と `--git-dir` の差異で worktree 内かを判定。ブランチは `git branch --show-current` で確認。
2. **main/master 上でクリーン（これから作業を始める）**
   → ブランチ名を決めて worktree を作成し、以降の作業（実装・コミット・プッシュ・PR）はすべて worktree 内で実行する。
   ```bash
   git worktree add .worktrees/<branch-dir> -b <branch>
   cd .worktrees/<branch-dir>
   ```
3. **main/master 上で変更あり（「実装終わった、コミットして」）**
   → 変更を stash で worktree に移送してからコミットフローへ。
   ```bash
   git stash push -u -m "github-flow: move to worktree"
   git worktree add .worktrees/<branch-dir> -b <branch>
   cd .worktrees/<branch-dir>
   git stash pop
   ```

共通の前処理として、`.gitignore` に `.worktrees/` が無ければ追加する（リポジトリごとに初回のみ）。

### Step 2〜6: 変更なし

コミット範囲の決定〜PR 作成は既存フローのまま。ただし全ステップを worktree 内で実行する旨を SKILL.md に明記する。

### 完了後（拡張）

マージ後の後始末に worktree の削除を追加する。

```bash
cd <メインcheckout>
git worktree remove .worktrees/<branch-dir>
git branch -d <branch>
```

### トリガー（description）の拡張

現状の description は作業完了時の表現（「コミットして」「PRを作って」）に偏っている。作業開始時にもスキルが発動するよう、「作業開始して」「ブランチ切って作業して」「worktree で作業して」等の表現を description に追加する。

## エラー対処（references/worktree-workflow.md に記載）

| 状況 | 対処 |
|------|------|
| `git stash pop` がコンフリクト | stash を消さずに停止し、ユーザーに報告して指示を仰ぐ |
| 同名ブランチの worktree が既に存在 | 新規作成せず、その worktree に移動して再利用 |
| worktree にコミット済み変更が残ったまま remove しようとした | `git worktree remove` は失敗する（安全側）。プッシュ済みか確認してから対処 |

## 検証方法

自動テストが無いスキル（Markdown）のため、以下の手動シナリオで検証する。

1. main 上・クリーン状態で「ブランチ切って作業して」→ worktree が作成され、その中で作業が進むこと
2. main 上・変更あり状態で「コミットして」→ 変更が worktree に移送されてコミットされること
3. worktree 内で再度スキルを呼ぶ → 二重 worktree 化しないこと
4. マージ後の後始末で worktree とブランチが削除されること
