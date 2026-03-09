#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SAITEC_GIT_SOURCE_DIR:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}"
VERSION_FILE="${SOURCE_DIR}/../VERSION"

print_usage() {
    cat <<'EOF'
用法:
  saitec-git.sh <command> [args]

命令:
  init       初始化目标仓库
  validate   校验 AI 协作入口
  doctor     诊断环境和目标仓库状态
  version    输出版本
  help       显示帮助
EOF
}

print_version() {
    if [[ -n "${SAITEC_GIT_BUILD_VERSION:-}" ]]; then
        printf '%s\n' "$SAITEC_GIT_BUILD_VERSION"
        return 0
    fi

    if [[ -f "$VERSION_FILE" ]]; then
        sed -n '1p' "$VERSION_FILE"
        return 0
    fi

    printf 'dev\n'
}

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        init)
            exec env SAITEC_GIT_SOURCE_DIR="$SOURCE_DIR" bash "${SCRIPT_DIR}/initial.sh" "$@"
            ;;
        validate)
            exec bash "${SCRIPT_DIR}/validate_ai_collaboration.sh" "$@"
            ;;
        doctor)
            exec bash "${SCRIPT_DIR}/doctor.sh" "$@"
            ;;
        version)
            print_version
            ;;
        help|--help|-h)
            print_usage
            ;;
        *)
            printf '未知命令: %s\n' "$command" >&2
            print_usage >&2
            exit 1
            ;;
    esac
}

main "$@"
