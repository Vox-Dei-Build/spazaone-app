#!/usr/bin/env bash
# scripts/purge-secrets.sh
#
# Rewrites git history to remove leaked secrets, then force-pushes.
#
# WHAT IT REMOVES (all paths, full history, every branch & tag):
#   - functions/.env.local
#   - functions/.env.default
#   - functions/.runtimeconfig.json
#   - pasella-ledger-firebase-adminsdk-av7ho-985ee21a3d.json
#   - pasella-ledger-430d249a5061.json
#   - any *-adminsdk-*.json
#
# DO NOT run this in your normal working clone — it operates on a fresh
# `--mirror` clone so the rewrite is clean and complete.
#
# REQUIREMENTS:
#   - git-filter-repo  (brew install git-filter-repo)
#   - Repo admin rights (force-push to protected branches)
#
# PREREQUISITES — DO THESE FIRST:
#   1. Rotate every credential that was ever in those files
#      (Paystack keys, Twilio token, Mailgun key, Firebase service-account key).
#   2. Confirm with the team that a force-push window is OK.
#   3. Make sure CI doesn't auto-deploy off a moved HEAD.
#
# AFTER RUNNING:
#   - Tell every collaborator to delete their old clone and re-clone.
#   - Open a GitHub Support ticket asking them to purge the cached blobs
#     for SHAs e5d90fa and cfda865 (and any others surfaced by gitleaks).
#   - Enable GitHub Secret Scanning + Push Protection.
#   - Audit forks; ask GitHub to take down any that retain the secrets.

set -euo pipefail

REPO_URL="${1:-}"
if [[ -z "$REPO_URL" ]]; then
  cat >&2 <<EOF
Usage: $0 git@github.com:<org>/<repo>.git

Example:
  $0 git@github.com:pasella/pasella-ledger.git
EOF
  exit 2
fi

if ! command -v git-filter-repo >/dev/null 2>&1; then
  echo "git-filter-repo not found. Install: brew install git-filter-repo" >&2
  exit 1
fi

WORKDIR="$(mktemp -d -t purge-secrets-XXXXXX)"
echo "[purge] Working in $WORKDIR"
cd "$WORKDIR"

echo "[purge] Mirror-cloning $REPO_URL"
git clone --mirror "$REPO_URL" repo.git
cd repo.git

echo "[purge] Rewriting history (removing leaked files from every commit)"
git filter-repo \
  --force \
  --invert-paths \
  --path functions/.env.local \
  --path functions/.env.default \
  --path functions/.runtimeconfig.json \
  --path pasella-ledger-firebase-adminsdk-av7ho-985ee21a3d.json \
  --path pasella-ledger-430d249a5061.json \
  --path-glob '*-adminsdk-*.json'

echo
echo "[purge] Rewrite complete. Review with:"
echo "    cd $WORKDIR/repo.git && git log --all --oneline | head"
echo
read -r -p "[purge] Force-push rewritten history to origin? [y/N] " confirm
case "$confirm" in
  y|Y|yes|YES)
    # filter-repo strips the remote; re-add it.
    git remote add origin "$REPO_URL"
    echo "[purge] Pushing branches..."
    git push --force --prune origin '+refs/heads/*:refs/heads/*'
    echo "[purge] Pushing tags..."
    git push --force --prune origin '+refs/tags/*:refs/tags/*'
    echo "[purge] Done."
    ;;
  *)
    echo "[purge] Aborted force-push. Rewritten mirror is at: $WORKDIR/repo.git"
    exit 0
    ;;
esac

cat <<'EOF'

[purge] NEXT STEPS:
  1. Notify all collaborators to re-clone (old clones still contain secrets).
  2. File a GitHub Support ticket to purge cached commit views for the
     leaked SHAs and any forks.
  3. Re-run `gitleaks detect --log-opts="--all" --redact` against a fresh
     clone to confirm no secrets remain.
  4. Confirm rotated credentials are live in GCP Secret Manager / Firebase
     Functions config and the app/functions still work.
EOF
