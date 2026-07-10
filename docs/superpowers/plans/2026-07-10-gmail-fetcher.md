# Gmail Fetcher スキル新設 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gmailスレッドを検索・取得し、OKF形式のMarkdownとして保存する `gmail-fetcher` スキルを新設する。

**Architecture:** MCP優先（`mcp__claude_ai_Gmail__search_threads` / `get_thread`）＋ADCフォールバック（Gmail API直叩き）の二段構え。Markdown整形は常に `gmail_fetcher.py` が担い、MCP経路・ADC経路のどちらのデータも共通の内部形式（NormalizedMessage）に正規化してから同じ書き込み関数を通す。

**Tech Stack:** Python 3.12+ / `uv run` 単一ファイルスクリプト / `requests` / `google-auth`（ADCフォールバックのみ）/ `pytest`（ユニットテスト）

## Global Constraints

- スクリプトは `#!/usr/bin/env -S uv run` + PEP 723 インラインメタデータ形式（既存fetcher群と同一）
- 依存バージョンは `requests==2.32.3`, `google-auth==2.35.0`（spreadsheet-fetcherと同一バージョンに揃える）
- 出力先デフォルトは `docs/gmail`、既存ファイルは上書き
- OKF frontmatterフィールド: `type` / `title` / `resource` / `tags` / `timestamp`（他fetcherと同一キー構成）
- ファイル名は `{threadId}.md`（`sanitize_filename`でサニタイズ）
- 添付ファイルは実データをダウンロードせず、ファイル名のみ本文に記載
- ネットワークを伴う関数（MCP呼び出し、Gmail API呼び出し）はユニットテスト対象外。純粋関数のみテストする

## 参考にした実データ構造（設計の前提）

`mcp__claude_ai_Gmail__get_thread`（`messageFormat=FULL_CONTENT`）の実際のレスポンス構造を1件確認済み。

```json
{
  "id": "19f498f8341c90fe",
  "messages": [
    {
      "id": "19f498f8341c90fe",
      "date": "2026-07-10T01:06:09Z",
      "sender": "marketing@adjust.com",
      "toRecipients": ["seiji.sawayanagi@dena.jp"],
      "subject": "...",
      "snippet": "...",
      "plaintextBody": "...",
      "htmlBody": "...",
      "labelIds": ["UNREAD", "INBOX"]
    }
  ]
}
```

`attachmentIds`（ツールdescription記載のフィールド名）は今回確認した添付なしメールでは出現しなかった。実装では`.get("attachmentIds", [])`で欠落時に空リストとし、キー名が違っていても添付検出が漏れるだけでエラーにならないようにする。

Gmail API（ADCフォールバック用、`users.threads.get`）は上記と異なり、MIME構造（`payload.headers` / `payload.parts`）で返る標準のGmail APIレスポンスになるため、別途MIME解析が必要。

---

### Task 1: 共通ヘルパー（ファイル名サニタイズ・frontmatter生成）

**Files:**
- Create: `skills/gmail-fetcher/scripts/gmail_fetcher.py`
- Test: `tests/skills/test_gmail_fetcher.py`

**Interfaces:**
- Produces: `sanitize_filename(name: str) -> str`, `_build_frontmatter(fields: dict) -> str`

- [ ] **Step 1: テストディレクトリとスクリプト雛形を作る**

`skills/gmail-fetcher/scripts/gmail_fetcher.py` を以下の内容で新規作成する。

```python
#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "requests==2.32.3",
#   "google-auth==2.35.0",
# ]
# ///

"""Gmailスレッドを検索・取得し、OKF形式のMarkdownファイルに保存する。

■ 取得経路(2段構え)
  1. MCP経路: claude.aiのGmail連携でClaudeが`get_thread`で取得した生JSONを
     無加工でファイル保存し `--mcp-json` で渡す(このモードはネットワークアクセスしない)
  2. ADC経路: Application Default Credentialsを使い、このスクリプトが直接Gmail API
     (`users.threads.list` / `users.threads.get`)を呼んで検索・取得する

■ 使い方
  uv run scripts/gmail_fetcher.py --search "from:tanaka after:2026/07/03"
  uv run scripts/gmail_fetcher.py --mcp-json <thread_id>.json -o docs/gmail
  uv run scripts/gmail_fetcher.py <thread_id> [<thread_id> ...] -o docs/gmail
"""

import argparse
import base64
import json
import logging
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

import requests

logger = logging.getLogger(__name__)

GMAIL_API_BASE = "https://gmail.googleapis.com/gmail/v1"
_SANITIZE_RE = re.compile(r'[\\/:*?"<>|\s]+')


def sanitize_filename(name: str) -> str:
    result = _SANITIZE_RE.sub("_", name).strip("_")
    return result or "untitled"


def _build_frontmatter(fields: dict) -> str:
    """OKF形式のYAML frontmatterを生成する。値はJSONエンコードしてコロン等の混入に耐える。"""
    lines = ["---"]
    for k, v in fields.items():
        lines.append(f"{k}: {json.dumps(v, ensure_ascii=False)}")
    lines.append("---")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    pass
```

- [ ] **Step 2: 失敗するテストを書く**

`tests/skills/test_gmail_fetcher.py` を新規作成する。

```python
#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "pytest==8.4.2",
#   "requests==2.32.3",
# ]
# ///

"""gmail_fetcher.py のユニットテスト（正規化・MIME解析・frontmatter・書き込みsmoke）。"""

import importlib.util
import json
import sys
from pathlib import Path

import pytest
import requests

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "skills" / "gmail-fetcher" / "scripts" / "gmail_fetcher.py"

spec = importlib.util.spec_from_file_location("gmail_fetcher", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


# --- sanitize_filename ---


def test_sanitize_filename_replaces_special_chars():
    assert mod.sanitize_filename("a/b:c") == "a_b_c"


def test_sanitize_filename_empty_becomes_untitled():
    assert mod.sanitize_filename("   ") == "untitled"


# --- _build_frontmatter ---


def test_build_frontmatter_basic():
    fm = mod._build_frontmatter({"type": "gmail-thread", "tags": ["gmail", "thread"]})
    assert fm.startswith("---\n")
    assert fm.endswith("---\n")
    assert '"gmail-thread"' in fm
    assert '["gmail", "thread"]' in fm


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-q"]))
```

- [ ] **Step 3: テストを実行して通ることを確認する**

Run: `uv run tests/skills/test_gmail_fetcher.py`
Expected: `2 passed`（Step 1で雛形に実装済みのため、この時点で既にPASSする）

- [ ] **Step 4: コミット**

```bash
git add skills/gmail-fetcher/scripts/gmail_fetcher.py tests/skills/test_gmail_fetcher.py
git commit -m "feat(gmail-fetcher): add filename sanitize and frontmatter helpers"
```

---

### Task 2: MCP JSON → 内部形式（NormalizedMessage）への正規化

**Files:**
- Modify: `skills/gmail-fetcher/scripts/gmail_fetcher.py`
- Test: `tests/skills/test_gmail_fetcher.py`

**Interfaces:**
- Consumes: なし（MCPの生JSON構造を直接扱う）
- Produces: `normalize_mcp_thread(data: dict) -> list[dict]`。各要素（NormalizedMessage）は `{"id": str, "date": str, "sender": str, "to": list[str], "subject": str, "body": str, "attachments": list[str]}`

- [ ] **Step 1: 失敗するテストを書く**

`tests/skills/test_gmail_fetcher.py` に追記する。

```python
# --- normalize_mcp_thread ---

MCP_THREAD_JSON = {
    "id": "19f498f8341c90fe",
    "messages": [
        {
            "id": "19f498f8341c90fe",
            "date": "2026-07-10T01:06:09Z",
            "sender": "marketing@adjust.com",
            "toRecipients": ["seiji.sawayanagi@dena.jp"],
            "subject": "件名テスト",
            "snippet": "スニペット",
            "plaintextBody": "本文テスト\n2行目",
            "htmlBody": "<html>...</html>",
            "labelIds": ["UNREAD", "INBOX"],
        }
    ],
}


def test_normalize_mcp_thread_basic():
    messages = mod.normalize_mcp_thread(MCP_THREAD_JSON)
    assert len(messages) == 1
    msg = messages[0]
    assert msg["id"] == "19f498f8341c90fe"
    assert msg["date"] == "2026-07-10T01:06:09Z"
    assert msg["sender"] == "marketing@adjust.com"
    assert msg["to"] == ["seiji.sawayanagi@dena.jp"]
    assert msg["subject"] == "件名テスト"
    assert msg["body"] == "本文テスト\n2行目"
    assert msg["attachments"] == []


def test_normalize_mcp_thread_falls_back_to_snippet_when_no_plaintext_body():
    data = {
        "id": "t1",
        "messages": [
            {
                "id": "m1",
                "date": "2026-07-01T00:00:00Z",
                "sender": "a@example.com",
                "toRecipients": ["b@example.com"],
                "subject": "件名",
                "snippet": "スニペットのみ",
            }
        ],
    }
    messages = mod.normalize_mcp_thread(data)
    assert messages[0]["body"] == "スニペットのみ"


def test_normalize_mcp_thread_includes_attachment_ids_when_present():
    data = {
        "id": "t1",
        "messages": [
            {
                "id": "m1",
                "date": "2026-07-01T00:00:00Z",
                "sender": "a@example.com",
                "toRecipients": [],
                "subject": "件名",
                "plaintextBody": "本文",
                "attachmentIds": ["file1.pdf", "file2.png"],
            }
        ],
    }
    messages = mod.normalize_mcp_thread(data)
    assert messages[0]["attachments"] == ["file1.pdf", "file2.png"]
```

- [ ] **Step 2: テストを実行して失敗を確認する**

Run: `uv run tests/skills/test_gmail_fetcher.py`
Expected: FAIL with `AttributeError: module 'gmail_fetcher' has no attribute 'normalize_mcp_thread'`

- [ ] **Step 3: 最小実装を書く**

`gmail_fetcher.py` の `_build_frontmatter` 関数の直後に追加する。

```python
def normalize_mcp_thread(data: dict) -> list[dict]:
    """MCPの get_thread(FULL_CONTENT) が返す生JSONを内部形式(NormalizedMessage)に変換する。"""
    normalized = []
    for msg in data.get("messages", []):
        body = (msg.get("plaintextBody") or msg.get("snippet") or "").strip()
        normalized.append(
            {
                "id": msg.get("id", ""),
                "date": msg.get("date", ""),
                "sender": msg.get("sender", ""),
                "to": msg.get("toRecipients") or [],
                "subject": msg.get("subject", ""),
                "body": body,
                "attachments": msg.get("attachmentIds") or [],
            }
        )
    return normalized
```

- [ ] **Step 4: テストを実行して通ることを確認する**

Run: `uv run tests/skills/test_gmail_fetcher.py`
Expected: `5 passed`

- [ ] **Step 5: コミット**

```bash
git add skills/gmail-fetcher/scripts/gmail_fetcher.py tests/skills/test_gmail_fetcher.py
git commit -m "feat(gmail-fetcher): normalize MCP get_thread JSON to internal message format"
```

---

### Task 3: Markdown組み立て・書き込み（write_thread）

**Files:**
- Modify: `skills/gmail-fetcher/scripts/gmail_fetcher.py`
- Test: `tests/skills/test_gmail_fetcher.py`

**Interfaces:**
- Consumes: Task1の`sanitize_filename`/`_build_frontmatter`、Task2のNormalizedMessage構造（`list[dict]`、各dictは`id/date/sender/to/subject/body/attachments`キーを持つ）
- Produces: `write_thread(output_dir: Path, thread_id: str, messages: list[dict]) -> Path`

- [ ] **Step 1: 失敗するテストを書く**

```python
# --- write_thread ---


def test_write_thread_smoke(tmp_path):
    messages = mod.normalize_mcp_thread(MCP_THREAD_JSON)
    path = mod.write_thread(tmp_path, "19f498f8341c90fe", messages)
    assert path.name == "19f498f8341c90fe.md"
    content = path.read_text(encoding="utf-8")
    assert content.startswith("---\n")
    assert '"gmail-thread"' in content
    assert '"件名テスト"' in content
    assert "marketing@adjust.com" in content
    assert "本文テスト" in content


def test_write_thread_includes_attachments_line(tmp_path):
    data = {
        "id": "t1",
        "messages": [
            {
                "id": "m1",
                "date": "2026-07-01T00:00:00Z",
                "sender": "a@example.com",
                "toRecipients": ["b@example.com"],
                "subject": "件名",
                "plaintextBody": "本文",
                "attachmentIds": ["file1.pdf"],
            }
        ],
    }
    messages = mod.normalize_mcp_thread(data)
    path = mod.write_thread(tmp_path, "t1", messages)
    content = path.read_text(encoding="utf-8")
    assert "添付: file1.pdf" in content


def test_write_thread_multiple_messages_separated(tmp_path):
    data = {
        "id": "t1",
        "messages": [
            {"id": "m1", "date": "2026-07-01T00:00:00Z", "sender": "a@example.com", "toRecipients": [], "subject": "件名", "plaintextBody": "1通目"},
            {"id": "m2", "date": "2026-07-02T00:00:00Z", "sender": "b@example.com", "toRecipients": [], "subject": "Re: 件名", "plaintextBody": "2通目"},
        ],
    }
    messages = mod.normalize_mcp_thread(data)
    path = mod.write_thread(tmp_path, "t1", messages)
    content = path.read_text(encoding="utf-8")
    assert "## メッセージ 1" in content
    assert "## メッセージ 2" in content
    assert content.index("1通目") < content.index("## メッセージ 2")
```

- [ ] **Step 2: テストを実行して失敗を確認する**

Run: `uv run tests/skills/test_gmail_fetcher.py`
Expected: FAIL with `AttributeError: module 'gmail_fetcher' has no attribute 'write_thread'`

- [ ] **Step 3: 最小実装を書く**

`gmail_fetcher.py` に追加する（`import` 節に `from pathlib import Path` は既に含まれている前提）。

```python
def write_thread(output_dir: Path, thread_id: str, messages: list[dict]) -> Path:
    first = messages[0]
    subject = first["subject"] or "(件名なし)"
    permalink = f"https://mail.google.com/mail/u/0/#all/{thread_id}"

    frontmatter = _build_frontmatter(
        {
            "type": "gmail-thread",
            "title": subject,
            "resource": permalink,
            "tags": ["gmail", "thread"],
            "timestamp": first["date"],
        }
    )

    sections = []
    for i, msg in enumerate(messages, start=1):
        lines = [
            f"## メッセージ {i}",
            f"- From: {msg['sender']}",
            f"- To: {', '.join(msg['to'])}",
            f"- Date: {msg['date']}",
            "",
            msg["body"] or "_(本文なし)_",
        ]
        if msg["attachments"]:
            lines += ["", "添付: " + ", ".join(msg["attachments"])]
        sections.append("\n".join(lines))

    body_text = "\n\n---\n\n".join(sections) + "\n"

    output_dir.mkdir(parents=True, exist_ok=True)
    file_path = output_dir / f"{sanitize_filename(thread_id)}.md"
    file_path.write_text(frontmatter + "\n" + body_text, encoding="utf-8")
    logger.info(f"書き込み完了: {file_path}")
    return file_path
```

- [ ] **Step 4: テストを実行して通ることを確認する**

Run: `uv run tests/skills/test_gmail_fetcher.py`
Expected: `8 passed`

- [ ] **Step 5: コミット**

```bash
git add skills/gmail-fetcher/scripts/gmail_fetcher.py tests/skills/test_gmail_fetcher.py
git commit -m "feat(gmail-fetcher): write normalized messages as OKF markdown"
```

---

### Task 4: CLI `--mcp-json` モード

**Files:**
- Modify: `skills/gmail-fetcher/scripts/gmail_fetcher.py`
- Test: `tests/skills/test_gmail_fetcher.py`

**Interfaces:**
- Consumes: Task2の`normalize_mcp_thread`、Task3の`write_thread`
- Produces: `main()` に `--mcp-json <path> [<path> ...] -o <dir>` 引数群を追加。ネットワークアクセスなしで動作する

- [ ] **Step 1: 失敗するテストを書く**

```python
# --- main --mcp-json ---


def test_main_mcp_json_writes_file(tmp_path, monkeypatch):
    json_path = tmp_path / "19f498f8341c90fe.json"
    json_path.write_text(json.dumps(MCP_THREAD_JSON, ensure_ascii=False), encoding="utf-8")
    out_dir = tmp_path / "out"
    monkeypatch.setattr(
        sys, "argv",
        ["gmail_fetcher.py", "--mcp-json", str(json_path), "-o", str(out_dir)],
    )
    mod.main()
    written = out_dir / "19f498f8341c90fe.md"
    assert written.exists()
    assert '"件名テスト"' in written.read_text(encoding="utf-8")


def test_main_mcp_json_multiple_files(tmp_path, monkeypatch):
    data2 = dict(MCP_THREAD_JSON)
    data2["id"] = "another_thread_id"
    data2["messages"] = [dict(MCP_THREAD_JSON["messages"][0])]
    path1 = tmp_path / "a.json"
    path2 = tmp_path / "b.json"
    path1.write_text(json.dumps(MCP_THREAD_JSON, ensure_ascii=False), encoding="utf-8")
    path2.write_text(json.dumps(data2, ensure_ascii=False), encoding="utf-8")
    out_dir = tmp_path / "out"
    monkeypatch.setattr(
        sys, "argv",
        ["gmail_fetcher.py", "--mcp-json", str(path1), "--mcp-json", str(path2), "-o", str(out_dir)],
    )
    mod.main()
    assert (out_dir / "19f498f8341c90fe.md").exists()
    assert (out_dir / "another_thread_id.md").exists()
```

- [ ] **Step 2: テストを実行して失敗を確認する**

Run: `uv run tests/skills/test_gmail_fetcher.py`
Expected: FAIL with `AttributeError: module 'gmail_fetcher' has no attribute 'main'`

- [ ] **Step 3: 最小実装を書く**

`gmail_fetcher.py` 末尾の `if __name__ == "__main__": pass` を以下に置き換える。

```python
def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    parser = argparse.ArgumentParser(
        description="Gmailスレッドを検索・取得し、OKF形式のMarkdownとして保存する。",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "例:\n"
            "  uv run scripts/gmail_fetcher.py --search \"from:tanaka after:2026/07/03\"\n"
            "  uv run scripts/gmail_fetcher.py --mcp-json thread.json -o docs/gmail\n"
            "  uv run scripts/gmail_fetcher.py <thread_id> -o docs/gmail\n"
        ),
    )
    parser.add_argument("thread_ids", nargs="*", metavar="THREAD_ID", help="ADC経由で直接取得するスレッドID(複数指定可)")
    parser.add_argument("-o", "--output", metavar="DIR", default="docs/gmail", help="OKF出力先ディレクトリ（デフォルト: docs/gmail）")
    parser.add_argument(
        "--mcp-json",
        action="append",
        metavar="PATH",
        default=None,
        help="MCPのget_thread結果を無加工保存したJSONファイル(複数指定可)。指定時はTHREAD_IDは無視する",
    )
    parser.add_argument("--search", metavar="QUERY", default=None, help="ADC経由でGmail検索クエリを実行し、結果一覧をstdoutに出力して終了する")
    parser.add_argument("--page-size", type=int, default=20, help="--search時の最大取得件数（デフォルト: 20）")
    args = parser.parse_args()

    output_dir = Path(args.output)

    if args.mcp_json:
        saved = 0
        for json_path in args.mcp_json:
            try:
                data = json.loads(Path(json_path).read_text(encoding="utf-8"))
                messages = normalize_mcp_thread(data)
                if not messages:
                    raise ValueError("messagesが空です")
                write_thread(output_dir, data.get("id", Path(json_path).stem), messages)
                saved += 1
            except (OSError, ValueError, KeyError) as e:
                logger.warning(f"スレッド書き込み失敗: {json_path}: {e}, スキップ")
        logger.info(f"完了: {saved}/{len(args.mcp_json)} 件保存")
        if saved < len(args.mcp_json):
            sys.exit(1)
        return


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: テストを実行して通ることを確認する**

Run: `uv run tests/skills/test_gmail_fetcher.py`
Expected: `10 passed`

- [ ] **Step 5: コミット**

```bash
git add skills/gmail-fetcher/scripts/gmail_fetcher.py tests/skills/test_gmail_fetcher.py
git commit -m "feat(gmail-fetcher): add --mcp-json CLI mode"
```

---

### Task 5: ADC認証セットアップ + Gmail API検索一覧（`--search`）

**Files:**
- Modify: `skills/gmail-fetcher/scripts/gmail_fetcher.py`
- Test: `tests/skills/test_gmail_fetcher.py`

**Interfaces:**
- Produces: `get_header(headers: list[dict], name: str) -> str | None`、`format_search_results(results: list[dict]) -> str`
- ネットワーク関数（`_make_session()`, `search_threads_via_api()`）もこのタスクで追加するが、テスト対象は`get_header`と`format_search_results`のみ

- [ ] **Step 1: 失敗するテストを書く**

```python
# --- get_header ---


def test_get_header_case_insensitive():
    headers = [{"name": "Subject", "value": "件名"}, {"name": "From", "value": "a@example.com"}]
    assert mod.get_header(headers, "subject") == "件名"
    assert mod.get_header(headers, "From") == "a@example.com"
    assert mod.get_header(headers, "Cc") is None


# --- format_search_results ---


def test_format_search_results_empty():
    assert mod.format_search_results([]) == "該当するスレッドはありません"


def test_format_search_results_basic():
    results = [
        {"id": "t1", "subject": "件名1", "sender": "a@example.com", "date": "2026-07-01", "snippet": "スニペット1"},
    ]
    text = mod.format_search_results(results)
    assert "[t1]" in text
    assert "件名1" in text
    assert "a@example.com" in text
    assert "スニペット1" in text
```

- [ ] **Step 2: テストを実行して失敗を確認する**

Run: `uv run tests/skills/test_gmail_fetcher.py`
Expected: FAIL with `AttributeError: module 'gmail_fetcher' has no attribute 'get_header'`

- [ ] **Step 3: 最小実装を書く**

`gmail_fetcher.py` の先頭 import 節を以下に置き換える（`google-auth`関連の追加インポート）。

```python
import argparse
import base64
import json
import logging
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

import requests
from google.auth import default as google_auth_default
from google.auth.exceptions import DefaultCredentialsError, RefreshError
from google.auth.transport.requests import AuthorizedSession
```

`write_thread` 関数の後に以下を追加する。

```python
def get_header(headers: list[dict], name: str) -> str | None:
    for h in headers:
        if h.get("name", "").lower() == name.lower():
            return h.get("value")
    return None


def format_search_results(results: list[dict]) -> str:
    if not results:
        return "該当するスレッドはありません"
    lines = []
    for r in results:
        lines.append(f"[{r['id']}] {r['subject']}\n  From: {r['sender']} / Date: {r['date']}\n  {r['snippet']}")
    return "\n\n".join(lines)


def _make_session() -> requests.Session:
    try:
        credentials, _ = google_auth_default()
    except DefaultCredentialsError as e:
        logger.error(
            "Application Default Credentials の取得に失敗しました。"
            '`gcloud auth application-default login --scopes '
            '"https://www.googleapis.com/auth/gmail.readonly"` '
            f"を実行してください: {e}"
        )
        sys.exit(1)
    return AuthorizedSession(credentials)


def search_threads_via_api(session: requests.Session, query: str, page_size: int) -> list[dict]:
    resp = session.get(f"{GMAIL_API_BASE}/users/me/threads", params={"q": query, "maxResults": page_size})
    resp.raise_for_status()
    thread_stubs = resp.json().get("threads", [])

    results = []
    for stub in thread_stubs:
        detail_resp = session.get(
            f"{GMAIL_API_BASE}/users/me/threads/{stub['id']}",
            params={"format": "metadata", "metadataHeaders": ["Subject", "From", "Date"]},
        )
        detail_resp.raise_for_status()
        thread = detail_resp.json()
        first_msg = thread["messages"][0]
        headers = (first_msg.get("payload") or {}).get("headers") or []
        results.append(
            {
                "id": stub["id"],
                "subject": get_header(headers, "Subject") or "",
                "sender": get_header(headers, "From") or "",
                "date": get_header(headers, "Date") or "",
                "snippet": stub.get("snippet", ""),
            }
        )
    return results
```

- [ ] **Step 4: テストを実行して通ることを確認する**

Run: `uv run tests/skills/test_gmail_fetcher.py`
Expected: `13 passed`

- [ ] **Step 5: コミット**

```bash
git add skills/gmail-fetcher/scripts/gmail_fetcher.py tests/skills/test_gmail_fetcher.py
git commit -m "feat(gmail-fetcher): add ADC session and Gmail API search"
```

---

### Task 6: Gmail API MIME解析（本文・添付ファイル抽出）

**Files:**
- Modify: `skills/gmail-fetcher/scripts/gmail_fetcher.py`
- Test: `tests/skills/test_gmail_fetcher.py`

**Interfaces:**
- Consumes: なし（Gmail API標準の`payload`構造を直接扱う）
- Produces: `extract_plaintext_and_attachments(payload: dict) -> tuple[str, list[str]]`、`normalize_api_message(msg: dict) -> dict`（Task2と同じNormalizedMessage形式を返す）

- [ ] **Step 1: 失敗するテストを書く**

```python
# --- extract_plaintext_and_attachments ---


def _b64(text: str) -> str:
    return base64.urlsafe_b64encode(text.encode("utf-8")).decode("ascii")


def test_extract_plaintext_and_attachments_simple_text():
    payload = {"mimeType": "text/plain", "body": {"data": _b64("本文です")}}
    body, attachments = mod.extract_plaintext_and_attachments(payload)
    assert body == "本文です"
    assert attachments == []


def test_extract_plaintext_and_attachments_multipart_with_attachment():
    payload = {
        "mimeType": "multipart/mixed",
        "parts": [
            {
                "mimeType": "multipart/alternative",
                "parts": [
                    {"mimeType": "text/plain", "body": {"data": _b64("プレーン本文")}},
                    {"mimeType": "text/html", "body": {"data": _b64("<p>HTML本文</p>")}},
                ],
            },
            {"mimeType": "application/pdf", "filename": "report.pdf", "body": {"attachmentId": "AAA"}},
        ],
    }
    body, attachments = mod.extract_plaintext_and_attachments(payload)
    assert body == "プレーン本文"
    assert attachments == ["report.pdf"]


# --- normalize_api_message ---


def test_normalize_api_message_basic():
    msg = {
        "id": "m1",
        "internalDate": "1751500000000",
        "payload": {
            "headers": [
                {"name": "From", "value": "a@example.com"},
                {"name": "To", "value": "b@example.com"},
                {"name": "Subject", "value": "件名テスト"},
            ],
            "mimeType": "text/plain",
            "body": {"data": _b64("本文テスト")},
        },
    }
    normalized = mod.normalize_api_message(msg)
    assert normalized["id"] == "m1"
    assert normalized["sender"] == "a@example.com"
    assert normalized["to"] == ["b@example.com"]
    assert normalized["subject"] == "件名テスト"
    assert normalized["body"] == "本文テスト"
    assert normalized["attachments"] == []
    assert normalized["date"].endswith("Z")
```

- [ ] **Step 2: テストを実行して失敗を確認する**

Run: `uv run tests/skills/test_gmail_fetcher.py`
Expected: FAIL with `AttributeError: module 'gmail_fetcher' has no attribute 'extract_plaintext_and_attachments'`

- [ ] **Step 3: 最小実装を書く**

`gmail_fetcher.py` の `get_header` 関数の直前に追加する。

```python
def _decode_body_data(data: str) -> str:
    padded = data + "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(padded).decode("utf-8", errors="replace")


def extract_plaintext_and_attachments(payload: dict) -> tuple[str, list[str]]:
    """MIME構造を再帰的に走査し、text/plainパートの本文をすべて連結したものと添付ファイル名一覧を返す。"""
    plaintext_parts: list[str] = []
    attachments: list[str] = []

    def walk(part: dict) -> None:
        mime_type = part.get("mimeType", "")
        filename = part.get("filename") or ""
        body = part.get("body") or {}
        if filename:
            attachments.append(filename)
        elif mime_type == "text/plain" and body.get("data"):
            plaintext_parts.append(_decode_body_data(body["data"]))
        for sub_part in part.get("parts") or []:
            walk(sub_part)

    walk(payload)
    return "\n".join(plaintext_parts), attachments


def normalize_api_message(msg: dict) -> dict:
    """Gmail API(`users.threads.get`)の生メッセージを内部形式(NormalizedMessage)に変換する。"""
    payload = msg.get("payload") or {}
    headers = payload.get("headers") or []
    body, attachments = extract_plaintext_and_attachments(payload)
    internal_date_ms = int(msg.get("internalDate", "0"))
    date_iso = datetime.fromtimestamp(internal_date_ms / 1000, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    to_header = get_header(headers, "To") or ""
    return {
        "id": msg.get("id", ""),
        "date": date_iso,
        "sender": get_header(headers, "From") or "",
        "to": [addr.strip() for addr in to_header.split(",") if addr.strip()],
        "subject": get_header(headers, "Subject") or "",
        "body": body.strip(),
        "attachments": attachments,
    }
```

- [ ] **Step 4: テストを実行して通ることを確認する**

Run: `uv run tests/skills/test_gmail_fetcher.py`
Expected: `16 passed`

- [ ] **Step 5: コミット**

```bash
git add skills/gmail-fetcher/scripts/gmail_fetcher.py tests/skills/test_gmail_fetcher.py
git commit -m "feat(gmail-fetcher): parse Gmail API MIME payload into normalized messages"
```

---

### Task 7: CLI `--search` / ADCフォールバックのスレッド取得モード（main完成）

**Files:**
- Modify: `skills/gmail-fetcher/scripts/gmail_fetcher.py`
- Test: `tests/skills/test_gmail_fetcher.py`

**Interfaces:**
- Consumes: Task5の`_make_session`/`search_threads_via_api`/`format_search_results`、Task6の`normalize_api_message`、Task3の`write_thread`
- Produces: `main()`の`--search`モードと`<thread_id> ... -o <dir>`モードの完全実装。`fetch_thread_via_api(session, thread_id) -> dict`も追加

- [ ] **Step 1: 失敗するテストを書く**

ADCフォールバックのネットワーク関数（`_make_session`, `search_threads_via_api`, `fetch_thread_via_api`）はテスト対象外方針のため、`main()`の分岐が正しくディスパッチされることのみ確認する。ネットワーク呼び出しは`monkeypatch`で差し替える。

```python
# --- main --search / THREAD_ID dispatch ---


def test_main_search_calls_search_and_prints(monkeypatch, capsys):
    monkeypatch.setattr(mod, "_make_session", lambda: object())
    monkeypatch.setattr(
        mod, "search_threads_via_api",
        lambda session, query, page_size: [{"id": "t1", "subject": "件名", "sender": "a@example.com", "date": "2026-07-01", "snippet": "snip"}],
    )
    monkeypatch.setattr(sys, "argv", ["gmail_fetcher.py", "--search", "from:a"])
    mod.main()
    out = capsys.readouterr().out
    assert "[t1]" in out
    assert "件名" in out


def test_main_thread_ids_fetches_and_writes(tmp_path, monkeypatch):
    api_thread = {
        "id": "t1",
        "messages": [
            {
                "id": "m1",
                "internalDate": "1751500000000",
                "payload": {
                    "headers": [
                        {"name": "From", "value": "a@example.com"},
                        {"name": "To", "value": "b@example.com"},
                        {"name": "Subject", "value": "APIスレッド"},
                    ],
                    "mimeType": "text/plain",
                    "body": {"data": _b64("API本文")},
                },
            }
        ],
    }
    monkeypatch.setattr(mod, "_make_session", lambda: object())
    monkeypatch.setattr(mod, "fetch_thread_via_api", lambda session, thread_id: api_thread)
    out_dir = tmp_path / "out"
    monkeypatch.setattr(sys, "argv", ["gmail_fetcher.py", "t1", "-o", str(out_dir)])
    mod.main()
    written = out_dir / "t1.md"
    assert written.exists()
    assert "APIスレッド" in written.read_text(encoding="utf-8")


def test_main_thread_ids_skips_failed_and_exits_nonzero(tmp_path, monkeypatch):
    def _raise(session, thread_id):
        raise requests.HTTPError("404")

    monkeypatch.setattr(mod, "_make_session", lambda: object())
    monkeypatch.setattr(mod, "fetch_thread_via_api", _raise)
    out_dir = tmp_path / "out"
    monkeypatch.setattr(sys, "argv", ["gmail_fetcher.py", "missing_id", "-o", str(out_dir)])
    with pytest.raises(SystemExit) as exc_info:
        mod.main()
    assert exc_info.value.code == 1
```

- [ ] **Step 2: テストを実行して失敗を確認する**

Run: `uv run tests/skills/test_gmail_fetcher.py`
Expected: FAIL（`--search`は現状`main()`内で未処理のため引数解析はできるが分岐がなく何も出力されない。`t1`等の位置引数モードも未実装のため`AttributeError: module 'gmail_fetcher' has no attribute 'fetch_thread_via_api'`を含め失敗する）

- [ ] **Step 3: 最小実装を書く**

`gmail_fetcher.py` の`search_threads_via_api`関数の後に追加する。

```python
def fetch_thread_via_api(session: requests.Session, thread_id: str) -> dict:
    resp = session.get(f"{GMAIL_API_BASE}/users/me/threads/{thread_id}", params={"format": "full"})
    resp.raise_for_status()
    return resp.json()
```

`main()`内の`if args.mcp_json: ... return`ブロックの直後（`return`の後、関数末尾の前）に以下を追加する。

```python
    if args.search is not None:
        session = _make_session()
        try:
            results = search_threads_via_api(session, args.search, args.page_size)
        except RefreshError as e:
            logger.error(f"ADCの認証が無効です。再ログインしてください: {e}")
            sys.exit(1)
        print(format_search_results(results))
        return

    if not args.thread_ids:
        parser.error("THREAD_ID, --mcp-json, --search のいずれかを指定してください")

    session = _make_session()
    fetched = []
    try:
        for thread_id in args.thread_ids:
            try:
                data = fetch_thread_via_api(session, thread_id)
                messages = [normalize_api_message(m) for m in data.get("messages", [])]
                if not messages:
                    raise ValueError("messagesが空です")
                write_thread(output_dir, thread_id, messages)
                fetched.append(thread_id)
            except (requests.HTTPError, ValueError, KeyError) as e:
                logger.warning(f"スレッド取得失敗: {thread_id}: {e}, スキップ")
    except RefreshError as e:
        logger.error(f"ADCの認証が無効です。再ログインしてください: {e}")
        sys.exit(1)

    logger.info(f"完了: {len(fetched)}/{len(args.thread_ids)} 件取得")
    if len(fetched) < len(args.thread_ids):
        sys.exit(1)
```

`RefreshError`は`google.auth.exceptions`からのimportで、Task5で追加済みの`import`節に含まれている（`DefaultCredentialsError`と同じ行）。

- [ ] **Step 4: テストを実行して通ることを確認する**

Run: `uv run tests/skills/test_gmail_fetcher.py`
Expected: `19 passed`

- [ ] **Step 5: コミット**

```bash
git add skills/gmail-fetcher/scripts/gmail_fetcher.py tests/skills/test_gmail_fetcher.py
git commit -m "feat(gmail-fetcher): complete CLI with --search and ADC thread fetch modes"
```

---

### Task 8: `skills/gmail-fetcher/SKILL.md` 作成

**Files:**
- Create: `skills/gmail-fetcher/SKILL.md`

**Interfaces:**
- Consumes: Task1〜7で完成した`gmail_fetcher.py`のCLI引数（`--search`, `--mcp-json`, `<thread_id>...`, `-o`）
- Produces: なし（Markdownドキュメントのみ、コードからは独立）

- [ ] **Step 1: SKILL.mdを作成する**

`skills/gmail-fetcher/SKILL.md` を以下の内容で新規作成する（既存fetcher群、特に`slack-fetcher/SKILL.md`のStep構成を踏襲）。

```markdown
---
name: gmail-fetcher
description: >
  Gmailのメールスレッドを検索・取得しOKF形式のMarkdownとして保存する。
  claude.aiのGmail連携（未接続時はADC経由のGmail API）を使い、検索クエリまたはthreadIdから
  スレッド本文・送信者・宛先・日時を取得し保存する。
  「Gmailでこのメール探して」「田中さんからのメールを取得して」「このスレッドの内容を確認して」
  といった依頼で必ずこのスキルを使う。
allowed-tools: Bash(uv run .claude/skills/gmail-fetcher/scripts/gmail_fetcher.py:*) Bash(uv run scripts/gmail_fetcher.py:*) Bash(gcloud auth application-default print-access-token:*) Bash(gcloud auth application-default login:*) mcp__claude_ai_Gmail__search_threads mcp__claude_ai_Gmail__get_thread Write Read AskUserQuestion
---

# Gmail Fetcher スキル

`.claude/skills/gmail-fetcher/scripts/gmail_fetcher.py` を使い、Gmailスレッド（メッセージ本文・送信者・宛先・日時）をOKF形式（frontmatter付き）のMarkdownとして保存する。

**コマンドは必ずリポジトリルートから、上記のリポジトリルート相対パスで実行する。** `cd` はしない。

取得経路は2段構え。**claude.aiのGmail連携（MCPツール）を優先し、使えない場合のみADC（Application Default Credentials）経由でGmail APIを直接叩く。** どちらの経路でも出力されるMarkdownの形式は同一。

検索結果一覧はファイル保存せず会話内に提示するのみ。ユーザーが選んだスレッドだけを取得・保存する。

## Step 1: 検索クエリまたは対象スレッドの特定

- ユーザーの自然言語の依頼をGmail検索構文に変換する（例:「先週の田中さんからのメール」→`from:tanaka after:2026/07/03`）。演算子は`from:` `to:` `subject:` `after:` `before:` `has:attachment` `is:unread`等（詳細はMCPツールの`search_threads`説明を参照）
- 既にthreadIdが分かっている場合は検索をスキップし、Step 3の詳細取得に直接進んでよい

## Step 2: 出力先ディレクトリの確認

1. Claude Memoryの `fetcher_output_dirs.md` を確認し、gmail-fetcherの行にユーザー指定の出力先が記録されていればそれを使う
2. 記録が無く、今回の会話からも出力先の指定が読み取れない場合は `docs/gmail`（リポジトリルート相対）を使う
3. 会話でユーザーが出力先を指定した場合は、その値を使うと同時に `fetcher_output_dirs.md` のgmail-fetcherの行を更新して記憶する

## Step 3: 取得経路の判定・検索の実行

1. まず `mcp__claude_ai_Gmail__search_threads` を軽いクエリで呼んでみる。成功すれば **MCP経路**
2. 失敗する、またはツールが使えない場合は **ADCフォールバック経路**。ADCの認証状態を確認する
   ```bash
   gcloud auth application-default print-access-token >/dev/null 2>&1 && echo "ADC set: yes" || echo "ADC set: no"
   ```
   `ADC set: no` の場合、ユーザーに以下の実行を依頼する（`gmail.readonly`スコープが必要）
   ```bash
   gcloud auth application-default login \
     --scopes "https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/gmail.readonly"
   ```

### Step 3-A: MCP経路での検索

`search_threads(query=<Gmail構文>, pageSize=20, view="THREAD_VIEW_MINIMAL")` を呼び、返ってきた各スレッドの件名・送信者・日付・スニペットを会話内に一覧として提示する。ユーザーが対象スレッドを選ぶまでファイル保存はしない。

### Step 3-B: ADC経路での検索

```bash
uv run .claude/skills/gmail-fetcher/scripts/gmail_fetcher.py --search "<Gmail構文クエリ>" [--page-size 20]
```

出力される一覧をそのまま会話内に提示する（自分で加工しない）。ユーザーが対象スレッドを選ぶまでファイル保存はしない。

## Step 4: 詳細取得と保存

### Step 4-A: MCP経路

選択された各threadIdについて `get_thread(threadId, messageFormat="FULL_CONTENT")` を呼ぶ。**返ってきたJSONは自分で解析・整形せず**、セッションのscratchpadディレクトリ配下（無い環境では `/tmp` 配下）に `<threadId>.json` としてそのまま `Write` する。その後、以下を実行する。

```bash
uv run .claude/skills/gmail-fetcher/scripts/gmail_fetcher.py --mcp-json <threadId>.json [--mcp-json <threadId2>.json ...] -o <output-dir>
```

### Step 4-B: ADC経路

```bash
uv run .claude/skills/gmail-fetcher/scripts/gmail_fetcher.py <thread_id> [<thread_id> ...] -o <output-dir>
```

## Step 5: 結果報告

コマンド出力の `書き込み完了: <path>` からファイルパスを確認し、保存先をユーザーに報告する。`スレッド取得失敗` / `スレッド書き込み失敗` のログが出た場合は、threadIdの正しさ・MCP連携の認可状態・ADCの認証状態・対象メールへのアクセス権限を疑いユーザーに共有する。

## 補足

- 出力先ディレクトリには `{threadId}.md`（スレッドごとに1ファイル）が生成される
- 出力Markdownの先頭には `type` / `title`（件名）/ `resource`（Gmail permalink）/ `tags`（`gmail`, `thread`）/ `timestamp`（先頭メッセージの日時）の frontmatter が自動で付与される
- 添付ファイルは実データをダウンロードせず、本文中に「添付: ファイル名」として記載するのみ
- 既存ファイルは上書きされる。再取得（最新化）したい場合もそのまま同じコマンドを再実行すればよい
- 検索結果一覧そのものの保存、メール送信・下書き作成・ラベル付与などの書き込み系操作はこのスキルの対象外
```

- [ ] **Step 2: コミット**

```bash
git add skills/gmail-fetcher/SKILL.md
git commit -m "docs(gmail-fetcher): add SKILL.md"
```

---

### Task 9: 全体テスト実行と最終確認

**Files:**
- なし（検証のみ）

**Interfaces:**
- Consumes: Task1〜8の全成果物

- [ ] **Step 1: ユニットテスト全体を実行する**

Run: `uv run tests/skills/test_gmail_fetcher.py`
Expected: `19 passed`（Task1〜7で積み上げた全テストがpassすること）

- [ ] **Step 2: `--mcp-json` モードの手動smokeを実行する**

```bash
mkdir -p /tmp/gmail-fetcher-smoke
cat > /tmp/gmail-fetcher-smoke/test.json <<'EOF'
{"id": "smoke_test_id", "messages": [{"id": "m1", "date": "2026-07-10T00:00:00Z", "sender": "smoke@example.com", "toRecipients": ["me@example.com"], "subject": "smoke test", "plaintextBody": "これはsmokeテストです"}]}
EOF
uv run skills/gmail-fetcher/scripts/gmail_fetcher.py --mcp-json /tmp/gmail-fetcher-smoke/test.json -o /tmp/gmail-fetcher-smoke/out
cat /tmp/gmail-fetcher-smoke/out/smoke_test_id.md
```

Expected: `smoke_test_id.md` が生成され、frontmatterと「これはsmokeテストです」を含む内容が表示される

- [ ] **Step 3: 後片付け**

```bash
rm -rf /tmp/gmail-fetcher-smoke
```

- [ ] **Step 4: SKILL.mdの`allowed-tools`とdescriptionが実装と一致しているか目視確認する**

`skills/gmail-fetcher/SKILL.md` の frontmatter を読み、`gmail_fetcher.py` の実際の引数（`--search`, `--mcp-json`, `-o`, `--page-size`, 位置引数`thread_ids`）とStep記載のコマンド例が一致していることを確認する。不一致があれば修正してコミットする。
