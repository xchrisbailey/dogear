#!/usr/bin/env bash
# Fails when Server traffic bypasses Account. Account owns token refresh (single-flight),
# offline detection and "server changed" classification; a request sent around it loses all three.
#
# Allowed network senders:
#   Account.swift              authenticated requests
#   GrimmoryClient.swift       sign-in and refresh, which run before there's a token to manage
#   BackgroundTransport.swift  Downloads, which iOS runs in a background URLSession
set -euo pipefail
cd "$(dirname "$0")/.."

allowed='(Core/Sources/DogearCore/(Account|GrimmoryClient)|App/Downloads/BackgroundTransport)\.swift'
sends='\.(data|upload|download|bytes)\(for:|URLSession\.shared|URLSession\(|\.dataTask\(|\.downloadTask\('

hits="$(git grep -n -E -e "$sends" -- 'App/*.swift' 'Core/Sources/*.swift' |
  grep -v -E "^$allowed:" | grep -v -E '^[^:]+:[0-9]+:\s*//' || true)"

if [[ -n "$hits" ]]; then
  echo "check-architecture: send Server requests through Account.fetch/fetchData/deliver/send:" >&2
  echo "$hits" | sed 's/^/  /' >&2
  exit 1
fi
