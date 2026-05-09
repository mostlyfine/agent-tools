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

_FUNCTIONS = {
    "claude_task": mod.claude_task,
    "copilot_task": mod.copilot_task,
    "claude_status": mod.claude_status,
    "copilot_status": mod.copilot_status,
    "is_claude_pane": mod.is_claude_pane,
    "is_copilot_pane": mod.is_copilot_pane,
    "shorten_dir": mod.shorten_dir,
    "extract_last_message": mod.extract_last_message,
    "claude_title_status": mod.claude_title_status,
    "copilot_title_status": mod.copilot_title_status,
}

if __name__ == "__main__":
    func_name = sys.argv[1]
    args = sys.argv[2:]
    result = _FUNCTIONS[func_name](*args)
    print(result)
