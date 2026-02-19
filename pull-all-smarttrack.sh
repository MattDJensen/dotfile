#!/usr/bin/env bash
set -euo pipefail

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
  echo "Aborting pull. Uncommitted changes detected in:"
  for repo in "${DIRTY_REPOS[@]}"; do
    echo "  - $repo"
  done
  echo ""
  echo "Commit/stash/discard changes, then rerun."
  exit 2
fi

echo ""
echo "Pulling all SmartTrack repos..."
echo ""

for repo in "${REPOS[@]}"; do
  REPO_PATH="$ROOT_DIR/$repo"
  echo "==> $repo"

  if ! git -C "$REPO_PATH" remote get-url origin >/dev/null 2>&1; then
    echo "Skipping (no origin remote)"
    echo ""
    continue
  fi

  git -C "$REPO_PATH" fetch origin --prune

  if git -C "$REPO_PATH" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    git -C "$REPO_PATH" pull --rebase --autostash
  else
    CURRENT_BRANCH="$(git -C "$REPO_PATH" rev-parse --abbrev-ref HEAD)"
    if git -C "$REPO_PATH" show-ref --verify --quiet "refs/remotes/origin/$CURRENT_BRANCH"; then
      git -C "$REPO_PATH" branch --set-upstream-to="origin/$CURRENT_BRANCH" "$CURRENT_BRANCH"
      git -C "$REPO_PATH" pull --rebase --autostash
    else
      echo "Skipping pull (no upstream set for branch '$CURRENT_BRANCH')"
    fi
  fi

  echo ""
done

echo "Done."
