#!/usr/bin/env bash

set -euo pipefail

TARGET_DIR="${1:-$(pwd)}"
FAILURES=0
WARNINGS=0
REPO_ADAPTER_COUNT=0
LOCAL_ADAPTER_COUNT=0

usage() {
    cat <<'EOF'
用法:
  validate_ai_collaboration.sh [target-dir]

校验目标仓库是否具备 AI 协作主规范，并提示仓库级或本地工具适配入口的状态。
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
    local category="$2"

    if [[ -f "${TARGET_DIR}/${relative_path}" ]]; then
        printf '[OK] %s\n' "$relative_path"
        case "$category" in
            repo)
                REPO_ADAPTER_COUNT=$((REPO_ADAPTER_COUNT + 1))
                ;;
            local)
                LOCAL_ADAPTER_COUNT=$((LOCAL_ADAPTER_COUNT + 1))
                ;;
        esac
    else
        printf '[SKIP] %s\n' "$relative_path"
    fi
}

warn() {
    printf '[WARN] %s\n' "$1"
    WARNINGS=$((WARNINGS + 1))
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

    check_required_file ".saitec/AI_COLLABORATION.md"
    check_required_file "AGENTS.md"

    check_optional_file ".github/copilot-instructions.md" "repo"
    check_optional_file ".cursor/rules/ai-collaboration.mdc" "local"
    check_optional_file ".claude/CLAUDE.md" "local"
    check_optional_file ".codex/AGENTS.md" "local"
    check_optional_file ".trae/AGENTS.md" "local"

    if [[ "$REPO_ADAPTER_COUNT" -eq 0 ]]; then
        warn "未检测到仓库级 AI 工具入口；如需 GitHub 原生协作，建议保留 .github/copilot-instructions.md。"
    fi

    if [[ "$LOCAL_ADAPTER_COUNT" -eq 0 ]]; then
        if [[ -f "${TARGET_DIR}/.saitec/config.toml" ]]; then
            warn "未检测到本地 AI 工具目录；可执行 install.sh init --non-interactive . 进行重建。"
        else
            warn "未检测到本地 AI 工具目录；如需本地工具入口，请先执行初始化。"
        fi
    fi

    if [[ "$FAILURES" -gt 0 ]]; then
        printf 'AI 协作检查失败，共 %s 项未满足。\n' "$FAILURES" >&2
        exit 1
    fi

    if [[ "$WARNINGS" -gt 0 ]]; then
        printf 'AI 协作检查通过，但存在 %s 项提示。\n' "$WARNINGS"
        return 0
    fi

    printf 'AI 协作检查通过。\n'
}

main "$@"
