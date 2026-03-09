#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
VERSION_FILE="${REPO_ROOT}/VERSION"
OUTPUT_DIR="${1:-${REPO_ROOT}/dist}"
VERSION="${2:-}"
WORK_DIR=""

usage() {
    cat <<'EOF'
用法:
  build-release.sh [output-dir] [version]

生成可供 install.sh 下载的 release artifact 和 sha256 校验文件。
EOF
}

main() {
    local package_root=""
    local artifact_name=""
    local artifact_path=""

    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        usage
        exit 0
    fi

    if [[ -z "$VERSION" ]]; then
        if [[ -f "$VERSION_FILE" ]]; then
            VERSION="$(sed -n '1p' "$VERSION_FILE")"
        else
            printf '缺少 VERSION 文件，且未显式传入版本号。\n' >&2
            exit 1
        fi
    fi

    WORK_DIR="$(mktemp -d)"
    trap 'if [[ -n "${WORK_DIR:-}" ]]; then rm -rf "$WORK_DIR"; fi' EXIT

    package_root="${WORK_DIR}/saitec-git-${VERSION}"
    artifact_name="saitec-git-${VERSION}.tar.gz"
    artifact_path="${OUTPUT_DIR}/${artifact_name}"

    mkdir -p "$package_root" "$OUTPUT_DIR"
    cp -R "${REPO_ROOT}/src" "$package_root/src"
    cp "${REPO_ROOT}/install.sh" "$package_root/install.sh"
    cp "$VERSION_FILE" "$package_root/VERSION"

    tar -czf "$artifact_path" -C "$WORK_DIR" "saitec-git-${VERSION}"

    if command -v sha256sum >/dev/null 2>&1; then
        (
            cd "$OUTPUT_DIR"
            sha256sum "$artifact_name" >"${artifact_name}.sha256"
        )
    fi

    printf '已生成: %s\n' "$artifact_path"
    if [[ -f "${artifact_path}.sha256" ]]; then
        printf '已生成: %s.sha256\n' "$artifact_path"
    fi
}

main "$@"
