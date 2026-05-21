#!/usr/bin/env bash
set -euo pipefail

INTEGRATION="duocnv"
BASE="main"
UPSTREAM_REMOTE="origin"
FORK_REMOTE="fork"

PUSH=false
[[ "${1:-}" == "--push" ]] && PUSH=true

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "error: working tree has uncommitted changes; commit or stash first" >&2
  exit 1
fi

mapfile -t TOPICS < <(git config --get-all integration.topic || true)
if [[ ${#TOPICS[@]} -eq 0 ]]; then
  echo "error: no topic branches configured" >&2
  echo "       add one with: git config --add integration.topic <branch>" >&2
  exit 1
fi

git fetch "$UPSTREAM_REMOTE" --quiet

git checkout "$BASE" --quiet
git merge --ff-only "$UPSTREAM_REMOTE/$BASE" --quiet
echo "synced $BASE with $UPSTREAM_REMOTE/$BASE"

git checkout -B "$INTEGRATION" "$BASE" --quiet
echo "reset $INTEGRATION to $BASE"

for topic in "${TOPICS[@]}"; do
  if ! git rev-parse --verify --quiet "refs/heads/$topic" >/dev/null; then
    echo "skipped $topic (branch not found)"
    continue
  fi
  if git merge --no-edit "$topic" --quiet; then
    echo "merged $topic"
  else
    echo "conflict merging $topic" >&2
    echo "resolve it, run 'git commit', then re-run this script" >&2
    exit 1
  fi
done

if $PUSH; then
  git push --force-with-lease "$FORK_REMOTE" "$INTEGRATION"
  echo "pushed $INTEGRATION to $FORK_REMOTE"
fi

echo "done: $INTEGRATION = $BASE + ${#TOPICS[@]} topic branch(es)"
