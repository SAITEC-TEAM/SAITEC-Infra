#!/usr/bin/env bash

set -euo pipefail

# STEPS 1: 通过交互式生成pyproject.toml文件
# STEPS 2: 直接复制.pre-commit-config.yaml文件
# STEPS 3: 创建（如有则不创建）.vscode / .cursor / .trae 文件夹, 并复制settings.json文件
# STEPS 4: 如果项目中有requirements.txt文件，则将requirements.txt导入pyproject.toml的[dependencies]中

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ASSETS_DIR="${SRC_DIR}/assets"
TARGET_DIR="${1:-$(pwd)}"

PROJECT_VERSION_DEFAULT="0.1.0"
PYTHON_VERSION_DEFAULT=">=3.10"
MYPY_STRICT_DEFAULT="false"

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

prompt_required() {
    local label="$1"
    local value=""

    while true; do
        read -r -p "${label}: " value
        value="$(trim "$value")"
        if [[ -n "$value" ]]; then
            printf '%s' "$value"
            return 0
        fi
        printf '该字段不能为空，请重新输入。\n' >&2
    done
}

prompt_with_default() {
    local label="$1"
    local default_value="$2"
    local value=""

    read -r -p "${label} [DEFAULT: ${default_value}]: " value
    value="$(trim "$value")"

    if [[ -z "$value" ]]; then
        printf '%s' "$default_value"
        return 0
    fi

    printf '%s' "$value"
}

default_project_name() {
    local target_dir="$1"
    local normalized_dir="${target_dir%/}"

    if [[ -z "$normalized_dir" ]]; then
        normalized_dir="$target_dir"
    fi

    basename "$normalized_dir"
}

prompt_confirm_default_no() {
    local label="$1"
    local value=""

    read -r -p "${label} [y/N]: " value
    value="$(tr '[:upper:]' '[:lower:]' <<<"$value")"
    value="$(trim "$value")"

    case "$value" in
        y|yes)
            return 0
            ;;
        ""|n|no)
            return 1
            ;;
        *)
            printf '无法识别的输入，按默认值 N 处理。\n' >&2
            return 1
            ;;
    esac
}

normalize_requires_python() {
    local value="$1"
    value="$(trim "$value")"

    if [[ "$value" =~ ^[0-9]+\.[0-9]+$ ]]; then
        printf '>=%s' "$value"
        return 0
    fi

    printf '%s' "$value"
}

extract_python_version_real() {
    local requires_python="$1"

    if [[ "$requires_python" =~ ([0-9]+\.[0-9]+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    printf '无法从 requires-python 中提取 Python 版本: %s\n' "$requires_python" >&2
    exit 1
}

escape_toml_string() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

render_template_file() {
    local file_path="$1"
    local content=""

    content="$(<"$file_path")"
    content="${content//\{\{\$PROJECT_NAME\}\}/$PROJECT_NAME}"
    content="${content//\{\{\$PROJECT_VERSION\}\}/$PROJECT_VERSION}"
    content="${content//\{\{\$PYTHON_VERSION\}\}/$PYTHON_VERSION}"
    content="${content//\{\{\$PYTHON_VERSION_REAL\}\}/$PYTHON_VERSION_REAL}"
    content="${content//\{\{\$PYTHON_VERSION_REAL_NOPOINT\}\}/$PYTHON_VERSION_REAL_NOPOINT}"
    content="${content//\{\{\$STRICT\}\}/$STRICT}"
    printf '%s' "$content"
}

build_dependency_section() {
    local requirements_file="$1"
    local line=""
    local raw_line=""
    local dependencies=()

    if [[ -f "$requirements_file" ]]; then
        while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
            line="${raw_line%$'\r'}"

            if [[ "$line" =~ ^[[:space:]]*# ]]; then
                continue
            fi

            line="${line%% \#*}"
            line="${line%%	\#*}"
            line="$(trim "$line")"

            if [[ -z "$line" ]]; then
                continue
            fi

            case "$line" in
                -r*|--requirement*|-c*|--constraint*|-e*|--editable*|--index-url*|--extra-index-url*|--find-links*|--trusted-host*)
                    printf '警告: requirements.txt 中的配置项暂不自动导入，已跳过: %s\n' "$line" >&2
                    continue
                    ;;
            esac

            dependencies+=("$line")
        done <"$requirements_file"
    fi

    printf 'dependencies = [\n'
    for line in "${dependencies[@]}"; do
        printf '    "%s",\n' "$(escape_toml_string "$line")"
    done
    printf ']\n\n'
    printf '[project.optional-dependencies]\n'
    printf 'dev = [\n]\n'
    printf 'prod = [\n]\n'
}

write_file_with_confirm() {
    local target_file="$1"
    local content="$2"

    if [[ -f "$target_file" ]]; then
        if ! prompt_confirm_default_no "$(basename "$target_file") 已存在，是否覆盖"; then
            printf '跳过: %s\n' "$target_file"
            return 0
        fi
    fi

    printf '%s\n' "$content" >"$target_file"
    printf '已写入: %s\n' "$target_file"
}

copy_file_with_confirm() {
    local source_file="$1"
    local target_file="$2"

    if [[ -f "$target_file" ]]; then
        if ! prompt_confirm_default_no "$(basename "$target_file") 已存在，是否覆盖"; then
            printf '跳过: %s\n' "$target_file"
            return 0
        fi
    fi

    cp "$source_file" "$target_file"
    printf '已写入: %s\n' "$target_file"
}

ensure_git_repository_or_confirm() {
    if git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 0
    fi

    printf '提醒: 目标目录不是一个 Git 仓库: %s\n' "$TARGET_DIR"
    if ! prompt_confirm_default_no "是否仍然继续初始化"; then
        printf '已取消初始化。\n'
        exit 0
    fi
}

main() {
    local project_section=""
    local dependency_section=""
    local pytest_section=""
    local mypy_section=""
    local ruff_section=""
    local taskipy_section=""
    local pyproject_content=""
    local requirements_file="${TARGET_DIR}/requirements.txt"
    local pyproject_file="${TARGET_DIR}/pyproject.toml"
    local project_name_default=""

    if [[ ! -d "$TARGET_DIR" ]]; then
        printf '目标目录不存在: %s\n' "$TARGET_DIR" >&2
        exit 1
    fi

    if [[ ! -f "${ASSETS_DIR}/.pre-commit-config.yaml" ]]; then
        printf '缺少模板文件: %s\n' "${ASSETS_DIR}/.pre-commit-config.yaml" >&2
        exit 1
    fi

    ensure_git_repository_or_confirm

    project_name_default="$(default_project_name "$TARGET_DIR")"
    PROJECT_NAME="$(prompt_with_default "项目名称" "$project_name_default")"
    PROJECT_VERSION="$(prompt_with_default "项目版本" "$PROJECT_VERSION_DEFAULT")"
    PYTHON_VERSION="$(prompt_with_default "Python 版本要求" "$PYTHON_VERSION_DEFAULT")"
    PYTHON_VERSION="$(normalize_requires_python "$PYTHON_VERSION")"
    PYTHON_VERSION_REAL="$(extract_python_version_real "$PYTHON_VERSION")"
    PYTHON_VERSION_REAL_NOPOINT="${PYTHON_VERSION_REAL//./}"

    if prompt_confirm_default_no "是否启用 mypy strict 模式"; then
        STRICT="true"
    else
        STRICT="$MYPY_STRICT_DEFAULT"
    fi

    project_section="$(render_template_file "${ASSETS_DIR}/pyproject.toml.proj")"
    dependency_section="$(build_dependency_section "$requirements_file")"
    pytest_section="$(<"${ASSETS_DIR}/pyproject.toml.pytest")"
    mypy_section="$(render_template_file "${ASSETS_DIR}/pyproject.toml.mypy")"
    ruff_section="$(render_template_file "${ASSETS_DIR}/pyproject.toml.ruff")"
    taskipy_section="$(<"${ASSETS_DIR}/pyproject.toml.taskipy")"

    pyproject_content="$(printf '%s\n\n%s\n\n%s\n\n%s\n\n%s\n\n%s\n' \
        "$project_section" \
        "$dependency_section" \
        "$pytest_section" \
        "$mypy_section" \
        "$ruff_section" \
        "$taskipy_section")"

    write_file_with_confirm "$pyproject_file" "$pyproject_content"
    copy_file_with_confirm "${ASSETS_DIR}/.pre-commit-config.yaml" "${TARGET_DIR}/.pre-commit-config.yaml"
    copy_file_with_confirm "${ASSETS_DIR}/.gitignore" "${TARGET_DIR}/.gitignore"
    copy_file_with_confirm "${ASSETS_DIR}/.gitattributes" "${TARGET_DIR}/.gitattributes"

    mkdir -p "${TARGET_DIR}/.vscode" "${TARGET_DIR}/.cursor" "${TARGET_DIR}/.trae"
    printf '已确保目录存在: %s\n' "${TARGET_DIR}/.vscode"
    printf '已确保目录存在: %s\n' "${TARGET_DIR}/.cursor"
    printf '已确保目录存在: %s\n' "${TARGET_DIR}/.trae"

    copy_file_with_confirm "${ASSETS_DIR}/settings.json" "${TARGET_DIR}/.vscode/settings.json"

    if [[ -f "$requirements_file" ]]; then
        printf '已检测到 requirements.txt，并尝试导入到 pyproject.toml 的 [project].dependencies。\n'
    else
        printf '未检测到 requirements.txt，已生成空的 dependencies 列表。\n'
    fi

    printf '初始化完成，目标目录: %s\n' "$TARGET_DIR"
}

main "$@"