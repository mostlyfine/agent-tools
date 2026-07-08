#!/usr/bin/env python3
"""BATS テストから Python 純粋関数を呼び出すラッパー。

使用例:
  python3 test_helper.py claude_task "✺ Claude Code doing work"
  python3 test_helper.py claude_status "✺ idle" ""
  python3 test_helper.py is_claude_pane "1.3.0" ""
"""
import importlib.machinery
import importlib.util
import os
import sys

_SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../scripts/agent-ps")

loader = importlib.machinery.SourceFileLoader("agent_ps", _SCRIPT)
spec = importlib.util.spec_from_loader("agent_ps", loader)
mod = importlib.util.module_from_spec(spec)
sys.modules["agent_ps"] = mod
loader.exec_module(mod)

def _classify_key_hex(hex_str):
    result = mod._classify_key(bytes.fromhex(hex_str))
    if isinstance(result, tuple):
        return ":".join(str(part) for part in result)
    return result


def _build_panes(pane_ids_csv):
    return [
        mod.Pane(agent="claude", pane_id_num=pid, status="idle", task="", dir="")
        for pid in pane_ids_csv.split(",")
        if pid
    ]


def _pane_at_row(horizontal_flag, row, pane_ids_csv):
    panes = _build_panes(pane_ids_csv)
    return mod._pane_at_row(panes, int(row), horizontal_flag == "1")


def _handle_click(cy, pane_ids_csv, selected, horizontal_flag):
    panes = _build_panes(pane_ids_csv)
    selected = None if selected == "-" else selected
    result_selected, action = mod.handle_click(
        int(cy), panes, selected, horizontal_flag == "1"
    )
    return f"{result_selected},{action}"


def _handle_key(key, pane_ids_csv, selected):
    panes = _build_panes(pane_ids_csv)
    selected = None if selected == "-" else selected
    result_selected, action = mod.handle_key(key, panes, selected)
    return f"{result_selected},{action}"


_FUNCTIONS = {
    "claude_task": mod.claude_task,
    "copilot_task": mod.copilot_task,
    "codex_task": mod.codex_task,
    "claude_status": mod.claude_status,
    "copilot_status": mod.copilot_status,
    "codex_status": mod.codex_status,
    "is_claude_pane": mod.is_claude_pane,
    "is_copilot_pane": mod.is_copilot_pane,
    "is_codex_pane": mod.is_codex_pane,
    "shorten_dir": mod.shorten_dir,
    "claude_title_status": mod.claude_title_status,
    "copilot_title_status": mod.copilot_title_status,
    "codex_title_status": mod.codex_title_status,
    "classify_key_hex": _classify_key_hex,
    "pane_at_row": _pane_at_row,
    "handle_click": _handle_click,
    "handle_key": _handle_key,
}

if __name__ == "__main__":
    func_name = sys.argv[1]
    args = sys.argv[2:]
    result = _FUNCTIONS[func_name](*args)
    print(result)
