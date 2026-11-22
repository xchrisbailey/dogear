#!/usr/bin/env bash
# Merges a pushed branch into a target branch in a throwaway worktree, runs the fast checks,
# and pushes. The main checkout is never switched, so it stays clean and keeps its build cache.
#
#   scripts/merge-branch.sh <branch> [target=main] [message]
#   MERGE_APP_TESTS=1 scripts/merge-branch.sh …   also runs seam 2 (slow; CI runs it anyway)
set -euo pipefail
cd "$(dirname "$0")/.."

branch="${1:?usage: $0 <branch> [target] [message]}"
target="${2:-main}"
message="${3:-merge: $branch}"

git fetch -q origin "$branch" "$target"
dir="$(mktemp -d "${TMPDIR:-/tmp}/dogear-merge.XXXXXX")"
cleanup() { git worktree remove --force "$dir" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM

git worktree add -q --detach "$dir" "origin/$target"
cd "$dir"
git merge -q --no-ff -m "$message" "origin/$branch"

scripts/check-secrets.sh --all
scripts/check-architecture.sh
swift test --package-path Core -q
[[ "${MERGE_APP_TESTS:-0}" == 1 ]] && scripts/app.sh test

git push -q origin "HEAD:$target"
echo "Merged $branch into $target at $(git rev-parse --short HEAD)."
