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
