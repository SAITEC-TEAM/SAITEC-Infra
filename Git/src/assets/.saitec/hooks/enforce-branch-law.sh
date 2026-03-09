#!/usr/bin/env bash

set -euo pipefail

readonly ALLOWED_BRANCH_PATTERN='^(feat|fix|new)/[a-z0-9._-]+$'

current_branch() {
    git symbolic-ref --quiet --short HEAD 2>/dev/null || true
}

fail() {
    printf 'SAITEC branch law violation: %s\n' "$1" >&2
    exit 1
}

check_branch_name() {
    local branch_name=""

    branch_name="$(current_branch)"
    if [[ -z "$branch_name" ]]; then
        return 0
    fi

    if [[ "$branch_name" =~ $ALLOWED_BRANCH_PATTERN ]]; then
        return 0
    fi

    fail "branch '${branch_name}' is not allowed. Use feat/<topic>, fix/<topic>, or new/<topic>."
}

block_main_push() {
    local local_ref=""
    local local_sha=""
    local remote_ref=""
    local remote_sha=""

    while read -r local_ref local_sha remote_ref remote_sha; do
        if [[ "$remote_ref" == "refs/heads/main" ]]; then
            fail "direct pushes to remote branch 'main' are forbidden. Open a pull request instead."
        fi
    done
}

main() {
    local mode="${1:-}"

    case "$mode" in
        check-branch-name)
            check_branch_name
            ;;
        block-main-push)
            block_main_push
            ;;
        *)
            fail "unknown enforcement mode '${mode}'."
            ;;
    esac
}

main "$@"
