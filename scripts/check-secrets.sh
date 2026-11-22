#!/usr/bin/env bash
# Fails if tracked or staged content carries secrets or private details. The repo is public.
#
#   scripts/check-secrets.sh           scans staged changes (pre-commit hook)
#   scripts/check-secrets.sh --all     scans every tracked file (CI)
#
# Built-in patterns catch credentials of any kind. Private details (server hostnames, test
# account passwords) can't be listed here without publishing them, so they're read from a
# local file outside the repo: one extended regex per line, # for comments.
set -euo pipefail
cd "$(dirname "$0")/.."

patterns=(
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}'   # JWTs (access and refresh tokens)
  'ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}'
)
local_file="${DOGEAR_SECRET_PATTERNS:-$HOME/.config/dogear/secret-patterns}"
if [[ -f "$local_file" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] || patterns+=("$line")
  done < "$local_file"
fi
regex="$(IFS='|'; echo "${patterns[*]}")"

if [[ "${1:-}" == "--all" ]]; then
  files="$(git ls-files)"
  hits="$(git grep -n -I -E -e "$regex" -- . || true)"
else
  files="$(git diff --cached --name-only --diff-filter=ACMR)"
  hits="$(git diff --cached -U0 --diff-filter=ACMR | grep -E '^\+[^+]' | grep -n -E -e "$regex" || true)"
fi

bad_files="$(grep -E '(^|/)(AuthKey_[^/]*\.p8|[^/]*\.p12|[^/]*\.mobileprovision|\.env[^/]*)$' <<<"$files" || true)"

if [[ -n "$hits" || -n "$bad_files" ]]; then
  echo "check-secrets: possible secret or private detail. Remove it, or adjust the patterns if it's a false positive." >&2
  [[ -n "$bad_files" ]] && echo "$bad_files" | sed 's/^/  file: /' >&2
  [[ -n "$hits" ]] && echo "$hits" | cut -c1-160 | sed 's/^/  /' >&2
  exit 1
fi
