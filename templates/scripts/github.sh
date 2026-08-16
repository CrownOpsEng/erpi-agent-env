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

repo_remote() {
  local branch remote
  branch="$(git branch --show-current 2>/dev/null || true)"
  if [[ -n "$branch" ]]; then
    remote="$(git config --get "branch.${branch}.remote" 2>/dev/null || true)"
    if [[ -n "$remote" && "$remote" != "." ]]; then
      git remote get-url --push "$remote" 2>/dev/null && return 0
    fi
  fi
  git remote get-url --push origin 2>/dev/null || git remote get-url origin 2>/dev/null
}

report_git_auth() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local remote helpers
  remote="$(repo_remote 2>/dev/null || true)"
  case "$remote" in
    https://github.com/*)
      helpers="$(git config --local --get-all credential.https://github.com.helper 2>/dev/null || true)"
      if grep -Fxq '!gh auth git-credential' <<<"$helpers"; then
        echo "Git push auth: repo-local gh helper ready."
      else
        echo "Git push auth: HTTPS GitHub remote detected; run 'agent-env github-git' before push."
      fi
      ;;
    git@github.com:*|ssh://git@github.com/*)
      echo "Git push auth: SSH GitHub remote; host SSH credentials are required."
      ;;
    "")
      echo "Git push auth: no push remote detected."
      ;;
    *)
      echo "Git push auth: non-GitHub remote; host Git authentication applies."
      ;;
  esac
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
    report_git_auth
  else
    echo "Repository: no local Git worktree detected (authentication itself is ready)."
  fi
}

git_ready() {
  command -v git >/dev/null 2>&1 || { echo "Host Git is unavailable." >&2; return 1; }
  status || return $?
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Git push readiness requires a local Git worktree." >&2
    return 2
  }

  local branch remote remote_name helpers
  branch="$(git branch --show-current 2>/dev/null || true)"
  [[ -n "$branch" ]] || { echo "Git push readiness requires a named local branch." >&2; return 2; }
  remote_name="$(git config --get "branch.${branch}.remote" 2>/dev/null || true)"
  if [[ -z "$remote_name" || "$remote_name" == "." ]]; then
    remote_name=origin
  fi
  remote="$(git remote get-url --push "$remote_name" 2>/dev/null || git remote get-url "$remote_name" 2>/dev/null || true)"
  [[ -n "$remote" ]] || { echo "No push remote could be resolved for the current branch." >&2; return 2; }

  case "$remote" in
    https://github.com/*)
      # Scope this helper to the current repository and keep it location-neutral.
      # `gh auth setup-git` writes an absolute gh path into global Git config,
      # which is inappropriate for a relocatable bundle.
      git config --local --replace-all credential.https://github.com.helper ''
      git config --local --add credential.https://github.com.helper '!gh auth git-credential'
      helpers="$(git config --local --get-all credential.https://github.com.helper 2>/dev/null || true)"
      grep -Fxq '!gh auth git-credential' <<<"$helpers" || {
        echo "Could not configure the repo-local GitHub CLI credential helper." >&2
        return 1
      }
      ;;
    git@github.com:*|ssh://git@github.com/*)
      echo "Current push remote uses SSH; GitHub CLI OAuth is not used for Git transport."
      ;;
    *)
      echo "Current push remote is not github.com: $remote" >&2
      return 2
      ;;
  esac

  if ! git push --dry-run --no-verify "$remote_name" "HEAD:refs/heads/${branch}" >/dev/null 2>&1; then
    echo "Git push dry-run failed. Check network, repository permission, branch policy, or SSH credentials." >&2
    return 1
  fi

  if [[ "$remote" == https://github.com/* ]]; then
    echo "Git push dry-run: ready for ${remote_name}/${branch} using repo-local gh credentials."
  else
    echo "Git push dry-run: ready for ${remote_name}/${branch} over SSH."
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

  echo "Starting GitHub's browser/device authorization flow."
  echo "Do not paste an access token into chat. Complete the one-time authorization GitHub presents."
  # Disable terminal prompts so gh cannot offer to write a global Git credential
  # helper containing this relocatable bundle's current absolute path.
  GH_PROMPT_DISABLED=1 gh auth login --hostname "$HOST" --git-protocol https --web
  echo
  status
}

case "$MODE" in
  status) status ;;
  auth) auth ;;
  git) git_ready ;;
  -h|--help|help)
    cat <<'USAGE'
Usage: github.sh [status|auth|git]

status  Validate credential presence, GitHub API access, and current-repo access.
auth    Start browser/device OAuth when no environment token overrides it, then verify.
git     Configure current-repo Git transport safely and verify push with --dry-run --no-verify.

Exit status from status:
  0  GitHub API is ready (and current repo is accessible when in a Git worktree)
  1  A credential/tool exists but access is unusable or could not be verified
  2  No GitHub credential source exists; interactive authentication is appropriate
USAGE
    ;;
  *) echo "Unknown mode: $MODE" >&2; exit 2 ;;
esac
