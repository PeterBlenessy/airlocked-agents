#!/usr/bin/env bash
# scripts/bootstrap-repo.sh — initialize git and create+push the GitHub repo via the gh CLI.
# Safe by default: refuses to proceed if secrets would be committed, and confirms before pushing.
set -euo pipefail

REPO_NAME="${1:-airlocked-agents}"
VISIBILITY="${2:-private}"   # private | public

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# --- Preconditions ---
command -v git >/dev/null || { echo "git not found."; exit 1; }
command -v gh  >/dev/null || { echo "GitHub CLI (gh) not found — install it: https://cli.github.com"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Not logged in to gh — run: gh auth login"; exit 1; }

# --- Init repo if needed ---
if [ ! -d .git ]; then
  git init -q
  git branch -M main
fi

# --- Secret guard: never let .env / keys / rendered configs get staged ---
git add -A
LEAK="$(git diff --cached --name-only | grep -E '(^\.env$|\.key$|\.pem$|wireguard/.*\.conf$|^secrets/)' | grep -v '^secrets/\.gitkeep$' || true)"
if [ -n "$LEAK" ]; then
  echo "Refusing to commit — these secret-like files are staged:"
  echo "$LEAK"
  echo "Check .gitignore, unstage them (git rm --cached <file>), and retry."
  exit 1
fi

# --- Commit ---
if git rev-parse HEAD >/dev/null 2>&1; then
  git commit -qm "chore: update airlocked-agents IaC" || echo "Nothing new to commit."
else
  git commit -qm "Initial commit: privacy-first automation stack (IaC)"
fi

# --- Confirm, then create + push ---
echo
echo "About to create GitHub repo '$REPO_NAME' ($VISIBILITY) and push 'main'."
read -r -p "Proceed? [y/N] " ans
[[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

if gh repo view "$REPO_NAME" >/dev/null 2>&1; then
  echo "Repo exists — pushing to it."
  git remote get-url origin >/dev/null 2>&1 || \
    git remote add origin "$(gh repo view "$REPO_NAME" --json sshUrl -q .sshUrl)"
  git push -u origin main
else
  gh repo create "$REPO_NAME" --"$VISIBILITY" --source=. --remote=origin --push
fi

# --- Discoverability: set topics + description (idempotent; re-adding is a no-op) ---
TOPICS="infrastructure-as-code,ansible,docker-compose,self-hosted,ai-agents,privacy,security,llm,local-first,n8n,mcp,homelab,prompt-injection,automation,llama-cpp"
DESC="Deterministic IaC for a private, self-hosted AI automation stack — untrusted content stays in the airlock."
gh repo edit --add-topic "$TOPICS" --description "$DESC" \
  || echo "Could not set topics/description automatically — add them in the repo UI."

echo "Done. Repo: $(gh repo view "$REPO_NAME" --json url -q .url 2>/dev/null || echo "$REPO_NAME")"
