#!/usr/bin/env bash
# Dry-runs a merge of upstream Vorssaint into this fork and reports what a
# sync would touch: new upstream commits, any conflicts, and the upstream
# files the fork hooks into. Changes nothing; safe to run any time.
#
#   Tools/check-upstream.sh            # finds the Vorssaint remote itself
#   UPSTREAM_REMOTE=upstream Tools/check-upstream.sh
set -euo pipefail
cd "$(dirname "$0")/.."

remote="${UPSTREAM_REMOTE:-}"
if [ -z "$remote" ]; then
    for candidate in upstream origin; do
        url=$(git remote get-url "$candidate" 2>/dev/null || true)
        case "$url" in *vorssaint/vorssaint-utils*) remote=$candidate; break ;; esac
    done
fi
if [ -z "$remote" ]; then
    echo "Add Vorssaint as a remote first:"
    echo "  git remote add upstream https://github.com/vorssaint/vorssaint-utils.git"
    exit 1
fi

git fetch -q "$remote" main
upstream="$remote/main"
pending=$(git rev-list --count "HEAD..$upstream")
echo "Upstream commits not yet merged: $pending"
if [ "$pending" -gt 0 ]; then git log --oneline "HEAD..$upstream" | head -20; fi

echo
if result=$(git merge-tree --write-tree --name-only HEAD "$upstream" 2>/dev/null); then
    echo "A merge would be clean: no conflicts."
else
    echo "A merge would conflict in:"
    printf '%s\n' "$result" | sed -n '2,/^$/p' | sed '/^$/d; s/^/  /'
fi

base=$(git merge-base HEAD "$upstream")
echo
echo "Fork-only source files: $(git diff --diff-filter=A --name-only "$base" HEAD -- Sources | wc -l | tr -d ' ')"
echo "Upstream files the fork hooks into, most changed first:"
git diff --diff-filter=M --numstat "$base" HEAD -- Sources build.sh Tests/generate_sources.py \
    | sort -k1,1nr | awk '{ printf "  %5s+ %4s-  %s\n", $1, $2, $3 }'
