#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLY=false

if [ "${1:-}" = "--apply" ]; then
  APPLY=true
elif [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  echo "Usage: ./prune-local-branches-smarttrack.sh [--apply]"
  echo "  default   Dry run (shows branches that would be deleted)"
  echo "  --apply   Actually delete local branches not present on origin"
  exit 0
fi

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

if [ "$APPLY" = false ]; then
  echo "Dry run mode. No branches will be deleted."
  echo "Run with --apply to delete."
fi

echo ""

total_candidates=0
total_deleted=0

for repo in "${REPOS[@]}"; do
  REPO_PATH="$ROOT_DIR/$repo"
  echo "==> $repo"

  if ! git -C "$REPO_PATH" remote get-url origin >/dev/null 2>&1; then
    echo "Skipping (no origin remote)"
    echo ""
    continue
  fi

  git -C "$REPO_PATH" fetch origin --prune >/dev/null

  current_branch="$(git -C "$REPO_PATH" rev-parse --abbrev-ref HEAD)"

  repo_candidates=0
  repo_deleted=0

  while IFS= read -r branch; do
    [ -z "$branch" ] && continue

    if [ "$branch" = "$current_branch" ]; then
      continue
    fi

    if git -C "$REPO_PATH" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      continue
    fi

    repo_candidates=$((repo_candidates + 1))
    total_candidates=$((total_candidates + 1))

    if [ "$APPLY" = true ]; then
      if git -C "$REPO_PATH" branch -D "$branch" >/dev/null 2>&1; then
        echo "deleted: $branch"
        repo_deleted=$((repo_deleted + 1))
        total_deleted=$((total_deleted + 1))
      else
        echo "failed to delete: $branch"
      fi
    else
      echo "would delete: $branch"
    fi
  done < <(git -C "$REPO_PATH" for-each-ref --format='%(refname:short)' refs/heads)

  if [ "$repo_candidates" -eq 0 ]; then
    echo "No local-only branches found."
  elif [ "$APPLY" = true ]; then
    echo "Deleted $repo_deleted/$repo_candidates branches."
  else
    echo "Found $repo_candidates local-only branches."
  fi

  echo ""
done

if [ "$APPLY" = true ]; then
  echo "Done. Deleted $total_deleted/$total_candidates branches across all repos."
else
  echo "Dry run complete. Found $total_candidates local-only branches across all repos."
fi
