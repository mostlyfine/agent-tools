# Maker/Reviewer 自律開発ループ 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** maker.md・reviewer.md にフロントマターとループ状態ファイル操作を追加し、CLAUDE.md のオーケストレーション手順を書き換えることで、Agentツールを使った自律 Maker/Reviewer ループを実現する。

**Architecture:** メインセッションが `.claude/loop-state.md` を共有コンテキストとして作成し、Agentツールで `maker` → `reviewer` を順番に呼び出す。各サブエージェントはファイルを読み書きして状態を引き継ぐ。`VERDICT: PASS` が出るまで最大5回繰り返す。

**Tech Stack:** Markdown（Claude Code agent frontmatter YAML）、Claude Code Agentツール

## Global Constraints

- agent frontmatter の `tools` フィールドは Claude Code の仕様に従い、カンマ区切りで列挙する
- `.claude/loop-state.md` のセクション名は `## 計画`、`## ループカウンター`、`## 最新Makerサマリ`、`## 最新Reviewer判定` に統一する（大文字・スペース含め完全一致）
- 既存のペルソナ本文（SOLID/DRY/KISS/YAGNI/TDDの原則、コミット規約、判定基準）は一切変更しない

---

### Task 1: maker.md にフロントマターとループ状態ファイル操作を追加

**Files:**
- Modify: `.claude/agents/maker.md`

**Interfaces:**
- Produces: `subagent_type: "maker"` で起動したサブエージェントが `.claude/loop-state.md` を読んで計画を把握し、完了後に `## 最新Makerサマリ` を書き込む動作

- [ ] **Step 1: 現在の maker.md を読み込む**

```bash
cat .claude/agents/maker.md
```

期待出力: `# 役割: 堅牢な実装・修正エンジニア (Maker Agent)` から始まるファイル内容

- [ ] **Step 2: maker.md をフロントマター付きの新内容に書き換える**

`.claude/agents/maker.md` を以下の内容に書き換える（既存のペルソナ本文はそのまま保持し、フロントマターと2つのセクションを追加する）：

```markdown
---
name: maker
description: 計画に従ってコードを実装するMakerエージェント
tools: Read, Write, Edit, Bash, Glob, Grep
---
# 役割: 堅牢な実装・修正エンジニア (Maker Agent)
前提: あなたの任務は、提示された計画（/plan）に従って、最も美しくテスト可能なコードを実装することである。

## 起動時の手順
必ず最初に `.claude/loop-state.md` を読み込み、以下を確認すること：
- `## 計画` セクション: 今回実装すべき内容
- `## 最新Reviewer判定` セクション: 前回の REJECT 理由（初回は空）

## 開発哲学・実装原則
以下のソフトウェア設計原則を厳格に遵守すること：
- **SOLID**: 各クラス・関数は1つの責任のみを持つように設計する。
- **DRY / KISS**: 重複を避け、過度に複雑にせず、最もシンプルな実装を選ぶ。
- **YAGNI**: 現時点で必要のない「将来のためのコード」は追加しない。
- **テスト駆動 (TDD) の遵守**: 修正するコードは、まずテストを作成してから実装を開始する。常にテストコードで検証可能（モック化しやすい、副作用が分離されている）な設計にすること。

## コミット規約
コードを修正してコミットを生成、または提案する場合は、必ず「Conventional Commits」の仕様に従うこと。
- 例: `feat(auth): ...`, `fix(api): ...`, `test(auth): ...`

## 出力ルール（完了時）
コードの修正が完了したら、`.claude/loop-state.md` の `## 最新Makerサマリ` セクションを以下の形式で上書きすること：

```
## 最新Makerサマリ
変更ファイル: [変更したファイルのパス一覧]
実装内容: [変更の要点を3行以内で記述]
```

その後、変更内容の要約と、次に実行すべきテストコマンド（例: `npm test`）を明示して処理を終了せよ。
```

- [ ] **Step 3: 書き換えが正しく反映されているか確認する**

```bash
head -10 .claude/agents/maker.md
```

期待出力:
```
---
name: maker
description: 計画に従ってコードを実装するMakerエージェント
tools: Read, Write, Edit, Bash, Glob, Grep
---
# 役割: 堅牢な実装・修正エンジニア (Maker Agent)
```

```bash
grep -n "起動時の手順\|最新Makerサマリ\|SOLID" .claude/agents/maker.md
```

期待出力: 3つのパターンがすべてマッチする行が出力される

- [ ] **Step 4: コミットする**

```bash
git add .claude/agents/maker.md
git commit -m "feat(agents): add frontmatter and loop-state integration to maker agent"
```

---

### Task 2: reviewer.md にフロントマターとループ状態ファイル操作を追加

**Files:**
- Modify: `.claude/agents/reviewer.md`

**Interfaces:**
- Consumes: Task 1 が定める `## 最新Makerサマリ` の形式（変更ファイル一覧と実装内容）
- Produces: `subagent_type: "reviewer"` で起動したサブエージェントが `.claude/loop-state.md` を読んでレビューし、完了後に `## 最新Reviewer判定` に `VERDICT: PASS` または `VERDICT: REJECT` を書き込む動作

- [ ] **Step 1: 現在の reviewer.md を読み込む**

```bash
cat .claude/agents/reviewer.md
```

期待出力: `# 役割: 敵対的コードレビュアー (Evaluator Agent)` から始まるファイル内容

- [ ] **Step 2: reviewer.md をフロントマター付きの新内容に書き換える**

`.claude/agents/reviewer.md` を以下の内容に書き換える（既存のペルソナ本文はそのまま保持し、フロントマターと2つのセクションを追加する）：

```markdown
---
name: reviewer
description: 計画との照合とテスト実行で品質を保証するReviewerエージェント
tools: Read, Bash, Glob, Grep
---
# 役割: 敵対的コードレビュアー (Evaluator Agent)
前提: このコードはテストと計画の双方で証明されるまで「壊れている/要件を満たしていない」と仮定せよ。

## 起動時の手順
必ず最初に `.claude/loop-state.md` を読み込み、以下を確認すること：
- `## 計画` セクション: 照合すべき計画内容
- `## 最新Makerサマリ` セクション: 今回の実装内容と変更ファイル一覧
- `## ループカウンター` セクション: 現在何回目の試行か

## チェック手順:
1. **計画との照合 (Plan Alignment)**:
   - 最初に提示された `/plan`（計画）を読み込み、変更されたコードがその計画を過不足なく満たしているか確認せよ。
   - 計画にない余計なコード（YAGNI違反）や、計画にあるのに実装漏れしている箇所がないか厳しくチェックせよ。
2. **動作検証**:
   - 実際にテスト（npm test等）を実行し、出力を確認せよ。
   - エッジケースや例外処理に不備がないか厳しく探せ。

## 完了時の手順（出力ルール）
`.claude/loop-state.md` の `## 最新Reviewer判定` セクションを以下の形式で上書きすること：

PASSの場合:
```
## 最新Reviewer判定
VERDICT: PASS
```

REJECTの場合:
```
## 最新Reviewer判定
VERDICT: REJECT
- [具体的な乖離内容1（例: テスト `test_foo` が失敗: expected X, got Y）]
- [具体的な乖離内容2（例: 計画にある `bar()` が未実装）]
```

## 判定基準:
- 計画通りの実装であり、かつすべての自動テストが100%成功した場合のみ「VERDICT: PASS」を出力せよ。
- 計画から逸脱している、またはテストが落ちている場合は「VERDICT: REJECT」とし、具体的な乖離内容をリストアップせよ。
```

- [ ] **Step 3: 書き換えが正しく反映されているか確認する**

```bash
head -10 .claude/agents/reviewer.md
```

期待出力:
```
---
name: reviewer
description: 計画との照合とテスト実行で品質を保証するReviewerエージェント
tools: Read, Bash, Glob, Grep
---
# 役割: 敵対的コードレビュアー (Evaluator Agent)
```

```bash
grep -n "起動時の手順\|最新Reviewer判定\|VERDICT" .claude/agents/reviewer.md
```

期待出力: 3つのパターンがすべてマッチする行が出力される

- [ ] **Step 4: コミットする**

```bash
git add .claude/agents/reviewer.md
git commit -m "feat(agents): add frontmatter, tool restrictions, and loop-state integration to reviewer agent"
```

---

### Task 3: CLAUDE.md のオーケストレーション手順を書き換える

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: Task 1 が定める `maker` サブエージェント型、Task 2 が定める `reviewer` サブエージェント型
- Produces: メインセッションが自律的に Maker→Reviewer サイクルを回す動作仕様

- [ ] **Step 1: 現在の CLAUDE.md の「基本開発フロー」セクションを確認する**

```bash
grep -n "基本開発フロー\|計画\|Maker\|Reviewer\|暴走防止" CLAUDE.md
```

期待出力: 各セクション見出しの行番号が表示される

- [ ] **Step 2: CLAUDE.md の「基本開発フロー」セクションを新しいオーケストレーション手順に書き換える**

`CLAUDE.md` の `## 基本開発フロー` セクションから `## 暴走防止ルール（ガードレール）` の直前までを、以下の内容に置き換える：

```markdown
## 基本開発フロー

**適用条件**: コードの実装・修正・リファクタリングを伴うタスクのみ。質問・説明・ドキュメント作成のみのタスクにはこのフローを適用しない。

タスクを依頼されたら、以下の Step 1〜4 を自動で実行すること（手動確認不要）。

### Step 1 — 計画フェーズ
1. `/plan` を実行して計画を確定する
2. `.claude/loop-state.md` を以下のテンプレートで新規作成する：

```
# ループ状態

## 計画
（/plan の出力をここに記録）

## ループカウンター
現在: 1回目 / 最大5回

## 最新Makerサマリ
（未実施）

## 最新Reviewer判定
（未実施）
```

### Step 2 — Makerフェーズ
Agentツールで `maker` サブエージェントを起動する：

```
Agent(
  subagent_type: "maker",
  prompt: "
    .claude/loop-state.md の「## 計画」セクションに従って実装してください。
    「## 最新Reviewer判定」に前回の REJECT 理由があればそれも読んで対処してください。
    完了後は「## 最新Makerサマリ」セクションを更新してください。
  "
)
```

### Step 3 — Reviewerフェーズ
Agentツールで `reviewer` サブエージェントを起動する：

```
Agent(
  subagent_type: "reviewer",
  prompt: "
    .claude/loop-state.md の「## 計画」と「## 最新Makerサマリ」を読み、
    テストを実行して検証してください。
    結果を「## 最新Reviewer判定」に VERDICT: PASS または VERDICT: REJECT で書き込んでください。
  "
)
```

### Step 4 — 判定とループ制御
`.claude/loop-state.md` の `## 最新Reviewer判定` を読み取る：
- `VERDICT: PASS` → ループ終了。ユーザーに完了報告する。
- `VERDICT: REJECT` → `## ループカウンター` を +1 して Step 2 に戻る。
- カウンターが 5回到達、または同一テストエラーが3回連続 → 強制停止して人間にハンドオフ（後述のガードレールに従う）。
```

- [ ] **Step 3: 「暴走防止ルール（ガードレール）」セクションも確認し、ハンドオフ内容の記述と矛盾がないことを確認する**

```bash
grep -A 20 "暴走防止ルール" CLAUDE.md
```

期待出力: 「5回ループ」「3回連続」「人間へのハンドオフ」の記述が残っていること

- [ ] **Step 4: 最終的な CLAUDE.md を通読して整合性を確認する**

```bash
cat CLAUDE.md
```

確認ポイント：
- `## 基本開発フロー` が Step 1〜4 の形式になっていること
- `## 完了・停止条件` と `## 暴走防止ルール` が既存のまま残っていること（これらは削除しない）
- 古い「1. 計画」「2. 実装フェーズ」「3. 検証フェーズ」の箇条書きが消えていること

- [ ] **Step 5: コミットする**

```bash
git add CLAUDE.md
git commit -m "feat(harness): replace dev flow with Step1-4 maker/reviewer orchestration loop"
```

---

## 動作確認（全タスク完了後）

以下のコマンドで3ファイルの変更が正しく揃っていることを最終確認する：

```bash
# maker.md: フロントマターと起動時手順の存在確認
grep -c "name: maker\|起動時の手順\|最新Makerサマリ" .claude/agents/maker.md
# 期待: 3

# reviewer.md: フロントマター・tool制限・判定手順の存在確認
grep -c "name: reviewer\|tools: Read, Bash\|最新Reviewer判定\|VERDICT" .claude/agents/reviewer.md
# 期待: 4以上

# CLAUDE.md: Step 1〜4の存在確認
grep -c "Step 1\|Step 2\|Step 3\|Step 4" CLAUDE.md
# 期待: 4
```
