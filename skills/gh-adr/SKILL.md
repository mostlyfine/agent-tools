---
name: gh-adr
description: gh CLIでPR・Issueの履歴を取得し変更履歴を生成するスキル。「変更履歴を作って」「PRから変更記録を作って」「なぜこの変更をしたか記録したい」「意思決定記録を残したい」「ADRを作って」という依頼で起動。Issue→Why/Problem（背景・問題）、PR→How/What（解決方針・実施内容）に対応する箇条書き形式でdocs/changes/配下にファイルを出力する。PR番号・期間・ラベル指定に対応。
allowed-tools: Bash(mkdir *) Bash(find *) Bash(ls *) Bash(date *) Bash(gh pr list *) Bash(gh pr view *) Bash(gh issue list *) Bash(gh issue view *) Bash(gh repo view *) Bash(jq *) AskUserQuestion Read Write
---

# gh-adr: 変更履歴ジェネレーター（GitHub PRs & Issues）

GitHubの履歴から変更履歴を自動生成する。Issue が「なぜ変更が必要だったか（Why / Problem）」、PR が「どう解決したか（How / What）」に対応する。アーキテクチャ変更に限らず、あらゆる変更の背景と意思決定を記録することを目的とする。

---

## Phase 0: 出力先フォルダを準備する

最初に `docs/changes/` ディレクトリを作成する。すでに存在する場合は何もしない：

```bash
mkdir -p docs/changes
```

---

## Phase A: 対象PRを特定する

ユーザーの入力から以下の3パターンを判定する：

- **PR番号直接指定** — 例: 「PR #42 から変更履歴を作って」
- **期間指定** — 例: 「先月マージされたPRを変更履歴にして」
- **ラベル指定** — 例: 「feature ラベルのPRを変更履歴にまとめて」

情報が不足している場合は必ず確認を取る：

```
対象のPR番号、期間（例: 過去30日）、またはラベルを教えてください。
現在のディレクトリのリポジトリを対象にしますか？
```

---

## Phase B: PR情報を取得する

取得後は必ず `jq` でパースして各フィールドを変数として扱う。

**PR番号指定の場合：**

```bash
gh pr view <N> --json number,title,body,mergedAt,author,labels,url,closingIssuesReferences \
  | jq '{
      number: .number,
      title: .title,
      body: .body,
      mergedAt: (.mergedAt | split("T")[0]),
      mergedAtCompact: (.mergedAt | split("T")[0] | gsub("-"; "")),
      author: .author.login,
      labels: [.labels[].name],
      url: .url,
      closingIssues: [.closingIssuesReferences[].number]
    }'
```

**期間指定の場合：**

期間の境界日付は暗算せず、`date` コマンドで計算する（例: 「過去30日」の開始日）：

```bash
date -v-30d +%Y-%m-%d          # macOS (BSD date)
date -d '30 days ago' +%Y-%m-%d  # Linux (GNU date)
```

計算した日付を `merged:>` に埋め込んで検索する：

```bash
gh pr list --state merged --search "merged:>YYYYMMDD" \
  --json number,title,body,mergedAt,author,labels,url,closingIssuesReferences --limit 50 \
  | jq '[.[] | {
      number: .number,
      title: .title,
      mergedAt: (.mergedAt | split("T")[0]),
      mergedAtCompact: (.mergedAt | split("T")[0] | gsub("-"; "")),
      author: .author.login,
      labels: [.labels[].name],
      url: .url
    }]'
```

**ラベル指定の場合：**

```bash
gh pr list --state merged --label <LABEL> \
  --json number,title,body,mergedAt,author,labels,url,closingIssuesReferences \
  | jq '[.[] | {number: .number, title: .title, mergedAt: (.mergedAt | split("T")[0]), mergedAtCompact: (.mergedAt | split("T")[0] | gsub("-"; "")), url: .url}]'
```

期間・ラベル指定で複数PRが返った場合は一覧をユーザーに提示し、変更履歴化する対象を確認する。対象が決まったら番号指定の形式で各PRの詳細を取得する。

**複数PR（5件以上）の詳細を効率よく取得する場合（forループを使う）：**

```bash
for n in 83 82 81 80 79; do
  echo "=== PR #$n ==="
  gh pr view $n --json number,title,body,mergedAt,author,closingIssuesReferences \
    | jq '{number: .number, title: .title, body: .body, mergedAt: (.mergedAt | split("T")[0]), author: .author.login, closingIssues: [.closingIssuesReferences[].number]}'
done
```

件数が多い場合は2バッチに分割して並行実行する（片方が処理中に結果を先読みできるため）。

**IssueとIssueコメントの取得：**

```bash
gh issue view <N> --comments \
  --json number,title,body,author,createdAt,url,comments \
  | jq '{
      number: .number,
      title: .title,
      body: .body,
      author: .author.login,
      url: .url,
      comments: [.comments[] | {author: .author.login, body: .body}]
    }'
```

**リポジトリ名の取得：**

```bash
gh repo view --json nameWithOwner | jq -r '.nameWithOwner'
```

---

## Phase B-2: 本番デプロイPRのグルーピング

期間・ラベル指定で取得したPRの中に「本番デプロイ」専用PRが含まれている場合、feature PRと統合して1つのADRにまとめる。

**本番デプロイPRの判定パターン：**
- タイトルに「本番デプロイ」「prod deploy」「production deploy」が含まれる
- body に「の本番デプロイ」「の production deploy」+ 別PRのURLが含まれる

**統合ルール：**
1. 本番デプロイPRのbodyから参照されているfeature PR番号を抽出する
2. feature PRが**対象期間内**の場合: feature PRの内容をメインにし、prod deployのPR URLもReferencesに含める。ADRの日付はprod deployのmergedAtを使う（実際にリリースされた日）
3. feature PRが**対象期間外**（過去のPRなど）の場合: 限定的な情報でADRを生成し、「詳細はfeature PR #Nを参照」と記載する → エラー処理表の「対象期間外のfeature PR参照」を参照
4. 1つのprod deployが複数のfeature PRをまとめている場合: **feature PRごとに別々のADRを生成する**（本番デプロイPRは各ADRのReferencesに記載するのみ）

---

## Phase C: IssueとPRを紐づける

### C-1. closingIssuesReferences を確認

PRの `closingIssuesReferences` フィールドにIssue番号が含まれていれば、それを使う。

### C-2. フォールバック: PR bodyからIssue番号を抽出

`closingIssuesReferences` が空の場合、PR bodyを正規表現で検索する：

```
(closes|fixes|resolves|refs?)\s+#(\d+)
```

### C-3. Issue詳細とコメントを取得

Issue番号が判明したら Phase B の Issue 取得コマンドで詳細を取得する。`comments[].body` を全て Why / Problem の補足として参照する。

### C-4. コミットメッセージの取得

以下のいずれかに該当する場合は**必ず**取得する（判断を省略しない）：

- PR body が空（空文字・改行のみ）
- PR body が「SSIA」「same as above」など1〜2行の短文で実質的な情報がない
- PR body にテーブル名・カラム名・ファイル名・IDなどの固有名詞が含まれていない

上記以外でも、How の補足として有用と判断した場合は取得してよい。

```bash
gh pr view <N> --json commits \
  | jq '[.commits[] | {headline: .messageHeadline, body: .messageBody}]'
```

コミットメッセージは **How の情報源** として使う。PR body・コミット body から情報を読み取り、How の各項目を「**対象**（テーブル名・ファイル名・API名などの固有名詞）+ **操作**（追加・変更・削除など）+ **具体値**（ID・名前・設定値）」の3要素で構成する（変換の実例は Phase E の完成例を参照）。

### C-5. Slackリンクの検出

Issue body・全コメント・PR bodyのいずれかに Slack リンクが含まれる場合：

1. 全リンクを抽出して一覧表示する
2. 「このSlackスレッドの内容を変更履歴に含めたい場合は、内容をコピペしてください」とユーザーに依頼する
3. ユーザーが提供した場合は Why または Problem の補足として組み込む

Issue不在時はPR bodyをWhy/Problemとして使用し、その旨をユーザーに通知する。

---

## Phase D: ファイル名プレフィックスを決定する

PRの `mergedAt` からマージ日を取得し、`YYYYMMDD` 形式のプレフィックスとして使用する。

- マージ済みPRの場合: `mergedAtCompact`（例: `20260612`）
- 未マージPRの場合: 実行日の日付を使用する

同一日に複数の変更履歴を生成する場合、ファイル名が重複しないよう `-2`, `-3` などのサフィックスを**ファイル名末尾（`.md` の直前）**に付加する：

- 例（1件目）: `20260331-add-movie-portal-tables.md`
- 例（2件目）: `20260331-exclude-content-access-staging-2.md`

サフィックスはケバブケースのスラッグ末尾に付けること（日付プレフィックスの直後ではない）。

```bash
find docs/changes -name "YYYYMMDD-*.md" -type f 2>/dev/null
```

---

## Phase E: 変更履歴を生成・保存する

### フィールドマッピング

| セクション | ソース |
|---|---|
| Title | PRタイトル |
| Date | PRの `mergedAt`（`YYYY-MM-DD` 形式に変換）|
| Author | PRの `author.login`（`@` prefix付き）|
| Status | `Completed`（マージ済みPR）|
| Repository | `gh repo view --json nameWithOwner` で取得した `owner/repo` 形式 |
| References | Issue URL / PR URL / Slack リンク / その他 URL（body・コメントから抽出）|
| Why | Issue body + Issue 全コメント → 変更の背景・動機・経緯。なければ PR body の背景部分 |
| Problem | Issue body + Issue 全コメント → 具体的な問題・課題・制約 |
| How | PR body + コミットメッセージ body → 各項目を「**対象**（テーブル名・ファイル名・API名などの固有名詞）+ **操作**（追加・変更・削除など）+ **具体値**（ID・名前・設定値）」の3要素で構成した箇条書き |

**Why / Problem / How の各セクションは、1項目=1行の箇条書きで記述する。**

### 完成例（入力素材 → ADR）

以下の入力素材から生成する ADR の完成形。この形をそのまま模倣する。

**入力素材（抜粋）：**

- Issue #101 body: 「セッションストア（Redis）の運用コストが月$300かかっている。APIサーバーのスケールアウト時にセッション共有が必要で構成が複雑。Redis障害時に全ユーザーがログアウトされる。」
- PR #123: title `Migrate auth middleware to JWT` / author `alice` / mergedAt `2026-06-12` / body: 「Closes #101. セッション認証をJWTに移行。トークン有効期限は24時間。」
- コミット1: headline `feat(auth): add JWT verification middleware` / body: 「RS256署名検証を auth/jwt.go に実装。公開鍵は AUTH_JWT_PUBLIC_KEY 環境変数から読み込む。」
- コミット2: headline `refactor(auth): remove session middleware` / body: 「auth/session.go を削除。」

**生成される ADR（ファイル名: `docs/changes/20260612-migrate-auth-middleware-to-jwt.md`）：**

```markdown
# Migrate auth middleware to JWT

- **Date**: 2026-06-12
- **Author**: @alice
- **Status**: Completed
- **Repository**: example/api-server

## References

- Issue: https://github.com/example/api-server/issues/101
- PR: https://github.com/example/api-server/pull/123

## Why（背景）

- セッションストア（Redis）の運用コストが月$300発生していた
- APIサーバーのスケールアウト時にセッション共有が必要で構成が複雑だった

## Problem（問題）

- Redis障害時に全ユーザーがログアウトされる単一障害点になっていた

## How（解決内容）

- `auth/jwt.go` にRS256署名検証を行うJWT検証ミドルウェアを追加（トークン有効期限: 24時間）
- 公開鍵の読み込み元を環境変数 `AUTH_JWT_PUBLIC_KEY` に設定
- セッション認証ミドルウェア `auth/session.go` を削除
```

コミット headline `feat(auth): add JWT verification middleware` がそのまま How に並ぶのではなく、コミット body の情報と合わせて「対象（`auth/jwt.go`）+ 操作（追加）+ 具体値（RS256・有効期限24時間）」の1行に変換されている点に注目すること。

### ファイル名の生成ルール

- プレフィックス: PRの `mergedAt` の日付（`YYYYMMDD` 形式）
- PRタイトルを小文字に変換
- 記号・スペースをハイフンに置換、連続ハイフンは1つに圧縮
- 英数字とハイフンのみ残す（日本語は英語要約を簡潔に生成）
- 同一日に複数ある場合: `-2`, `-3` を付加
- 例: `20260612-migrate-auth-middleware-to-jwt.md`

### テンプレート

テンプレートは `BASE_DIR/templates/adr.md` に定義されている（`BASE_DIR` はスキル呼び出し時に提示されるベースディレクトリ）。

Read ツールで読み込んでから使用する：

```
Read: <BASE_DIR>/templates/adr.md
```

読み込んだ内容をベースに各フィールドを上記マッピングに従って埋める。

### 書き込み前セルフチェック

生成した各 ADR について、以下を全て満たしていることを確認する。満たさない項目があれば修正してから次へ進む：

- [ ] テンプレートの全スロット（Title / Date / Author / Status / Repository / References / Why / Problem / How）が埋まっている
- [ ] Why / Problem / How の各セクションが箇条書き（1項目=1行）になっている
- [ ] How の各項目に固有名詞（テーブル名・ファイル名・API名など）または具体値（ID・名前・設定値）が最低1つ含まれている
- [ ] ファイル名が `YYYYMMDD-kebab-case.md` 形式で、同日重複時は `-2` サフィックスがスラッグ末尾（`.md` の直前）に付いている

### プレビューと確認

1. 生成した変更履歴をユーザーにプレビュー表示する
2. 複数PR対象の場合は全件まとめて表示する
3. 「この内容でファイルを書き込みますか？修正が必要な場合は教えてください。」と確認を取る
4. 確認後に `docs/changes/YYYYMMDD-kebab-case-title.md` に書き込む

**例外: ユーザーが「全て出力」「全件出力」「全部書き込んで」と明示した場合**、プレビュー表示と確認ステップをスキップして直接全件書き込む。書き込み完了後に生成ファイル一覧を表形式で通知する。

---

## エラー処理

| 状況 | 対応 |
|---|---|
| `gh` が未認証 | `gh auth status` の実行を案内する |
| PRがまだマージされていない | Status を `In Progress` にして生成し、その旨を通知する |
| Issue詳細の取得に失敗 | PR bodyのみで生成し、IssueリンクをReferencesに記載 |
| 対象期間外のfeature PRを参照している | 「詳細は feature PR #N を参照」と How に記載し、PR URLをReferencesに追加して生成する。情報が限定的な旨をユーザーに通知する |
