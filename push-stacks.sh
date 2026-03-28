#!/usr/bin/env bash
set -euo pipefail

if (($# > 0)); then
  echo "Usage: $(basename "$0")" >&2
  echo "Push the current branch of each configured homelab stack repo to its configured upstream." >&2
  exit 64
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Mirrors the stack list documented in /srv/homelab/CLAUDE.md.
stacks=(
  "network-stack"
  "infra-stack"
  "smart-home-stack"
  "homelab-maestro"
  "homelab-n8n-workflows"
  "homelab-template"
  "n8n-gitops"
)

declare -a pushed=()
declare -a skipped=()
declare -a failed=()

for stack in "${stacks[@]}"; do
  stack_dir="$ROOT_DIR/$stack"

  if [[ ! -d "$stack_dir/.git" ]]; then
    skipped+=("$stack: not a git repository")
    continue
  fi

  if ! branch="$(git -C "$stack_dir" symbolic-ref --quiet --short HEAD)"; then
    failed+=("$stack: detached HEAD")
    continue
  fi

  if [[ -n "$(git -C "$stack_dir" status --short)" ]]; then
    failed+=("$stack: dirty worktree")
    continue
  fi

  if ! upstream="$(git -C "$stack_dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"; then
    failed+=("$stack: no upstream configured for $branch")
    continue
  fi

  ahead_behind="$(git -C "$stack_dir" rev-list --left-right --count "${upstream}...HEAD")"
  behind_count="${ahead_behind%%$'\t'*}"
  ahead_count="${ahead_behind##*$'\t'}"

  if [[ "$behind_count" != "0" ]]; then
    failed+=("$stack: branch $branch is behind $upstream")
    continue
  fi

  if [[ "$ahead_count" == "0" ]]; then
    skipped+=("$stack: nothing to push on $branch")
    continue
  fi

  echo "[push] $stack ($branch -> $upstream)"
  if git -C "$stack_dir" push; then
    pushed+=("$stack")
  else
    failed+=("$stack: git push failed")
  fi
done

echo
echo "Push summary:"

if ((${#pushed[@]} > 0)); then
  printf '  pushed: %s\n' "${pushed[@]}"
fi

if ((${#skipped[@]} > 0)); then
  printf '  skipped: %s\n' "${skipped[@]}"
fi

if ((${#failed[@]} > 0)); then
  printf '  failed: %s\n' "${failed[@]}" >&2
  exit 1
fi
