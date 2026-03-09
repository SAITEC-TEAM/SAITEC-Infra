#!/usr/bin/env bash

set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" 2>/dev/null && pwd || pwd)"
LOCAL_ENTRYPOINT="${SCRIPT_DIR}/src/shells/saitec-git.sh"

DIST_VERSION="${SAITEC_GIT_VERSION:-latest}"
DIST_BASE_URL="${SAITEC_GIT_DIST_BASE_URL:-}"
ARTIFACT_URL="${SAITEC_GIT_ARTIFACT_URL:-}"

usage() {
    cat <<'EOF'
用法:
  install.sh [--version <tag>] [--dist-base-url <url> | --artifact-url <url>] <command> [args]

命令:
  init       初始化目标仓库
  validate   校验 AI 协作入口
  doctor     诊断环境和目标仓库状态
  version    输出当前工具版本

说明:
  1. 在源码仓库内执行时，install.sh 会直接调用本地实现。
  2. 以远程单文件方式执行时，install.sh 会下载对应版本的 release artifact。
EOF
}

download_file() {
    local url="$1"
    local output="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$output"
        return 0
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -qO "$output" "$url"
        return 0
    fi

    printf '缺少 curl 或 wget，无法下载远程 artifact。\n' >&2
    exit 1
}

verify_checksum_if_available() {
    local artifact_path="$1"
    local checksum_path="$2"
    local expected_hash=""
    local actual_hash=""

    if [[ ! -f "$checksum_path" ]]; then
        printf '提醒: 未找到 checksum 文件，跳过完整性校验。\n' >&2
        return 0
    fi

    if ! command -v sha256sum >/dev/null 2>&1; then
        printf '提醒: 未找到 sha256sum，跳过完整性校验。\n' >&2
        return 0
    fi

    expected_hash="$(awk 'NR==1 {print $1}' "$checksum_path")"
    actual_hash="$(sha256sum "$artifact_path" | awk '{print $1}')"

    if [[ -z "$expected_hash" || -z "$actual_hash" ]]; then
        printf 'checksum 校验失败：无法解析校验值。\n' >&2
        exit 1
    fi

    if [[ "$expected_hash" != "$actual_hash" ]]; then
        printf 'checksum 校验失败：artifact 与发布校验值不匹配。\n' >&2
        exit 1
    fi
}

main() {
    local forwarded_args=()
    local command_seen="false"
    local temp_dir=""
    local artifact_path=""
    local checksum_path=""
    local resolved_artifact_url=""
    local extracted_root=""
    local entrypoint=""

    while [[ $# -gt 0 ]]; do
        if [[ "$command_seen" == "false" ]]; then
            case "$1" in
                --version)
                    [[ $# -ge 2 ]] || {
                        printf '--version 需要一个值。\n' >&2
                        exit 1
                    }
                    DIST_VERSION="$2"
                    shift 2
                    continue
                    ;;
                --dist-base-url)
                    [[ $# -ge 2 ]] || {
                        printf '--dist-base-url 需要一个值。\n' >&2
                        exit 1
                    }
                    DIST_BASE_URL="$2"
                    shift 2
                    continue
                    ;;
                --artifact-url)
                    [[ $# -ge 2 ]] || {
                        printf '--artifact-url 需要一个值。\n' >&2
                        exit 1
                    }
                    ARTIFACT_URL="$2"
                    shift 2
                    continue
                    ;;
                --help|-h)
                    usage
                    exit 0
                    ;;
                init|validate|doctor|version|help)
                    command_seen="true"
                    ;;
            esac
        fi

        forwarded_args+=("$1")
        shift
    done

    if [[ "${#forwarded_args[@]}" -eq 0 ]]; then
        usage
        exit 1
    fi

    if [[ -f "$LOCAL_ENTRYPOINT" ]]; then
        if [[ "$DIST_VERSION" != "latest" ]]; then
            printf '提醒: 当前在源码仓库内执行 install.sh，将直接使用本地源码，忽略 --version=%s。\n' "$DIST_VERSION" >&2
        fi
        exec bash "$LOCAL_ENTRYPOINT" "${forwarded_args[@]}"
    fi

    if [[ -z "$ARTIFACT_URL" ]]; then
        if [[ -z "$DIST_BASE_URL" ]]; then
            printf '远程模式需要通过 --dist-base-url、--artifact-url 或环境变量 SAITEC_GIT_DIST_BASE_URL 提供 artifact 地址。\n' >&2
            exit 1
        fi
        ARTIFACT_URL="${DIST_BASE_URL%/}/saitec-git-${DIST_VERSION}.tar.gz"
    fi

    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' EXIT

    artifact_path="${temp_dir}/artifact.tar.gz"
    checksum_path="${temp_dir}/artifact.tar.gz.sha256"
    resolved_artifact_url="$ARTIFACT_URL"

    download_file "$resolved_artifact_url" "$artifact_path"
    if download_file "${resolved_artifact_url}.sha256" "$checksum_path"; then
        :
    else
        rm -f "$checksum_path"
    fi

    verify_checksum_if_available "$artifact_path" "$checksum_path"

    tar -xzf "$artifact_path" -C "$temp_dir"
    extracted_root="$(find "$temp_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    entrypoint="${extracted_root}/src/shells/saitec-git.sh"

    if [[ ! -f "$entrypoint" ]]; then
        printf '下载的 artifact 不包含期望入口: %s\n' "$entrypoint" >&2
        exit 1
    fi

    exec bash "$entrypoint" "${forwarded_args[@]}"
}

main "$@"
