---
name: github-flow
description: >
  GitHub Flowに従ってコミット・プッシュ・プルリクエスト作成を行う。
  「コミットして」「PRを作って」「ブランチ切ってPR」「git addからPR作成まで全部」
  「変更をまとめてPR」「実装が終わった、コミットして」など、部分的な依頼や作業完了の
  自然な表現を含め必ずこのスキルを使う。次の用途には使わない: git stash、rebase、
  diff/log閲覧、コンフリクト解決、CI/テスト失敗の調査、ブランチ削除（新しい変更を保存しない操作）。
compatibility: "Requires: git, gh CLI (GitHub CLI)"
---

# GitHub Flow スキル

GitHub Flow + Conventional Commits に従い、依頼された範囲だけを実行して完結させる。
このファイル単体でワークフロー全体を実行できる。references は詳細・例が必要なときだけ読む（末尾の表参照）。

## Step 0: スコープ決定（最初に必ず行う）

依頼の表現から**終端ステップ**を決める。終端ステップより先は実行しない。

| 依頼の表現 | 終端ステップ |
|-----------|-------------|
| 「コミットして」「変更を保存して」 | **Step 4**（コミット）で終了 |
| 「プッシュして」 | **Step 5**（プッシュ）で終了 |
| 「PR作って」「PRまで全部」「まとめてPR」 | **Step 6**（PR作成）まで |
| 上記に該当せず不明瞭 | 依頼で明示された最終成果物まで。判断できなければ `AskUserQuestion` で確認 |

終端ステップに到達したら作業を止め、「完了報告」（下記セクション）を行う。

## Step 1: ブランチ確保

```bash
git branch --show-current
git status --short
```

観測した状態で分岐する。**main / master に直接コミットしない。**

| 観測される状態 | アクション |
|--------------|-----------|
| 現在ブランチが main/master 以外 | そのまま作業を続行 |
| main/master 上で、未コミットの変更がある | その場で `git switch -c <prefix>/<name>`（未コミット変更は新ブランチへ追従するため安全） |
| main/master 上でクリーン（これから新タスクを開始） | `git worktree add ../<リポジトリ名>-<name> -b <prefix>/<name>` を優先し、以後そのworktree内で作業する |

ブランチ prefix 早見: `feature/`（新機能） `fix/`（バグ修正） `docs/` `refactor/` `chore/`。
命名規則と worktree の詳細は `references/branching-strategies.md` を参照。

## Step 2: コミット範囲の決定

```bash
git diff --cached --stat   # ステージング済みの変更概要
git status                 # Staged/Unstaged/Untracked を確認
```

- **ステージング済みの変更がある** → それだけがコミット範囲。未ステージング・未追跡は無視して **Step 4** へ。ユーザーは `git add` 済みの内容で意図を示している。コミットメッセージは staged 範囲内の**すべての変更**をカバーする（無関係な変更が混在していても簡潔に言及する）。
- **何もステージングされていない** → 未ステージング＋未追跡のすべてを候補として **Step 3** へ。
- **コミットすべき変更がない（作業ツリーがクリーン）** → 終端が Step 5/6 なら **Step 5** へ直行（未プッシュのコミットや既存ブランチをそのまま扱う）。終端が Step 4 なら「コミット対象の変更なし」と完了報告して終了。

## Step 3: コミット計画と確認

1. `git diff HEAD` を分析し、変更を論理単位にグルーピングする。分割基準:
   - type（feat/fix/docs 等）が異なる変更 → 別コミット
   - 同一 type でも無関係なモジュール・関心事 → 別コミット
2. **秘密ファイルらしきもの（`.env`・認証情報・秘密鍵・トークン類）はコミット候補から無条件に除外し、除外した旨を完了報告に明記する。**
3. 未追跡ファイルの取捨（どれをコミットに含めるか）とコミット分割計画（各コミットの対象ファイルと提案メッセージ）を、**まとめて1回の `AskUserQuestion`** で提示して承認を得る。未追跡ファイルがなく分割も不要（1コミットで自明）な場合は確認不要で Step 4 へ。

## Step 4: ステージングとコミット（ループ）

コミット範囲によってループの終了条件が異なる:

- **Step 2 でステージング済みをコミット範囲とした場合** → 以下を1回だけ実行して終了（ステージングは済んでいるので手順1は省略。未ステージング・未追跡には触れない）
- **Step 3 の計画がある場合** → 計画のすべての単位を消化するまで1単位ずつ繰り返す

1. **ステージング**: ファイル単位の `git add <file1> <file2>` がデフォルト（削除は `git rm <file>`）。1ファイル内に複数の論理単位が混在する場合のみハンク分割する（手順は `references/commit-conventions.md` の「ハンク単位ステージング」参照）
2. **検証**: `git diff --staged` で意図した変更だけがステージされていることを確認する。秘密情報（`.env`・認証情報・秘密鍵・トークン類）が含まれていたら `git restore --staged <file>` で外し、完了報告に明記する
3. **コミット直前チェックリスト**（すべて満たしてから実行）:
   - (a) subject は英語の命令形・小文字始まり・末尾ピリオドなし
   - (b) **subject の文字数を数えて72字以内であること。超えていたら短縮してから実行する**
   - (c) subject は WHY（背景・理由）を表しているか
     - ❌ `fix(auth): fix null pointer error`
     - ✅ `fix(auth): prevent crash when session expires without refresh`
   - (d) 意図した変更のみステージされているか
4. **コミット**: Conventional Commits 形式（`<type>(<scope>): <description>`）。body は subject だけで不十分なとき WHY を箇条書きで（日本語可）

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <why-description>

[body - 省略可]
EOF
)"
```

5. 計画に未消化の単位が残っていれば 1 へ戻る

コミット後にメッセージ修正を依頼されたら `git commit --amend`（**未プッシュのみ**）。
コミット前にフックの有無を確認しておくとエラー時に原因を特定しやすい:

```bash
ls lefthook.yml .lefthook.yml captainhook.json .husky/pre-commit .pre-commit-config.yaml 2>/dev/null
```

## Step 5: プッシュ

```bash
git push -u origin <branch-name>
```

フォースプッシュが必要な場合は `--force-with-lease` のみ使用。詳細は `references/pull-request-workflow.md`。

## Step 6: プルリクエスト作成

PRタイトルは英語の Conventional Commits 形式、PR本文は日本語。本文テンプレートは次の手順で決める:

```bash
cat .github/pull_request_template.md 2>/dev/null || echo "TEMPLATE_NOT_FOUND"
```

- テンプレートがある → それをベースに本文を作成する
- ない（`TEMPLATE_NOT_FOUND`） → `references/pr-template-default.md` を使う

```bash
gh pr create --title "<type>(<scope>): <description in English>" --body "<日本語の本文>"
```

作成後は PR URL をユーザーに報告する。本文組み立ての詳細・オプション・エラー対処は `references/pull-request-workflow.md` を参照。

## 完了報告（終端ステップ到達時）

以下の4項目をすべて埋めて報告する:

1. **実行した範囲と成果**: どのステップまで実行したか、作成したコミット一覧（PR作成まで行った場合は PR URL）
2. **秘密ファイル**: `git status` の変更・未追跡一覧を見て `.env`・認証情報・秘密鍵・トークン類の有無を判定し、「秘密ファイル: `<ファイル名>`（コミットから除外済み）」または「秘密ファイル: なし」と必ず記載する
3. **コミットに含めなかったファイル**: あれば理由とともに列挙（なければ省略可）
4. **次にできること**: 例: コミットで終了した場合「プッシュしますか？」

## 禁止事項

| 禁止 | 代わりに |
|------|---------|
| `git add -A` / `git add .` | ファイルを明示して `git add <file>` |
| `git push --force` | `git push --force-with-lease` |
| `--no-verify` でフックを回避 | フックの失敗原因を修正する |
| main/master への直接コミット・直接プッシュ | ブランチを切って PR 経由でマージ |
| プッシュ済みコミットの `--amend` | 新しいコミットとして積む |
| 秘密ファイル（`.env`・認証情報・秘密鍵・トークン類）のステージング | 除外し、除外した旨を完了報告に明記 |

## リファレンス

| リファレンス | 読むタイミング |
|------------|--------------|
| `references/branching-strategies.md` | 命名規則の詳細／GitHub Flow の原則／worktree のコマンド例 |
| `references/commit-conventions.md` | タイプ一覧・BREAKING CHANGE・メッセージ例／ハンク単位ステージングの手順 |
| `references/pull-request-workflow.md` | PR本文組み立ての詳細／`gh pr create` オプション／マージ後の後始末／エラー対処 |
| `references/pr-template-default.md` | `.github/pull_request_template.md` が無い場合のPR本文テンプレート |
