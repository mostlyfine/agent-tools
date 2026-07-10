# gmail-fetcher スキル新設 — 設計書

日付: 2026-07-10
対象: `skills/gmail-fetcher/`（新設）

## 背景・目的

既存のfetcher系スキル（spreadsheet-fetcher, slack-fetcher, jira-fetcher, pr-fetcher等）はURL/IDを指定した単発〜複数取得に特化しており、横断検索は明示的に対象外としてきた。しかしGmailはURLでの安定した参照が難しく、「検索してから対象を絞り込む」利用が主になる。既存パターンを踏襲しつつ、検索から取得までを一気通貫でカバーするスキルを新設する。

このスキルはGmail単体のスキルであり、後続でカレンダー版（calendar-fetcher）を同パターンで設計する前提の第一弾に位置づける。

## スコープ

- `skills/gmail-fetcher/SKILL.md` — 新設
- `skills/gmail-fetcher/scripts/gmail_fetcher.py` — 新設
- `tests/skills/test_gmail_fetcher.py` — 新設（純粋関数のユニットテスト）

スコープ外:
- 添付ファイルの実データダウンロード（ファイル名の記載のみ）
- 検索結果一覧そのもののファイル保存（会話内表示のみ）
- メール送信・下書き作成・ラベル付与などの書き込み系操作
- カレンダー連携（別スキルとして後続で設計）

## 決定事項

| 項目 | 決定 |
|------|------|
| 取得経路 | MCP優先（`mcp__claude_ai_Gmail__*`）＋ADCフォールバック（Gmail API直叩き） |
| 検索結果の扱い | 会話内表示のみ。保存はユーザーが選んだスレッドの詳細取得分のみ |
| 添付ファイル | 対象外（本文中にファイル名のみ記載） |
| Markdown整形の主体 | 常にスクリプト（`gmail_fetcher.py`）。MCP経由でもClaudeが解析・整形しない |
| 保存粒度 | 1スレッド = 1ファイル |
| ファイル名 | `{threadId}.md`（件名は特殊文字・重複の懸念があるためID基準） |
| 出力先デフォルト | `docs/gmail`（Claude Memory `fetcher_output_dirs.md` で上書き可、既存fetcherと同じ運用） |
| 出力形式 | OKF形式Markdown（type/title/resource/tags/timestamp frontmatter） |

## アーキテクチャ

取得経路はslack-fetcherと同じ二段構え。

1. **MCP経路**: `mcp__claude_ai_Gmail__search_threads` で検索し、結果一覧を会話内に提示する。ユーザーが選んだスレッドについて `mcp__claude_ai_Gmail__get_thread`（`messageFormat=FULL_CONTENT`）を呼び、返ってきたJSONを一切加工せずscratchpadにファイルとして書き出す。
2. **ADCフォールバック経路**: MCP連携が使えない場合、`gcloud auth application-default login` に `gmail.readonly` スコープを追加認可した上で、`gmail_fetcher.py` がGmail API（`users.threads.list` / `users.threads.get`）を直接叩く。

**Markdown整形はどちらの経路でも `gmail_fetcher.py` が担う。** MCP経路ではscratchpadに保存したJSONを `--mcp-json` オプションでスクリプトに渡し、フォールバック経路ではスクリプト自身がAPIレスポンスから同じ変換ロジックを通す。Claudeが自分でMCPの戻り値を解析・Markdown化することは禁止する（slack-fetcherの設計方針を踏襲）。

## コンポーネント

### `skills/gmail-fetcher/scripts/gmail_fetcher.py`

3つの実行モードを持つ。

- `--search "<Gmail構文クエリ>" [--page-size N]`
  ADCフォールバック時の検索。Gmail APIの`threads.list`を叩き、件名・送信者・日付・スニペットを整形したテキストをstdoutに出す。Claudeはこの出力をそのまま会話内に転記する（自分で加工しない）。
- `--mcp-json <path> [<path> ...] -o <dir>`
  MCP経路で取得した`get_thread`の生JSON（1スレッド1ファイル）を読み込み、Markdown化して保存する。
- `<thread_id> [<thread_id> ...] -o <dir>`
  ADCフォールバック時、指定したthreadIdをGmail APIから直接取得しMarkdown化して保存する（他fetcherと同じ複数ID対応）。

いずれのモードも最終的に共通の「スレッドデータ構造 → Markdown」変換関数を通る。

## データフロー（SKILL.md Step構成）

既存fetcherと同じStep1〜5構成に、検索フェーズを追加する。

1. **検索クエリの特定**: ユーザーの自然言語指示をGmail検索構文に変換する（例:「先週の田中さんからのメール」→`from:tanaka after:2026/07/03`）。threadIdやGmail URLが既知の場合はそれを直接使い、検索をスキップしてよい。
2. **出力先ディレクトリの確認**: Claude Memory `fetcher_output_dirs.md`を確認、無ければ`docs/gmail`
3. **取得経路の判定**: MCPのGmail連携が使えるか確認（`search_threads`呼び出しの成否で判定）→使えなければADC認証状況を確認
4. **検索の実行と選択**
   - MCP経路: `search_threads`で検索→会話内に一覧提示→ユーザーが対象スレッドを選択
   - ADC経路: `gmail_fetcher.py --search`で検索→出力をそのまま会話内に提示→ユーザーが対象スレッドを選択
5. **詳細取得と保存**
   - MCP経路: 選択された各threadIdについて`get_thread(FULL_CONTENT)`→JSONをscratchpadに保存→`gmail_fetcher.py --mcp-json`でMarkdown化
   - ADC経路: `gmail_fetcher.py <thread_id> ... -o <dir>`で直接取得・保存
6. **結果報告**: 保存先パスをユーザーに報告。失敗時はスレッドID・権限・認証状態を疑う旨を共有

## 出力形式

```markdown
---
type: gmail-thread
title: <件名>
resource: <Gmail permalink または threadId>
tags: [gmail, thread]
timestamp: <取得日時>
---

## メッセージ 1
- From: ...
- To: ...
- Date: ...

<本文（plaintext）>

添付: xxx.pdf

---

## メッセージ 2
...
```

- `resource`はGmail permalink（`https://mail.google.com/mail/u/0/#all/<threadId>`形式）が導出できる場合はそれを使い、できなければthreadIdをそのまま記載する
- 添付ファイルは本文末尾に「添付: ファイル名」の形式で列挙するのみ（実データは扱わない）
- 既存ファイルは上書き。再取得時も同じコマンドを再実行すればよい

## エラーハンドリング

- Gmail API呼び出し失敗（HTTPError）: warningログを出しスキップ、`{"saved": N, "skipped": M}`の統計を出力。スキップがあれば非ゼロ終了（既存fetcherと同一パターン）
- ADC認証エラー（`DefaultCredentialsError`/`RefreshError`）: 再ログインコマンド（`gmail.readonly`スコープ付き）を提示しexit(1)
- 検索結果0件: エラーではなくその旨をログ出力して正常終了

## テスト方針

- `tests/skills/test_gmail_fetcher.py`でネットワークを伴わない純粋関数をpytestでユニットテストする
  - MCP JSON（get_thread構造）→Markdown変換
  - frontmatter生成
  - ファイル名生成（threadId基準のサニタイズ）
  - Gmail permalink導出ロジック
- ネットワークアクセスを伴う関数（`search_threads`呼び出し、`threads.get`呼び出し）自体はテスト対象外（既存fetcherと同じ割り切り）
- 実装はTDD（Red-Green-Refactor）で進める

## 検証方法

1. MCP経路: 適当な検索クエリで一覧が会話内に提示され、選択したスレッドが`docs/gmail/{threadId}.md`として保存されること
2. ADCフォールバック経路: MCP未接続を模した状態で`--search`が一覧を出し、`<thread_id>`指定で同じ形式のMarkdownが保存されること
3. 存在しないthreadId指定時にスキップされ、統計と終了コードに反映されること
4. 同じスレッドを再取得した際に上書きされること
