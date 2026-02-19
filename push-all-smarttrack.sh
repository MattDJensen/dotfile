#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLY=false

if [ "${1:-}" = "--apply" ]; then
  APPLY=true
elif [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  echo "Usage: ./push-all-smarttrack.sh [--apply]"
  echo "  default   Dry run (shows what would be pushed)"
  echo "  --apply   Actually push eligible branches"
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
  echo "Dry run mode. No pushes will be performed."
  echo "Run with --apply to push."
fi

echo ""

total_candidates=0
total_pushed=0

for repo in "${REPOS[@]}"; do
  REPO_PATH="$ROOT_DIR/$repo"
  echo "==> $repo"

  if ! git -C "$REPO_PATH" remote get-url origin >/dev/null 2>&1; then
    echo "Skipping (no origin remote)"
    echo ""
    continue
  fi

  if [ -n "$(git -C "$REPO_PATH" status --porcelain)" ]; then
    echo "Skipping (uncommitted changes present)"
    echo ""
    continue
  fi

  git -C "$REPO_PATH" fetch origin --prune >/dev/null

  branch="$(git -C "$REPO_PATH" rev-parse --abbrev-ref HEAD)"
  if [ "$branch" = "HEAD" ]; then
    echo "Skipping (detached HEAD)"
    echo ""
    continue
  fi

  has_upstream=false
  upstream_ref=""
  if upstream_ref="$(git -C "$REPO_PATH" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
    has_upstream=true
  fi

  should_push=false
  reason=""

  if [ "$has_upstream" = true ]; then
    ahead_count="$(git -C "$REPO_PATH" rev-list --count "${upstream_ref}..HEAD")"
    if [ "$ahead_count" -gt 0 ]; then
      should_push=true
      reason="ahead by $ahead_count commit(s)"
    else
      reason="no commits to push"
    fi
  else
    if git -C "$REPO_PATH" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      ahead_count="$(git -C "$REPO_PATH" rev-list --count "origin/$branch..HEAD")"
      if [ "$ahead_count" -gt 0 ]; then
        should_push=true
        reason="ahead by $ahead_count commit(s)"
      else
        reason="no commits to push"
      fi
    else
      default_remote_head="$(git -C "$REPO_PATH" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
      if [ -n "$default_remote_head" ]; then
        unique_count="$(git -C "$REPO_PATH" rev-list --count "$default_remote_head..HEAD")"
      else
        unique_count="1"
      fi

      if [ "$unique_count" -gt 0 ]; then
        should_push=true
        reason="new branch with $unique_count unique commit(s)"
      else
        reason="new branch has no unique commits"
      fi
    fi
  fi

  if [ "$should_push" = true ]; then
    total_candidates=$((total_candidates + 1))
    if [ "$APPLY" = true ]; then
      if [ "$has_upstream" = true ] || git -C "$REPO_PATH" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        git -C "$REPO_PATH" push
      else
        git -C "$REPO_PATH" push -u origin "$branch"
      fi
      total_pushed=$((total_pushed + 1))
      echo "Pushed ($reason)"
    else
      echo "Would push ($reason)"
    fi
  else
    echo "Skipping ($reason)"
  fi

  echo ""
done

if [ "$APPLY" = true ]; then
  echo "Done. Pushed $total_pushed/$total_candidates eligible repo branch(es)."
else
  echo "Dry run complete. Found $total_candidates eligible repo branch(es) to push."
fi
