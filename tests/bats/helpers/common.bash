#!/usr/bin/env bash

AGENT_PS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/agent-ps"
FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
PYTHON_HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../python" && pwd)/test_helper.py"

setup_mock_bin() {
    mkdir -p "$BATS_TEST_TMPDIR/mock_bin"
    export PATH="$BATS_TEST_TMPDIR/mock_bin:$PATH"
    export TMUX="/tmp/tmux-test-fake,0,0"
}

create_tmux_mock() {
    local pane_fixture="${1:-pane_list_empty.txt}"
    local capture_fixture="${2:-capture_empty.txt}"
    local mock="$BATS_TEST_TMPDIR/mock_bin/tmux"
    export MOCK_PANE_LIST_FIXTURE="$FIXTURES_DIR/$pane_fixture"
    export MOCK_CAPTURE_FIXTURE="$FIXTURES_DIR/$capture_fixture"
    cat > "$mock" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    display-message) echo "test-session" ;;
    list-panes)      cat "${MOCK_PANE_LIST_FIXTURE}" ;;
    capture-pane)    cat "${MOCK_CAPTURE_FIXTURE}" ;;
    select-window|select-pane) exit 0 ;;
    *) exit 1 ;;
esac
MOCK_EOF
    chmod +x "$mock"
}

call_python() {
    python3 "$PYTHON_HELPER" "$@"
}
