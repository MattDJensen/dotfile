#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: ./switch-all-smarttrack.sh <branch-name>"
  exit 1
fi

TARGET_BRANCH="$1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPOS=()
while IFS= read -r repo; do
  REPOS+=("$repo")
done < <(
  find "$ROOT_DIR" -maxdepth 1 -mindepth 1 -type d -name 'SmartTrack*' -print \
    | while IFS= read -r repo; do
        if git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
          basename "$repo"
        fi
      done \
    | sort
)

if [ "${#REPOS[@]}" -eq 0 ]; then
  echo "No SmartTrack git repositories found under $ROOT_DIR"
  exit 1
fi

echo "Checking for uncommitted changes..."
DIRTY_REPOS=()
for repo in "${REPOS[@]}"; do
  if [ -n "$(git -C "$ROOT_DIR/$repo" status --porcelain)" ]; then
    DIRTY_REPOS+=("$repo")
  fi
done

if [ "${#DIRTY_REPOS[@]}" -gt 0 ]; then
  echo ""
  echo "Aborting branch switch. Uncommitted changes detected in:"
  for repo in "${DIRTY_REPOS[@]}"; do
    echo "  - $repo"
  done
  echo ""
  echo "Commit/stash/discard changes, then rerun."
  exit 2
fi

echo ""
echo "Switching all SmartTrack repos to branch: $TARGET_BRANCH"
echo ""

for repo in "${REPOS[@]}"; do
  REPO_PATH="$ROOT_DIR/$repo"
  echo "==> $repo"

  if git -C "$REPO_PATH" remote get-url origin >/dev/null 2>&1; then
    git -C "$REPO_PATH" fetch origin --prune
  fi

  if git -C "$REPO_PATH" show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"; then
    git -C "$REPO_PATH" switch "$TARGET_BRANCH"
  elif git -C "$REPO_PATH" show-ref --verify --quiet "refs/remotes/origin/$TARGET_BRANCH"; then
    git -C "$REPO_PATH" switch --track "origin/$TARGET_BRANCH"
  else
    git -C "$REPO_PATH" switch -c "$TARGET_BRANCH"
  fi

  if git -C "$REPO_PATH" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    git -C "$REPO_PATH" pull --rebase --autostash
  fi

  echo ""
done

echo "Done."
