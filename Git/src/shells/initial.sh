#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SAITEC_GIT_SOURCE_DIR:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}"
ASSETS_DIR="${SOURCE_DIR}/assets"

PROJECT_VERSION_DEFAULT="0.1.0"
PYTHON_VERSION_DEFAULT=">=3.10"
MYPY_STRICT_DEFAULT="false"

TARGET_DIR="$(pwd)"
CONFIG_FILE=""
INTERACTIVE_MODE="auto"
FORCE="false"
DRY_RUN="false"
INSTALL_HOOKS_MODE="auto"

PRE_COMMIT_PYTHON_CMD=()
PRE_COMMIT_PYTHON_LABEL=""
PRE_COMMIT_RUNNER=()
PRE_COMMIT_RUNNER_LABEL=""

PROJECT_NAME=""
PROJECT_VERSION=""
PYTHON_VERSION=""
PYTHON_VERSION_REAL=""
PYTHON_VERSION_REAL_NOPOINT=""
STRICT="$MYPY_STRICT_DEFAULT"
INSTALL_HOOKS="false"

AI_COLLAB_ENABLED="false"
AI_GITHUB_ENABLED="false"
AI_CURSOR_ENABLED="false"
AI_CLAUDE_ENABLED="false"
AI_CODEX_ENABLED="false"
AI_TRAE_ENABLED="false"

CFG_PROJECT_NAME=""
CFG_PROJECT_VERSION=""
CFG_PYTHON_VERSION=""
CFG_STRICT=""
CFG_INSTALL_HOOKS=""
CFG_AI_COLLAB_ENABLED=""
CFG_AI_GITHUB_ENABLED=""
CFG_AI_CURSOR_ENABLED=""
CFG_AI_CLAUDE_ENABLED=""
CFG_AI_CODEX_ENABLED=""
CFG_AI_TRAE_ENABLED=""

trim() {
    local value="${1:-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

lower() {
    printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

parse_bool() {
    local value=""
    value="$(lower "$(trim "${1:-}")")"

    case "$value" in
        true|1|yes|y|on)
            printf 'true'
            ;;
        false|0|no|n|off)
            printf 'false'
            ;;
        *)
            return 1
            ;;
    esac
}

is_interactive() {
    [[ "$INTERACTIVE_MODE" == "true" ]]
}

print_usage() {
    cat <<'EOF'
用法:
  initial.sh [选项] [target-dir]

选项:
  --interactive         强制使用交互模式
  --non-interactive     使用默认值和配置文件，不进行提问
  --config <file>       从 TOML 配置文件读取参数
  --force               覆盖已存在文件
  --dry-run             仅显示将执行的动作，不写入文件
  --install-hooks       显式安装 pre-commit 和 Git hooks
  --no-install-hooks    跳过 pre-commit 和 Git hooks 安装
  --help                显示帮助

配置文件支持的键:
  project_name, project_version, python_version, mypy_strict,
  install_hooks, ai_collaboration, ai_github, ai_cursor,
  ai_claude, ai_codex, ai_trae

说明:
  如未显式传入 --config，且目标仓库中已存在 .saitec/config.toml，
  脚本会自动读取该文件以恢复本地 AI 工具入口和初始化选项。
EOF
}

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

strip_toml_quotes() {
    local value=""
    value="$(trim "${1:-}")"

    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
        value="${value:1:${#value}-2}"
        value="${value//\\\"/\"}"
        value="${value//\\\\/\\}"
    fi

    printf '%s' "$value"
}

load_config_file() {
    local line=""
    local key=""
    local raw_value=""

    if [[ -z "$CONFIG_FILE" ]]; then
        return 0
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        fail "配置文件不存在: $CONFIG_FILE"
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        line="$(trim "$line")"

        if [[ -z "$line" || "$line" == \#* || "$line" == \[* ]]; then
            continue
        fi

        if [[ ! "$line" =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            continue
        fi

        key="${BASH_REMATCH[1]}"
        raw_value="$(trim "${BASH_REMATCH[2]}")"

        case "$key" in
            project_name)
                CFG_PROJECT_NAME="$(strip_toml_quotes "$raw_value")"
                ;;
            project_version)
                CFG_PROJECT_VERSION="$(strip_toml_quotes "$raw_value")"
                ;;
            python_version)
                CFG_PYTHON_VERSION="$(strip_toml_quotes "$raw_value")"
                ;;
            mypy_strict)
                CFG_STRICT="$(parse_bool "$raw_value" || true)"
                ;;
            install_hooks)
                CFG_INSTALL_HOOKS="$(parse_bool "$raw_value" || true)"
                ;;
            ai_collaboration)
                CFG_AI_COLLAB_ENABLED="$(parse_bool "$raw_value" || true)"
                ;;
            ai_github)
                CFG_AI_GITHUB_ENABLED="$(parse_bool "$raw_value" || true)"
                ;;
            ai_cursor)
                CFG_AI_CURSOR_ENABLED="$(parse_bool "$raw_value" || true)"
                ;;
            ai_claude)
                CFG_AI_CLAUDE_ENABLED="$(parse_bool "$raw_value" || true)"
                ;;
            ai_codex)
                CFG_AI_CODEX_ENABLED="$(parse_bool "$raw_value" || true)"
                ;;
            ai_trae)
                CFG_AI_TRAE_ENABLED="$(parse_bool "$raw_value" || true)"
                ;;
        esac
    done <"$CONFIG_FILE"
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
    value="$(lower "$value")"
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

prompt_confirm_default_yes() {
    local label="$1"
    local value=""

    read -r -p "${label} [Y/n]: " value
    value="$(lower "$value")"
    value="$(trim "$value")"

    case "$value" in
        ""|y|yes)
            return 0
            ;;
        n|no)
            return 1
            ;;
        *)
            printf '无法识别的输入，按默认值 Y 处理。\n' >&2
            return 0
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

    fail "无法从 requires-python 中提取 Python 版本: $requires_python"
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

ensure_directory() {
    local target_dir="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        printf '[DRY-RUN] 将确保目录存在: %s\n' "$target_dir"
        return 0
    fi

    mkdir -p "$target_dir"
    printf '已确保目录存在: %s\n' "$target_dir"
}

decide_existing_file_action() {
    local target_file="$1"

    if [[ ! -f "$target_file" ]]; then
        return 0
    fi

    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi

    if is_interactive; then
        if prompt_confirm_default_no "$(basename "$target_file") 已存在，是否覆盖"; then
            return 0
        fi
        printf '跳过: %s\n' "$target_file"
        return 1
    fi

    printf '跳过已存在文件（非交互模式，未指定 --force）: %s\n' "$target_file"
    return 1
}

write_file_with_confirm() {
    local target_file="$1"
    local content="$2"

    mkdir -p "$(dirname "$target_file")"

    if ! decide_existing_file_action "$target_file"; then
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        printf '[DRY-RUN] 将写入: %s\n' "$target_file"
        return 0
    fi

    printf '%s\n' "$content" >"$target_file"
    printf '已写入: %s\n' "$target_file"
}

copy_file_with_confirm() {
    local source_file="$1"
    local target_file="$2"

    mkdir -p "$(dirname "$target_file")"

    if ! decide_existing_file_action "$target_file"; then
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        printf '[DRY-RUN] 将写入: %s\n' "$target_file"
        return 0
    fi

    cp "$source_file" "$target_file"
    printf '已写入: %s\n' "$target_file"
}

ensure_git_repository_or_confirm() {
    if git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 0
    fi

    printf '提醒: 目标目录不是一个 Git 仓库: %s\n' "$TARGET_DIR"
    if ! is_interactive; then
        return 0
    fi

    if ! prompt_confirm_default_no "是否仍然继续初始化"; then
        printf '已取消初始化。\n'
        exit 0
    fi
}

find_python_with_pip() {
    if command -v python3 >/dev/null 2>&1 && python3 -m pip --version >/dev/null 2>&1; then
        PRE_COMMIT_PYTHON_CMD=(python3)
        PRE_COMMIT_PYTHON_LABEL="python3"
        return 0
    fi

    if command -v python >/dev/null 2>&1 && python -m pip --version >/dev/null 2>&1; then
        PRE_COMMIT_PYTHON_CMD=(python)
        PRE_COMMIT_PYTHON_LABEL="python"
        return 0
    fi

    PRE_COMMIT_PYTHON_CMD=()
    PRE_COMMIT_PYTHON_LABEL=""
    return 1
}

detect_pre_commit_runner() {
    if command -v pre-commit >/dev/null 2>&1; then
        PRE_COMMIT_RUNNER=(pre-commit)
        PRE_COMMIT_RUNNER_LABEL="pre-commit"
        return 0
    fi

    if find_python_with_pip && "${PRE_COMMIT_PYTHON_CMD[@]}" -m pre_commit --version >/dev/null 2>&1; then
        PRE_COMMIT_RUNNER=("${PRE_COMMIT_PYTHON_CMD[@]}" -m pre_commit)
        PRE_COMMIT_RUNNER_LABEL="${PRE_COMMIT_PYTHON_LABEL} -m pre_commit"
        return 0
    fi

    PRE_COMMIT_RUNNER=()
    PRE_COMMIT_RUNNER_LABEL=""
    return 1
}

ensure_pre_commit_available() {
    if [[ "$INSTALL_HOOKS" != "true" ]]; then
        printf '已跳过 pre-commit 安装；如需启用，请显式传入 --install-hooks。\n'
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        printf '[DRY-RUN] 将检测或安装 pre-commit。\n'
        return 0
    fi

    if detect_pre_commit_runner; then
        printf '已检测到 pre-commit，可直接使用: %s\n' "$PRE_COMMIT_RUNNER_LABEL"
        return 0
    fi

    printf '提醒: 未检测到 pre-commit，正在尝试自动安装 pip 包 pre-commit。\n'

    if ! find_python_with_pip; then
        fail '未找到可用的 pip，无法自动安装 pre-commit。请先安装 pip 后重试。'
    fi

    if ! "${PRE_COMMIT_PYTHON_CMD[@]}" -m pip install pre-commit; then
        if [[ -z "${VIRTUAL_ENV:-}" && -z "${CONDA_PREFIX:-}" ]]; then
            printf '提醒: 当前未检测到虚拟环境，改为尝试执行 --user 安装。\n'
            "${PRE_COMMIT_PYTHON_CMD[@]}" -m pip install --user pre-commit
        else
            fail '自动安装 pre-commit 失败，请检查当前 Python / pip 环境。'
        fi
    fi

    if detect_pre_commit_runner; then
        printf '已完成 pre-commit 安装，可直接使用: %s\n' "$PRE_COMMIT_RUNNER_LABEL"
        return 0
    fi

    if [[ "${#PRE_COMMIT_PYTHON_CMD[@]}" -gt 0 ]] && "${PRE_COMMIT_PYTHON_CMD[@]}" -m pre_commit --version >/dev/null 2>&1; then
        PRE_COMMIT_RUNNER=("${PRE_COMMIT_PYTHON_CMD[@]}" -m pre_commit)
        PRE_COMMIT_RUNNER_LABEL="${PRE_COMMIT_PYTHON_LABEL} -m pre_commit"
        printf 'pre-commit 已安装，但命令路径尚未加入当前 PATH，将继续使用: %s\n' "$PRE_COMMIT_RUNNER_LABEL"
        return 0
    fi

    fail 'pre-commit 安装完成，但当前 shell 无法定位其可执行入口，请重新打开终端后重试。'
}

install_pre_commit_hook() {
    if [[ "$INSTALL_HOOKS" != "true" ]]; then
        printf '已跳过 Git hooks 安装；如需启用，请显式传入 --install-hooks。\n'
        return 0
    fi

    if ! git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        printf '提醒: 目标目录不是 Git 仓库，已跳过 pre-commit hook 安装。\n'
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        printf '[DRY-RUN] 将在目标仓库安装 pre-commit / pre-push hooks。\n'
        return 0
    fi

    if [[ "${#PRE_COMMIT_RUNNER[@]}" -eq 0 ]] && ! detect_pre_commit_runner; then
        printf '提醒: 未找到可用的 pre-commit 入口，已跳过 hook 安装。\n' >&2
        return 0
    fi

    if (
        cd "$TARGET_DIR"
        "${PRE_COMMIT_RUNNER[@]}" install --hook-type pre-commit --hook-type pre-push
    ); then
        printf '已安装 pre-commit / pre-push Git hooks。\n'
        return 0
    fi

    printf '提醒: pre-commit 已安装，但 hook 自动注册失败，请在目标目录手动执行: %s install --hook-type pre-commit --hook-type pre-push\n' "$PRE_COMMIT_RUNNER_LABEL" >&2
}

resolve_string_setting() {
    local config_value="$1"
    local prompt_label="$2"
    local default_value="$3"

    if [[ -n "$config_value" ]]; then
        printf '%s' "$config_value"
        return 0
    fi

    if is_interactive; then
        printf '%s' "$(prompt_with_default "$prompt_label" "$default_value")"
        return 0
    fi

    printf '%s' "$default_value"
}

resolve_bool_setting() {
    local config_value="$1"
    local prompt_label="$2"
    local default_value="$3"
    local prompt_mode="$4"

    if [[ -n "$config_value" ]]; then
        printf '%s' "$config_value"
        return 0
    fi

    if ! is_interactive; then
        printf '%s' "$default_value"
        return 0
    fi

    case "$prompt_mode" in
        default_yes)
            if prompt_confirm_default_yes "$prompt_label"; then
                printf 'true'
            else
                printf 'false'
            fi
            ;;
        *)
            if prompt_confirm_default_no "$prompt_label"; then
                printf 'true'
            else
                printf 'false'
            fi
            ;;
    esac
}

resolve_install_hooks() {
    if [[ "$INSTALL_HOOKS_MODE" == "true" ]]; then
        INSTALL_HOOKS="true"
        return 0
    fi

    if [[ "$INSTALL_HOOKS_MODE" == "false" ]]; then
        INSTALL_HOOKS="false"
        return 0
    fi

    INSTALL_HOOKS="$(resolve_bool_setting "$CFG_INSTALL_HOOKS" "是否安装 pre-commit 与 Git hooks" "false" "default_no")"
}

resolve_ai_collaboration_options() {
    AI_COLLAB_ENABLED="$(resolve_bool_setting "$CFG_AI_COLLAB_ENABLED" "是否启用 AI 协作模板" "false" "default_no")"

    if [[ "$AI_COLLAB_ENABLED" != "true" ]]; then
        AI_GITHUB_ENABLED="false"
        AI_CURSOR_ENABLED="false"
        AI_CLAUDE_ENABLED="false"
        AI_CODEX_ENABLED="false"
        AI_TRAE_ENABLED="false"
        return 0
    fi

    AI_GITHUB_ENABLED="$(resolve_bool_setting "$CFG_AI_GITHUB_ENABLED" "是否生成 GitHub 协作模板（Copilot / PR / Issue / CODEOWNERS 示例）" "true" "default_yes")"
    AI_CURSOR_ENABLED="$(resolve_bool_setting "$CFG_AI_CURSOR_ENABLED" "是否生成 Cursor 规则模板" "true" "default_yes")"
    AI_CLAUDE_ENABLED="$(resolve_bool_setting "$CFG_AI_CLAUDE_ENABLED" "是否生成 Claude Code 协作模板" "true" "default_yes")"
    AI_CODEX_ENABLED="$(resolve_bool_setting "$CFG_AI_CODEX_ENABLED" "是否生成 Codex 协作模板" "true" "default_yes")"
    AI_TRAE_ENABLED="$(resolve_bool_setting "$CFG_AI_TRAE_ENABLED" "是否生成 Trae 协作模板" "true" "default_yes")"

    if [[ "$AI_GITHUB_ENABLED" != "true" ]] \
        && [[ "$AI_CURSOR_ENABLED" != "true" ]] \
        && [[ "$AI_CLAUDE_ENABLED" != "true" ]] \
        && [[ "$AI_CODEX_ENABLED" != "true" ]] \
        && [[ "$AI_TRAE_ENABLED" != "true" ]]; then
        printf '提醒: 当前仅会生成 AI 主规范与仓库级 AGENTS.md，不会生成工具专属适配文件。\n'
    fi
}

copy_asset_relative_with_confirm() {
    local asset_relative_path="$1"
    local target_relative_path="${2:-$1}"

    mkdir -p "$(dirname "${TARGET_DIR}/${target_relative_path}")"
    copy_file_with_confirm \
        "${ASSETS_DIR}/${asset_relative_path}" \
        "${TARGET_DIR}/${target_relative_path}"
}

generate_ai_collaboration_assets() {
    if [[ "$AI_COLLAB_ENABLED" != "true" ]]; then
        return 0
    fi

    copy_asset_relative_with_confirm ".saitec/AI_COLLABORATION.md"
    copy_asset_relative_with_confirm "Skills.md" ".saitec/Skills.md"
    copy_asset_relative_with_confirm "AGENTS.md"

    if [[ "$AI_GITHUB_ENABLED" == "true" ]]; then
        copy_asset_relative_with_confirm ".github/copilot-instructions.md"
        copy_asset_relative_with_confirm ".github/pull_request_template.md"
        copy_asset_relative_with_confirm ".github/ISSUE_TEMPLATE/ai-task.yml"
        copy_asset_relative_with_confirm ".github/ISSUE_TEMPLATE/config.yml"
        copy_asset_relative_with_confirm ".github/CODEOWNERS.example"
    fi

    if [[ "$AI_CURSOR_ENABLED" == "true" ]]; then
        copy_asset_relative_with_confirm ".cursor/rules/ai-collaboration.mdc"
    fi

    if [[ "$AI_CLAUDE_ENABLED" == "true" ]]; then
        copy_asset_relative_with_confirm ".claude/CLAUDE.md"
    fi

    if [[ "$AI_CODEX_ENABLED" == "true" ]]; then
        copy_asset_relative_with_confirm ".codex/AGENTS.md"
    fi

    if [[ "$AI_TRAE_ENABLED" == "true" ]]; then
        copy_asset_relative_with_confirm ".trae/AGENTS.md"
    fi
}

render_saitec_config() {
    cat <<EOF
project_name = "$(escape_toml_string "$PROJECT_NAME")"
project_version = "$(escape_toml_string "$PROJECT_VERSION")"
python_version = "$(escape_toml_string "$PYTHON_VERSION")"
mypy_strict = $STRICT
install_hooks = $INSTALL_HOOKS
ai_collaboration = $AI_COLLAB_ENABLED
ai_github = $AI_GITHUB_ENABLED
ai_cursor = $AI_CURSOR_ENABLED
ai_claude = $AI_CLAUDE_ENABLED
ai_codex = $AI_CODEX_ENABLED
ai_trae = $AI_TRAE_ENABLED
EOF
}

parse_args() {
    local positional=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --interactive)
                INTERACTIVE_MODE="true"
                shift
                ;;
            --non-interactive)
                INTERACTIVE_MODE="false"
                shift
                ;;
            --config)
                [[ $# -ge 2 ]] || fail "--config 需要一个文件路径"
                CONFIG_FILE="$2"
                shift 2
                ;;
            --force)
                FORCE="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --install-hooks)
                INSTALL_HOOKS_MODE="true"
                shift
                ;;
            --no-install-hooks)
                INSTALL_HOOKS_MODE="false"
                shift
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            --)
                shift
                while [[ $# -gt 0 ]]; do
                    positional+=("$1")
                    shift
                done
                ;;
            -*)
                fail "未知选项: $1"
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    if [[ "${#positional[@]}" -gt 1 ]]; then
        fail "仅支持一个目标目录参数"
    fi

    if [[ "${#positional[@]}" -eq 1 ]]; then
        TARGET_DIR="${positional[0]}"
    fi
}

determine_interactive_mode() {
    if [[ "$INTERACTIVE_MODE" != "auto" ]]; then
        return 0
    fi

    if [[ -t 0 && -t 1 ]]; then
        INTERACTIVE_MODE="true"
    else
        INTERACTIVE_MODE="false"
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
    local requirements_file=""
    local pyproject_file=""
    local project_name_default=""
    local saitec_config_file=""

    parse_args "$@"
    determine_interactive_mode

    TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd || printf '%s' "$TARGET_DIR")"
    requirements_file="${TARGET_DIR}/requirements.txt"
    pyproject_file="${TARGET_DIR}/pyproject.toml"
    saitec_config_file="${TARGET_DIR}/.saitec/config.toml"

    if [[ -z "$CONFIG_FILE" && -f "$saitec_config_file" ]]; then
        CONFIG_FILE="$saitec_config_file"
    fi

    load_config_file

    if [[ ! -d "$TARGET_DIR" ]]; then
        fail "目标目录不存在: $TARGET_DIR"
    fi

    if [[ ! -f "${ASSETS_DIR}/.pre-commit-config.yaml" ]]; then
        fail "缺少模板文件: ${ASSETS_DIR}/.pre-commit-config.yaml"
    fi

    if [[ ! -f "${ASSETS_DIR}/.saitec/hooks/enforce-branch-law.sh" ]]; then
        fail "缺少模板文件: ${ASSETS_DIR}/.saitec/hooks/enforce-branch-law.sh"
    fi

    ensure_git_repository_or_confirm

    project_name_default="$(default_project_name "$TARGET_DIR")"
    PROJECT_NAME="$(resolve_string_setting "$CFG_PROJECT_NAME" "项目名称" "$project_name_default")"
    PROJECT_VERSION="$(resolve_string_setting "$CFG_PROJECT_VERSION" "项目版本" "$PROJECT_VERSION_DEFAULT")"
    PYTHON_VERSION="$(resolve_string_setting "$CFG_PYTHON_VERSION" "Python 版本要求" "$PYTHON_VERSION_DEFAULT")"
    PYTHON_VERSION="$(normalize_requires_python "$PYTHON_VERSION")"
    PYTHON_VERSION_REAL="$(extract_python_version_real "$PYTHON_VERSION")"
    PYTHON_VERSION_REAL_NOPOINT="${PYTHON_VERSION_REAL//./}"
    STRICT="$(resolve_bool_setting "$CFG_STRICT" "是否启用 mypy strict 模式" "$MYPY_STRICT_DEFAULT" "default_no")"

    resolve_ai_collaboration_options
    resolve_install_hooks

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
    copy_file_with_confirm "${ASSETS_DIR}/.README.md" "${TARGET_DIR}/.README.md"
    copy_asset_relative_with_confirm ".saitec/hooks/enforce-branch-law.sh"
    generate_ai_collaboration_assets

    ensure_directory "${TARGET_DIR}/.vscode"
    ensure_directory "${TARGET_DIR}/.cursor"
    ensure_directory "${TARGET_DIR}/.trae"
    ensure_directory "${TARGET_DIR}/.saitec"

    copy_file_with_confirm "${ASSETS_DIR}/settings.json" "${TARGET_DIR}/.vscode/settings.json"
    write_file_with_confirm "$saitec_config_file" "$(render_saitec_config)"

    ensure_pre_commit_available
    install_pre_commit_hook

    if [[ -f "$requirements_file" ]]; then
        printf '已检测到 requirements.txt，并尝试导入到 pyproject.toml 的 [project].dependencies。\n'
    else
        printf '未检测到 requirements.txt，已生成空的 dependencies 列表。\n'
    fi

    if [[ "$AI_COLLAB_ENABLED" == "true" ]]; then
        printf '已生成 AI 协作主规范与所选工具模板。\n'
        printf '提醒: .cursor/.claude/.codex/.trae 等本地工具目录是可重建产物，通常不需要提交到版本库。\n'
        printf '新成员 clone 仓库后，如需恢复本地 AI 工具入口，可执行: install.sh init --non-interactive .\n'
    else
        printf '未启用 AI 协作模板，仅生成基础工程配置。\n'
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        printf 'Dry run 完成，未写入任何文件。目标目录: %s\n' "$TARGET_DIR"
        return 0
    fi

    printf '初始化完成，目标目录: %s\n' "$TARGET_DIR"
}

main "$@"
