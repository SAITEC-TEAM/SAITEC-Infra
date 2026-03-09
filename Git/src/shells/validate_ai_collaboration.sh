#!/usr/bin/env bash

set -euo pipefail

TARGET_DIR="${1:-$(pwd)}"
FAILURES=0
ADAPTER_COUNT=0

usage() {
    cat <<'EOF'
用法:
  validate_ai_collaboration.sh [target-dir]

校验目标仓库是否具备 AI 协作主规范与至少一个工具适配入口。
EOF
}

check_required_file() {
    local relative_path="$1"

    if [[ -f "${TARGET_DIR}/${relative_path}" ]]; then
        printf '[OK] %s\n' "$relative_path"
        return 0
    fi

    printf '[MISSING] %s\n' "$relative_path" >&2
    FAILURES=$((FAILURES + 1))
}

check_optional_file() {
    local relative_path="$1"

    if [[ -f "${TARGET_DIR}/${relative_path}" ]]; then
        printf '[OK] %s\n' "$relative_path"
        ADAPTER_COUNT=$((ADAPTER_COUNT + 1))
    else
        printf '[SKIP] %s\n' "$relative_path"
    fi
}

main() {
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        usage
        exit 0
    fi

    if [[ ! -d "$TARGET_DIR" ]]; then
        printf '目标目录不存在: %s\n' "$TARGET_DIR" >&2
        exit 1
    fi

    printf '检查目标目录: %s\n' "$TARGET_DIR"

    check_required_file "AI_COLLABORATION.md"
    check_required_file "AGENTS.md"

    check_optional_file ".github/copilot-instructions.md"
    check_optional_file ".cursor/rules/ai-collaboration.mdc"
    check_optional_file ".claude/CLAUDE.md"
    check_optional_file ".codex/AGENTS.md"
    check_optional_file ".trae/AGENTS.md"

    if [[ "$ADAPTER_COUNT" -eq 0 ]]; then
        printf '[MISSING] 至少应存在一个 AI 工具适配文件。\n' >&2
        FAILURES=$((FAILURES + 1))
    fi

    if [[ "$FAILURES" -gt 0 ]]; then
        printf 'AI 协作检查失败，共 %s 项未满足。\n' "$FAILURES" >&2
        exit 1
    fi

    printf 'AI 协作检查通过。\n'
}

main "$@"
