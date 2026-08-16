#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-status}"
HOST="github.com"
export GH_PAGER=cat

have_env_token=0
if [[ -n "${GH_TOKEN:-}" || -n "${GITHUB_TOKEN:-}" ]]; then
  have_env_token=1
fi

credential_source() {
  if (( have_env_token )); then
    printf '%s\n' environment
    return 0
  fi
  if gh auth token --hostname "$HOST" >/dev/null 2>&1; then
    printf '%s\n' stored
    return 0
  fi
  printf '%s\n' none
}

status() {
  command -v gh >/dev/null 2>&1 || { echo "GitHub CLI is unavailable." >&2; return 1; }
  local source account repo_info
  source="$(credential_source)"
  printf 'GitHub CLI: %s\n' "$(gh --version | sed -n '1p')"
  printf 'Credential source: %s\n' "$source"

  if [[ "$source" == none ]]; then
    echo "GitHub authentication is required. Run: agent-env github-auth" >&2
    return 2
  fi

  if ! gh auth status --active --hostname "$HOST" >/dev/null 2>&1; then
    echo "A GitHub credential exists but failed validation. Check network/token state before re-authenticating." >&2
    return 1
  fi

  if ! account="$(gh api user --jq '.login' 2>/dev/null)" || [[ -z "$account" ]]; then
    echo "GitHub authentication exists but the API is unreachable or rejected the credential." >&2
    return 1
  fi
  printf 'API: ready as %s\n' "$account"

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if repo_info="$(gh repo view --json nameWithOwner,viewerPermission --jq '[.nameWithOwner,.viewerPermission] | @tsv' 2>/dev/null)" && [[ -n "$repo_info" ]]; then
      printf 'Repository: %s\n' "$repo_info"
    else
      echo "Repository: local Git repository detected; GitHub repository access could not be resolved." >&2
      return 1
    fi
  else
    echo "Repository: no local Git worktree detected (authentication itself is ready)."
  fi
}

auth() {
  command -v gh >/dev/null 2>&1 || { echo "GitHub CLI is unavailable." >&2; return 1; }

  if (( have_env_token )); then
    echo "GH_TOKEN or GITHUB_TOKEN is set and takes precedence over stored GitHub CLI credentials." >&2
    echo "Fix that environment token, or unset it in this shell before using interactive OAuth." >&2
    return 2
  fi

  local source
  source="$(credential_source)"
  if [[ "$source" == stored ]]; then
    if status >/dev/null 2>&1; then
      echo "GitHub authentication is already ready."
      status
      return 0
    fi
    echo "A stored GitHub credential exists but is not currently usable." >&2
    echo "Not replacing it automatically: diagnose network/credential state with 'agent-env github' first." >&2
    return 1
  fi

  echo "Starting GitHub's interactive browser/device authorization flow."
  echo "Do not paste an access token into chat. Complete the one-time authorization GitHub presents."
  gh auth login --hostname "$HOST" --git-protocol https --web
  echo
  status
}

case "$MODE" in
  status) status ;;
  auth) auth ;;
  -h|--help|help)
    cat <<'USAGE'
Usage: github.sh [status|auth]

status  Validate credential presence, GitHub API access, and current-repo access.
auth    Start interactive GitHub OAuth when no environment token overrides it, then verify.

Exit status from status:
  0  GitHub API is ready (and current repo is accessible when in a Git worktree)
  1  A credential/tool exists but access is unusable or could not be verified
  2  No GitHub credential source exists; interactive authentication is appropriate
USAGE
    ;;
  *) echo "Unknown mode: $MODE" >&2; exit 2 ;;
esac
