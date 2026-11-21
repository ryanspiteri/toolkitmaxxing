#!/usr/bin/env bash
# Fails if a plugin changed between <base> and HEAD without a new `version` in its plugin.json.
# Usage: check-version-bump.sh <base-sha>
# A missing or all-zero base (first push of a branch) skips the check.
set -euo pipefail
base="${1:-}"
if [ -z "$base" ] || [ -z "${base//0/}" ] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then
  echo "no usable base commit ('$base'); skipping version check"
  exit 0
fi

fail=0
plugins="$(git diff --name-only "$base...HEAD" -- plugins | cut -d/ -f2 | sort -u)"
for name in $plugins; do
  manifest="plugins/$name/.claude-plugin/plugin.json"
  if [ ! -f "$manifest" ]; then
    echo "$name: removed, nothing to check"
    continue
  fi
  if ! old_json="$(git show "$(git merge-base "$base" HEAD):$manifest" 2>/dev/null)"; then
    echo "$name: new plugin, nothing to compare"
    continue
  fi
  old="$(printf '%s' "$old_json" | jq -r .version)"
  new="$(jq -r .version "$manifest")"
  if [ "$old" = "$new" ]; then
    echo "FAIL $name: files changed but version is still $old in $manifest. Bump it, or friends will not get the update."
    fail=1
  else
    echo "ok   $name: $old -> $new"
  fi
done
[ -n "$plugins" ] || echo "no plugin changes"
exit "$fail"
