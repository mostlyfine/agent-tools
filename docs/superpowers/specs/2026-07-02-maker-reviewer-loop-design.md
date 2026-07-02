# Maker/Reviewer 自律開発ループ 設計書

**日付**: 2026-07-02  
**ステータス**: 承認済み

## 背景・課題

現在の CLAUDE.md には plan→Maker→Reviewer のループが文書として定義されているが、実際にはメインセッションが手動で各エージェントを呼び出す必要があり、自律的なサイクルとして機能していない。

## 目標

タスクを依頼すればメインセッションが Agentツール を用いて Maker/Reviewer を自動的に順番に呼び出し、`VERDICT: PASS` が得られるまでループを継続する仕組みを実現する。

---

## アーキテクチャ

```
ユーザー → メインセッション（オーケストレーター）
              │
              ├─ /plan で計画を .claude/loop-state.md に書き出し
              │
              └─ [ループ: 最大5回]
                    │
                    ├─ Maker Agent（Agentツール / subagent_type: maker）
                    │   loop-state.md の計画・前回REJECT理由を参照して実装
                    │   → loop-state.md に「最新Makerサマリ」を書き込み
                    │
                    └─ Reviewer Agent（Agentツール / subagent_type: reviewer）
                        loop-state.md + 実装を参照してテスト実行
                        → loop-state.md に「最新Reviewer判定」を書き込み
                        │
                        PASS → ループ終了・ユーザーへ完了報告
                        REJECT → 差分を記録して次サイクルへ
```

`.claude/loop-state.md` が全サイクルをまたぐ唯一の共有コンテキスト。

---

## コンポーネント詳細

### 1. `.claude/agents/maker.md`

**フロントマター追加**:
```markdown
---
name: maker
description: 計画に従ってコードを実装するMakerエージェント
tools: Read, Write, Edit, Bash, Glob, Grep
---
```

**ペルソナ本文への追記**:
- 起動時: `.claude/loop-state.md` を読み込み、現在の計画と前回のREJECT理由を確認する
- 完了時: 変更ファイル一覧と実装サマリを `.claude/loop-state.md` の `## 最新Makerサマリ` セクションに上書きして終了する

---

### 2. `.claude/agents/reviewer.md`

**フロントマター追加**:
```markdown
---
name: reviewer
description: 計画との照合とテスト実行で品質を保証するReviewerエージェント
tools: Read, Bash, Glob, Grep
---
```

**ペルソナ本文への追記**:
- 起動時: `.claude/loop-state.md` を読み込み、計画・Makerサマリ・前回REJECTを確認する
- 完了時: `VERDICT: PASS` または `VERDICT: REJECT + 具体的な乖離リスト` を `.claude/loop-state.md` の `## 最新Reviewer判定` セクションに上書きして終了する

---

### 3. `.claude/loop-state.md`（ループ状態ファイル）

ループ開始時にメインセッションが作成し、各サブエージェントが読み書きする共有状態ファイル。

```markdown
# ループ状態

## 計画
（/plan の出力をここに記録）

## ループカウンター
現在: 1回目 / 最大5回

## 最新Makerサマリ
（変更ファイル一覧、実装の要点）

## 最新Reviewer判定
VERDICT: REJECT
- テスト `test_foo` が失敗: expected X, got Y
- 計画にある `bar()` が未実装
```

---

### 4. `CLAUDE.md` オーケストレーション手順

タスクを依頼されたら以下を自動で実行する（手動確認不要）：

**適用条件**: コードの実装・修正・リファクタリングを伴うタスクのみ。質問・説明・ドキュメント作成のみのタスクにはループを適用しない。

**Step 1 — 計画フェーズ**
1. `/plan` を実行して計画を確定する
2. `.claude/loop-state.md` を新規作成し、計画・カウンター（1/5）・空のサマリセクションを書き込む

**Step 2 — Makerフェーズ**
```
Agent(
  subagent_type: "maker",
  prompt: "
    .claude/loop-state.md の計画に従って実装してください。
    前回のREJECT理由があればそこも読んで対処してください。
    完了後は loop-state.md の「最新Makerサマリ」を更新してください。
  "
)
```

**Step 3 — Reviewerフェーズ**
```
Agent(
  subagent_type: "reviewer",
  prompt: "
    .claude/loop-state.md の計画・Makerサマリを読み、
    テストを実行して検証してください。
    結果を「最新Reviewer判定」に VERDICT: PASS/REJECT で書き込んでください。
  "
)
```

**Step 4 — 判定とループ制御**
- `.claude/loop-state.md` の判定を読み取る
- `VERDICT: PASS` → ループ終了、ユーザーに完了報告
- `VERDICT: REJECT` → カウンターを +1 して Step 2 へ戻る
- カウンター 5回到達 または 同一エラー3連続 → 強制停止して人間にハンドオフ

---

## ガードレール

| 条件 | 動作 |
|------|------|
| 5回ループしてもPASSなし | 即時停止・人間へ報告 |
| 同一テストエラーが3回連続 | 即時停止・人間へ報告 |
| 人間へのハンドオフ内容 | ① 試みたアプローチ履歴 ② 具体的エラーログ ③ 修正できない理由の仮説 |

---

## 変更ファイル一覧

| ファイル | 変更内容 |
|----------|----------|
| `.claude/agents/maker.md` | フロントマター追加・起動/完了時の状態ファイル操作を追記 |
| `.claude/agents/reviewer.md` | フロントマター追加・tool制限・起動/完了時の状態ファイル操作を追記 |
| `CLAUDE.md` | オーケストレーション手順（Step 1〜4）に書き換え |

---

## スコープ外

- Workflow スクリプトによる並列化（将来の拡張候補）
- `/goal` や `/loop` のネイティブプリミティブへの移行
