#!/usr/bin/env bash

set -euo pipefail

TARGET_DIR="${1:-$(pwd)}"
FAILURES=0
WARNINGS=0

ok() {
    printf '[OK] %s\n' "$1"
}

warn() {
    printf '[WARN] %s\n' "$1"
    WARNINGS=$((WARNINGS + 1))
}

fail() {
    printf '[FAIL] %s\n' "$1" >&2
    FAILURES=$((FAILURES + 1))
}

usage() {
    cat <<'EOF'
用法:
  doctor.sh [target-dir]

检查当前环境是否具备运行 SAITEC Git 初始化脚本的基础条件。
EOF
}

check_command() {
    local name="$1"

    if command -v "$name" >/dev/null 2>&1; then
        ok "已检测到命令: $name"
    else
        fail "缺少命令: $name"
    fi
}

check_optional_command() {
    local name="$1"

    if command -v "$name" >/dev/null 2>&1; then
        ok "已检测到可选命令: $name"
    else
        warn "未检测到可选命令: $name"
    fi
}

main() {
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        usage
        exit 0
    fi

    if [[ ! -d "$TARGET_DIR" ]]; then
        fail "目标目录不存在: $TARGET_DIR"
    else
        ok "目标目录存在: $TARGET_DIR"
    fi

    check_command bash
    check_command git
    check_command cp
    check_command mktemp
    check_command tar

    if command -v curl >/dev/null 2>&1; then
        ok '已检测到下载命令: curl'
    elif command -v wget >/dev/null 2>&1; then
        ok '已检测到下载命令: wget'
    else
        warn '未检测到 curl 或 wget；远程 install.sh 模式将不可用。'
    fi

    if command -v python3 >/dev/null 2>&1 && python3 -m pip --version >/dev/null 2>&1; then
        ok '已检测到 python3 + pip'
    elif command -v python >/dev/null 2>&1 && python -m pip --version >/dev/null 2>&1; then
        ok '已检测到 python + pip'
    else
        warn '未检测到可用的 Python + pip；无法自动安装 pre-commit。'
    fi

    check_optional_command pre-commit

    if [[ -d "$TARGET_DIR" ]]; then
        if [[ -w "$TARGET_DIR" ]]; then
            ok "目标目录可写: $TARGET_DIR"
        else
            fail "目标目录不可写: $TARGET_DIR"
        fi

        if git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            ok '目标目录位于 Git 仓库中'
        else
            warn '目标目录不是 Git 仓库；可以生成文件，但无法安装 Git hooks。'
        fi

        if [[ -f "${TARGET_DIR}/.saitec/config.toml" ]]; then
            ok '已检测到 .saitec/config.toml'
        else
            warn '未检测到 .saitec/config.toml；首次初始化前这是正常现象。'
        fi
    fi

    if [[ "$FAILURES" -gt 0 ]]; then
        printf '环境检查失败：%s 个失败，%s 个警告。\n' "$FAILURES" "$WARNINGS" >&2
        exit 1
    fi

    printf '环境检查通过：%s 个警告。\n' "$WARNINGS"
}

main "$@"
