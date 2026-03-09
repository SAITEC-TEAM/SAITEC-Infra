#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
VERSION_FILE="${REPO_ROOT}/VERSION"
INSTALL_SCRIPT="${REPO_ROOT}/install.sh"

DIST_DIR="${REPO_ROOT}/dist"
VERSION=""
TAG=""
REPO_SLUG=""
TARGET_COMMITISH=""
RELEASE_NAME=""
NOTES=""
NOTES_FILE=""
TOKEN_ENV_NAME="GITHUB_TOKEN"

SKIP_BUILD="false"
SKIP_TAG="false"
SKIP_PUSH="false"
SKIP_RELEASE="false"
ALLOW_DIRTY="false"
DRY_RUN="false"
DRAFT="false"
PRERELEASE="false"

usage() {
    cat <<'EOF'
用法:
  publish-release.sh [选项]

功能:
  1. 生成 release artifact
  2. 创建并推送 Git tag
  3. 调用 GitHub Release API 创建 release
  4. 上传 install.sh、tar.gz、sha256

选项:
  --version <version>       发布版本；默认读取 VERSION
  --tag <tag>               Git tag 名称；默认与 version 一致
  --repo <owner/repo>       GitHub 仓库；默认从 origin 推断
  --target <commitish>      release 指向的 commit / branch；默认 HEAD
  --dist-dir <dir>          构建输出目录；默认 ./dist
  --release-name <name>     release 标题；默认 "SAITEC Git <tag>"
  --notes <text>            release 描述文本
  --notes-file <file>       从文件读取 release 描述
  --token-env <env>         Token 环境变量名；默认 GITHUB_TOKEN
  --skip-build              跳过构建
  --skip-tag                跳过创建 tag
  --skip-push               跳过推送 tag
  --skip-release            跳过 GitHub release 创建与上传
  --allow-dirty             允许在脏工作区发布
  --draft                   创建 draft release
  --prerelease              创建 prerelease
  --dry-run                 仅打印将执行的动作
  --help                    显示帮助

前置要求:
  - 已配置可 push 的 origin
  - 已导出 GitHub token，例如:
      export GITHUB_TOKEN=xxxx
EOF
}

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

trim() {
    local value="${1:-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

json_get() {
    local expr="$1"
    python3 -c 'import json, sys
data = json.load(sys.stdin)
expr = sys.argv[1]
value = data
for part in expr.split("."):
    if not part:
        continue
    if isinstance(value, list):
        value = value[int(part)]
    else:
        value = value.get(part)
if value is None:
    sys.exit(1)
if isinstance(value, (dict, list)):
    print(json.dumps(value))
else:
    print(value)' "$expr"
}

json_escape() {
    python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))'
}

infer_repo_slug() {
    local remote_url=""

    remote_url="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
    [[ -n "$remote_url" ]] || fail '无法从 origin 推断 GitHub 仓库，请使用 --repo 指定。'

    case "$remote_url" in
        git@github.com:*|git@github-*:*)
            remote_url="${remote_url#*:}"
            remote_url="${remote_url%.git}"
            printf '%s' "$remote_url"
            ;;
        https://github.com/*)
            remote_url="${remote_url#https://github.com/}"
            remote_url="${remote_url%.git}"
            printf '%s' "$remote_url"
            ;;
        ssh://git@github.com/*)
            remote_url="${remote_url#ssh://git@github.com/}"
            remote_url="${remote_url%.git}"
            printf '%s' "$remote_url"
            ;;
        *)
            fail "无法解析 origin 远程地址: $remote_url"
            ;;
    esac
}

ensure_clean_worktree() {
    local status=""

    if [[ "$ALLOW_DIRTY" == "true" ]]; then
        return 0
    fi

    status="$(git -C "$REPO_ROOT" status --short)"
    if [[ -n "$status" ]]; then
        fail '工作区存在未提交变更；请先提交，或显式传入 --allow-dirty。'
    fi
}

run_or_print() {
    if [[ "$DRY_RUN" == "true" ]]; then
        printf '[DRY-RUN] %s\n' "$*"
        return 0
    fi

    "$@"
}

load_release_notes() {
    if [[ -n "$NOTES" && -n "$NOTES_FILE" ]]; then
        fail '--notes 与 --notes-file 只能二选一。'
    fi

    if [[ -n "$NOTES_FILE" ]]; then
        [[ -f "$NOTES_FILE" ]] || fail "release 描述文件不存在: $NOTES_FILE"
        NOTES="$(<"$NOTES_FILE")"
    fi

    if [[ -z "$NOTES" ]]; then
        NOTES="Release ${TAG}"
    fi
}

require_token() {
    local token=""
    token="$(printenv "$TOKEN_ENV_NAME" 2>/dev/null || true)"
    [[ -n "$token" ]] || fail "未检测到 ${TOKEN_ENV_NAME}，无法调用 GitHub Release API。"
}

call_github_api() {
    local method="$1"
    local url="$2"
    local body="${3:-}"
    local response_file="$4"
    local http_code=""
    local token=""

    token="$(printenv "$TOKEN_ENV_NAME")"

    if [[ -n "$body" ]]; then
        http_code="$(curl -sS -o "$response_file" -w '%{http_code}' \
            -X "$method" \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${token}" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            -H 'Content-Type: application/json' \
            "$url" \
            -d "$body")"
    else
        http_code="$(curl -sS -o "$response_file" -w '%{http_code}' \
            -X "$method" \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${token}" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "$url")"
    fi

    printf '%s' "$http_code"
}

upload_asset() {
    local upload_url="$1"
    local asset_path="$2"
    local asset_name=""
    local response_file=""
    local http_code=""
    local token=""
    local mime_type="application/octet-stream"

    asset_name="$(basename "$asset_path")"
    response_file="$(mktemp)"
    token="$(printenv "$TOKEN_ENV_NAME")"

    case "$asset_name" in
        *.sh)
            mime_type="text/x-shellscript"
            ;;
        *.gz)
            mime_type="application/gzip"
            ;;
        *.sha256)
            mime_type="text/plain"
            ;;
    esac

    http_code="$(curl -sS -o "$response_file" -w '%{http_code}' \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${token}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -H "Content-Type: ${mime_type}" \
        --data-binary @"$asset_path" \
        "${upload_url}?name=${asset_name}")"

    if [[ ! "$http_code" =~ ^20[01]$ ]]; then
        printf '上传资产失败: %s\n' "$asset_name" >&2
        cat "$response_file" >&2
        rm -f "$response_file"
        exit 1
    fi

    rm -f "$response_file"
    printf '已上传资产: %s\n' "$asset_name"
}

delete_existing_assets() {
    local release_json_file="$1"
    local asset_names_csv="$2"
    local token=""

    token="$(printenv "$TOKEN_ENV_NAME")"

    python3 - "$release_json_file" "$asset_names_csv" <<'PY' | while IFS=$'\t' read -r asset_id asset_name; do
import json, sys
release_path = sys.argv[1]
names = set(filter(None, sys.argv[2].split(",")))
with open(release_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
for asset in data.get("assets", []):
    if asset.get("name") in names:
        print(f"{asset['id']}\t{asset['name']}")
PY
        if [[ -z "${asset_id:-}" ]]; then
            continue
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            printf '[DRY-RUN] 将删除已存在资产: %s\n' "$asset_name"
            continue
        fi

        curl -sS \
            -X DELETE \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${token}" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "https://api.github.com/repos/${REPO_SLUG}/releases/assets/${asset_id}" >/dev/null
        printf '已删除已存在资产: %s\n' "$asset_name"
    done
}

create_or_update_release() {
    local response_file=""
    local http_code=""
    local release_api_url=""
    local release_url=""
    local upload_url=""
    local html_url=""
    local notes_json=""
    local payload=""
    local artifact_name=""
    local artifact_path=""
    local checksum_path=""
    local asset_names_csv=""

    response_file="$(mktemp)"
    trap 'rm -f "$response_file"' RETURN

    release_api_url="https://api.github.com/repos/${REPO_SLUG}/releases/tags/${TAG}"
    http_code="$(call_github_api GET "$release_api_url" "" "$response_file")"

    notes_json="$(printf '%s' "$NOTES" | json_escape)"
    payload="$(cat <<EOF
{
  "tag_name": "$(printf '%s' "$TAG")",
  "target_commitish": "$(printf '%s' "$TARGET_COMMITISH")",
  "name": "$(printf '%s' "$RELEASE_NAME")",
  "body": ${notes_json},
  "draft": ${DRAFT},
  "prerelease": ${PRERELEASE}
}
EOF
)"

    if [[ "$http_code" == "200" ]]; then
        release_url="$(json_get "url" <"$response_file")"
        if [[ "$DRY_RUN" == "true" ]]; then
            printf '[DRY-RUN] 将更新已存在 release: %s\n' "$TAG"
        else
            http_code="$(call_github_api PATCH "$release_url" "$payload" "$response_file")"
            [[ "$http_code" =~ ^20[01]$ ]] || {
                cat "$response_file" >&2
                fail "更新 release 失败，HTTP ${http_code}"
            }
        fi
    elif [[ "$http_code" == "404" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            printf '[DRY-RUN] 将创建新的 release: %s\n' "$TAG"
        else
            http_code="$(call_github_api POST "https://api.github.com/repos/${REPO_SLUG}/releases" "$payload" "$response_file")"
            [[ "$http_code" =~ ^20[01]$ ]] || {
                cat "$response_file" >&2
                fail "创建 release 失败，HTTP ${http_code}"
            }
        fi
    else
        cat "$response_file" >&2
        fail "查询 release 失败，HTTP ${http_code}"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        printf '[DRY-RUN] 将上传 install.sh、artifact 和 checksum 到 GitHub release。\n'
        return 0
    fi

    upload_url="$(json_get "upload_url" <"$response_file")"
    html_url="$(json_get "html_url" <"$response_file")"
    upload_url="${upload_url%\{*}"

    artifact_name="saitec-git-${VERSION}.tar.gz"
    artifact_path="${DIST_DIR}/${artifact_name}"
    checksum_path="${artifact_path}.sha256"
    asset_names_csv="install.sh,${artifact_name},${artifact_name}.sha256"

    delete_existing_assets "$response_file" "$asset_names_csv"

    upload_asset "$upload_url" "$INSTALL_SCRIPT"
    upload_asset "$upload_url" "$artifact_path"
    [[ -f "$checksum_path" ]] && upload_asset "$upload_url" "$checksum_path"

    printf 'Release 已就绪: %s\n' "$html_url"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                VERSION="${2:-}"
                shift 2
                ;;
            --tag)
                TAG="${2:-}"
                shift 2
                ;;
            --repo)
                REPO_SLUG="${2:-}"
                shift 2
                ;;
            --target)
                TARGET_COMMITISH="${2:-}"
                shift 2
                ;;
            --dist-dir)
                DIST_DIR="${2:-}"
                shift 2
                ;;
            --release-name)
                RELEASE_NAME="${2:-}"
                shift 2
                ;;
            --notes)
                NOTES="${2:-}"
                shift 2
                ;;
            --notes-file)
                NOTES_FILE="${2:-}"
                shift 2
                ;;
            --token-env)
                TOKEN_ENV_NAME="${2:-}"
                shift 2
                ;;
            --skip-build)
                SKIP_BUILD="true"
                shift
                ;;
            --skip-tag)
                SKIP_TAG="true"
                shift
                ;;
            --skip-push)
                SKIP_PUSH="true"
                shift
                ;;
            --skip-release)
                SKIP_RELEASE="true"
                shift
                ;;
            --allow-dirty)
                ALLOW_DIRTY="true"
                shift
                ;;
            --draft)
                DRAFT="true"
                shift
                ;;
            --prerelease)
                PRERELEASE="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                fail "未知选项: $1"
                ;;
        esac
    done
}

main() {
    local artifact_path=""
    local checksum_path=""

    parse_args "$@"

    VERSION="$(trim "$VERSION")"
    if [[ -z "$VERSION" ]]; then
        [[ -f "$VERSION_FILE" ]] || fail "缺少 VERSION 文件: $VERSION_FILE"
        VERSION="$(trim "$(sed -n '1p' "$VERSION_FILE")")"
    fi

    [[ -n "$VERSION" ]] || fail '发布版本不能为空。'

    if [[ -z "$TAG" ]]; then
        TAG="$VERSION"
    fi

    if [[ -z "$REPO_SLUG" ]]; then
        REPO_SLUG="$(infer_repo_slug)"
    fi

    if [[ -z "$TARGET_COMMITISH" ]]; then
        TARGET_COMMITISH="$(git -C "$REPO_ROOT" rev-parse HEAD)"
    fi

    if [[ -z "$RELEASE_NAME" ]]; then
        RELEASE_NAME="SAITEC Git ${TAG}"
    fi

    load_release_notes
    ensure_clean_worktree

    artifact_path="${DIST_DIR}/saitec-git-${VERSION}.tar.gz"
    checksum_path="${artifact_path}.sha256"

    if [[ "$SKIP_BUILD" != "true" ]]; then
        run_or_print bash "${SCRIPT_DIR}/build-release.sh" "$DIST_DIR" "$VERSION"
    fi

    [[ -f "$INSTALL_SCRIPT" ]] || fail "缺少 install.sh: $INSTALL_SCRIPT"
    [[ "$DRY_RUN" == "true" || -f "$artifact_path" ]] || fail "缺少 artifact: $artifact_path"
    [[ "$DRY_RUN" == "true" || -f "$checksum_path" ]] || fail "缺少 checksum: $checksum_path"

    if git -C "$REPO_ROOT" rev-parse "$TAG" >/dev/null 2>&1; then
        printf 'tag 已存在: %s\n' "$TAG"
    elif [[ "$SKIP_TAG" == "true" ]]; then
        printf '已跳过创建 tag: %s\n' "$TAG"
    else
        run_or_print git -C "$REPO_ROOT" tag -a "$TAG" -m "Release $TAG"
    fi

    if [[ "$SKIP_PUSH" == "true" ]]; then
        printf '已跳过推送 tag。\n'
    else
        run_or_print git -C "$REPO_ROOT" push origin "$TAG"
    fi

    if [[ "$SKIP_RELEASE" == "true" ]]; then
        printf '已跳过 GitHub release 创建与上传。\n'
        return 0
    fi

    require_token
    create_or_update_release
}

main "$@"
