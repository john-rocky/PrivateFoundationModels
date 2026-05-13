#!/usr/bin/env bash
# Open all four social post drafts (X, HN, r/swift, r/iOSProgramming)
# in your default browser as pre-filled tabs. Click → review → press
# Submit / Post in each tab.
#
# Usage:
#   ./bin/post-tabs.sh
#
# Pulls the URLs from docs/POST_NOW.md so they stay in sync with the
# latest release's social copy.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POST_FILE="${REPO_ROOT}/docs/POST_NOW.md"

if [[ ! -f "${POST_FILE}" ]]; then
  echo "Missing ${POST_FILE}" >&2
  exit 1
fi

# Extract each launcher URL by matching the markdown link inside the
# **→ Post / Submit** anchors. The launcher line format is
# `[**→ ...**](https://...)`.
URLS=$(grep -Eo '\(https://[^)]+\)' "${POST_FILE}" \
       | head -4 \
       | sed 's/^(\(.*\))$/\1/')

if [[ -z "${URLS}" ]]; then
  echo "No URLs found in ${POST_FILE}" >&2
  exit 2
fi

echo "Opening these tabs in your default browser:"
echo "${URLS}" | sed 's/^/  - /'
echo

# `open` is macOS only; on Linux fall back to xdg-open.
opener="open"
command -v open >/dev/null 2>&1 || opener="xdg-open"

while IFS= read -r url; do
  "${opener}" "${url}"
  sleep 0.4  # let the browser focus catch up
done <<< "${URLS}"
