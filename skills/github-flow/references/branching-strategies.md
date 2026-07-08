# ブランチ戦略（GitHub Flow）

GitHub Flow におけるブランチの考え方と命名規則。

## 目次

- [GitHub Flow の原則](#github-flow-の原則)
- [ブランチ命名規則](#ブランチ命名規則)
- [git worktree の活用](#git-worktree-の活用)
- [よくある間違い](#よくある間違い)

## GitHub Flow の原則

GitHub Flow はシンプルなブランチモデル。`main`（デフォルトブランチ）は常にデプロイ可能な状態を保つ。

1. `main` から作業用ブランチを作成する
2. ブランチ上でコミットを重ねる
3. プルリクエストを作成してレビューを依頼する
4. レビューに対応する
5. 承認・CIグリーン後に `main` へマージする
6. マージ済みブランチを削除する

**重要なルール:**
- `main` / `master` に直接コミット・直接プッシュしない。必ずブランチを切ってPR経由でマージする
- ブランチは短命に保つ。長く生かすと `main` との乖離が大きくなりコンフリクトの原因になる

## ブランチ命名規則

```
<prefix>/<kebab-case-description>
```

| prefix | 使いどき |
|--------|---------|
| `feature/` | 新機能 |
| `fix/` | バグ修正 |
| `docs/` | ドキュメント |
| `refactor/` | リファクタリング |
| `chore/` | その他 |

例:
- `feature/add-user-auth`
- `fix/login-redirect-bug`
- `refactor/extract-validation`

チケット番号を含める運用の場合は `feature/PROJ-123-add-auth` のように付与する。

```bash
git switch -c feature/add-user-auth
```

## git worktree の活用

ブランチの作り方は、現在の状態で使い分ける（SKILL.md Step 1 と同じ判断表）。

| 観測される状態 | アクション |
|--------------|-----------|
| 現在ブランチが main/master 以外 | そのまま作業を続行 |
| main/master 上で、未コミットの変更がある | その場で `git switch -c <prefix>/<name>`（未コミット変更は新ブランチへ追従するため安全） |
| main/master 上でクリーン（これから新タスクを開始） | `git worktree add ../<リポジトリ名>-<name> -b <prefix>/<name>` を優先し、以後そのworktree内で作業する |

worktree を使うと、元の作業ツリーを汚さずに独立したディレクトリで並行作業できる。

```bash
# 新しいブランチ付きで worktree を作成（例: リポジトリ myapp、ブランチ feature/add-auth）
git worktree add ../myapp-add-auth -b feature/add-auth

# worktree の一覧を確認
git worktree list

# マージ後の後始末（ブランチ削除の前に worktree を除去する）
git worktree remove ../myapp-add-auth
```

## よくある間違い

**❌ Conventional Commits の type をブランチ prefix に流用する**

```
feat/add-login      # NG: feat はコミットの type
fix/null-check      # fix/ は許容されるが feature/ との対応に注意
```

ブランチ prefix（`feature/`）と Conventional Commits の type（`feat:`）は別物。新機能のブランチは `feature/`、コミットは `feat:` を使う。

**❌ main で直接作業する**

main にいる状態で `git commit` しない。先に SKILL.md Step 1 の判断表に従ってブランチ（または worktree）を用意する。
