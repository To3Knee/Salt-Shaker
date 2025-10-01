#!/bin/bash
# restore-github-helpers.sh
# Recreates salt-shaker/github helpers: SSH key+config, env, and small helper scripts.
# EL7-safe, project-root autodetect.

set -euo pipefail

# --- Bootstrap: PROJECT_ROOT ---
RESOLVE_ABS(){ local p="$1"; if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then readlink -f -- "$p" 2>/dev/null || echo "$p"; else ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s\n" "$(pwd)" "$(basename -- "$p")" ); fi; }
SCRIPT_PATH="$(RESOLVE_ABS "$0")"; SCRIPT_DIR="$(dirname -- "$SCRIPT_PATH")"
if [ -n "${SALT_SHAKER_ROOT:-}" ]; then PROJECT_ROOT="${SALT_SHAKER_ROOT}"
elif [ -f "${SCRIPT_DIR}/salt-shaker.sh" ] || [ -d "${SCRIPT_DIR}/modules" ]; then PROJECT_ROOT="${SCRIPT_DIR}"
elif [ -f "${SCRIPT_DIR}/../salt-shaker.sh" ] || [ -d "${SCRIPT_DIR}/../modules" ]; then PROJECT_ROOT="$(RESOLVE_ABS "${SCRIPT_DIR}/..")"
else PROJECT_ROOT="$(pwd)"; fi

GITHUB_DIR="${PROJECT_ROOT}/github"
SSH_DIR="${GITHUB_DIR}/.ssh"
LOG="${PROJECT_ROOT}/logs/salt-shaker.log"
mkdir -p "${GITHUB_DIR}" "${SSH_DIR}" "$(dirname "$LOG")"

say(){ echo -e "$*"; }
log(){ echo "$(date '+%F %T') [restore-github] $*" >>"$LOG"; }

say "▶ Restoring GitHub helpers"
say "Project Root : ${PROJECT_ROOT}"
say "GitHub Dir   : ${GITHUB_DIR}"

# --- .gitignore hardening (avoid committing secrets/noise) ---
if ! grep -q '^logs/$' "${PROJECT_ROOT}/.gitignore" 2>/dev/null; then
  cat >> "${PROJECT_ROOT}/.gitignore" <<'EOF'
# noise/sensitive
logs/
tmp/
archive/
.cache/
bin/*.bak
github/.ssh/
github/.ssh/*
EOF
  say "✓ Patched .gitignore"
fi

# --- env.sh ---
cat > "${GITHUB_DIR}/env.sh" <<'EOF'
#!/bin/bash
# github/env.sh — source to enable per-repo SSH config
PRJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG="${PRJ}/github/.ssh/config"
if [ -f "$CFG" ]; then
  export GIT_SSH_COMMAND="ssh -F ${CFG}"
  echo "GitHub env loaded. Using: ssh -F ${CFG}"
else
  unset GIT_SSH_COMMAND
  echo "GitHub env: no per-repo config; using default SSH"
fi
EOF
chmod +x "${GITHUB_DIR}/env.sh"
say "✓ env.sh"

# --- setup-git-ssh.sh (minimal: create key+config, print pubkey, test) ---
cat > "${GITHUB_DIR}/setup-git-ssh.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
RESOLVE_ABS(){ local p="$1"; if command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then readlink -f -- "$p" 2>/dev/null || echo "$p"; else ( cd "$(dirname -- "$p")" >/dev/null 2>&1 && printf "%s/%s\n" "$(pwd)" "$(basename -- "$p")" ); fi; }
PRJ="$(cd "$(dirname "$(RESOLVE_ABS "$0")")/.." && pwd)"
GDIR="${PRJ}/github"; SSHD="${GDIR}/.ssh"; mkdir -p "$SSHD"
EMAIL_DEFAULT="$(id -un)@salt-shaker"
OWNER_DEFAULT="${GITHUB_OWNER:-}"; REPO_DEFAULT="${GITHUB_REPO:-Salt-Shaker}"
HOST_DEFAULT="${GITHUB_HOST:-github.com}"
# Flags
REGEN=0; PRINT=0
while [ $# -gt 0 ]; do case "$1" in --regen-key) REGEN=1;; --print-config) PRINT=1;; *) ;; esac; shift; done

. "${GDIR}/env.sh" 2>/dev/null || true

echo "════════ Setup GitHub SSH ════════"
echo "Project Root: ${PRJ}"
echo "GitHub Dir  : ${GDIR}"

if [ $PRINT -eq 1 ]; then
  echo "── Config ──"
  echo "SSH Dir     : ${SSHD}"
  echo "SSH Config  : ${SSHD}/config $( [ -f "${SSHD}/config" ] && echo '[ok]' || echo '[missing]')"
  echo "Private Key : ${SSHD}/id_ed25519 $( [ -f "${SSHD}/id_ed25519" ] && echo '[ok]' || echo '[missing]')"
  echo "Public Key  : ${SSHD}/id_ed25519.pub $( [ -f "${SSHD}/id_ed25519.pub" ] && echo '[ok]' || echo '[missing]')"
  [ -f "${SSHD}/id_ed25519.pub" ] && { echo; echo "-- Public key --"; cat "${SSHD}/id_ed25519.pub"; }
  exit 0
fi

read -r -p "Email for key comment [${EMAIL_DEFAULT}]: " EMAIL; EMAIL="${EMAIL:-$EMAIL_DEFAULT}"
read -r -p "GitHub owner/org (optional) [${OWNER_DEFAULT}]: " OWNER; OWNER="${OWNER:-$OWNER_DEFAULT}"
read -r -p "GitHub repo name [${REPO_DEFAULT}]: " REPO; REPO="${REPO:-$REPO_DEFAULT}"
read -r -p "GitHub hostname [${HOST_DEFAULT}]: " HOST; HOST="${HOST:-$HOST_DEFAULT}"

if [ $REGEN -eq 1 ] || [ ! -f "${SSHD}/id_ed25519" ]; then
  ssh-keygen -t ed25519 -f "${SSHD}/id_ed25519" -N "" -C "${EMAIL}" >/dev/null
  chmod 700 "${SSHD}"; chmod 600 "${SSHD}/id_ed25519"; chmod 644 "${SSHD}/id_ed25519.pub"
  echo "✓ Generated ed25519 key"
else
  echo "✓ Existing key kept"
fi

cat > "${SSHD}/config" <<CFG
Host github.com-saltshaker
  HostName ${HOST}
  User git
  IdentityFile ${SSHD}/id_ed25519
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
  UserKnownHostsFile ${SSHD}/known_hosts
CFG
chmod 644 "${SSHD}/config"
echo "✓ SSH config written"

# refresh env
. "${GDIR}/env.sh"

echo
echo "-- Public key — add to GitHub → Settings → SSH and GPG keys --"
cat "${SSHD}/id_ed25519.pub"
echo

read -r -p "Run GitHub SSH connectivity test now? [Y/n]: " yn; yn="${yn:-Y}"
if [[ "$yn" =~ ^[Yy]$ ]]; then
  echo "Testing: ssh -F ${SSHD}/config -T git@github.com-saltshaker"
  ssh -F "${SSHD}/config" -T git@github.com-saltshaker || true
fi

# if repo is already git-initialized, set origin (optional)
if git -C "${PRJ}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ -n "$OWNER" ]; then
    git -C "${PRJ}" remote remove origin 2>/dev/null || true
    git -C "${PRJ}" remote add origin "git@github.com-saltshaker:${OWNER}/${REPO}.git"
    echo "✓ origin set to git@github.com-saltshaker:${OWNER}/${REPO}.git"
  fi
fi
EOF
chmod +x "${GITHUB_DIR}/setup-git-ssh.sh"
say "✓ setup-git-ssh.sh"

# --- status.sh ---
cat > "${GITHUB_DIR}/status.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
PRJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${PRJ}/github/env.sh" 2>/dev/null || true
echo "▶ GitHub Status"; echo "Project Root : ${PRJ}"
if ! command -v git >/dev/null 2>&1; then echo "✖ git not found"; exit 1; fi
( cd "${PRJ}" && \
  echo "Branch       : $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')" && \
  echo "Remote       : $(git remote get-url origin 2>/dev/null || echo 'origin: unset')" && \
  echo "Last commits :" && git --no-pager log -n 3 --pretty='%h %ad %s' --date=local || true
)
# SSH sanity (optional)
CFG="${PRJ}/github/.ssh/config"; if [ -f "$CFG" ]; then
  echo; echo "SSH sanity:"; ssh -F "$CFG" -T git@github.com-saltshaker || true
fi
EOF
chmod +x "${GITHUB_DIR}/status.sh"
say "✓ status.sh"

# --- push.sh (empty commit message by default) ---
cat > "${GITHUB_DIR}/push.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
PRJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${PRJ}/github/env.sh" 2>/dev/null || true
MSG="${1:-}"   # allow truly empty commit message
git -C "${PRJ}" add -A
if [ -n "$MSG" ]; then
  git -C "${PRJ}" commit -m "$MSG" || true
else
  git -C "${PRJ}" commit --allow-empty-message -m "" || true
fi
git -C "${PRJ}" push origin "$(git -C "${PRJ}" rev-parse --abbrev-ref HEAD)"
EOF
chmod +x "${GITHUB_DIR}/push.sh"
say "✓ push.sh"

# --- init-repo.sh (initialize repo if needed, keep history otherwise) ---
cat > "${GITHUB_DIR}/init-repo.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
PRJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${PRJ}/github/env.sh" 2>/dev/null || true
OWNER_DEFAULT="${GITHUB_OWNER:-}"; REPO_DEFAULT="${GITHUB_REPO:-Salt-Shaker}"
if ! command -v git >/dev/null 2>&1; then echo "✖ git not found"; exit 1; fi
if ! git -C "${PRJ}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "${PRJ}" init
  # prefer 'main'
  git -C "${PRJ}" symbolic-ref HEAD refs/heads/main || true
fi
read -r -p "GitHub owner/org [${OWNER_DEFAULT}]: " OWNER; OWNER="${OWNER:-$OWNER_DEFAULT}"
read -r -p "GitHub repo name [${REPO_DEFAULT}]: " REPO; REPO="${REPO:-$REPO_DEFAULT}"
git -C "${PRJ}" remote remove origin 2>/dev/null || true
git -C "${PRJ}" remote add origin "git@github.com-saltshaker:${OWNER}/${REPO}.git"
echo "✓ origin → git@github.com-saltshaker:${OWNER}/${REPO}.git"
echo "Staging + initial commit (blank message)…"
git -C "${PRJ}" add -A
git -C "${PRJ}" commit --allow-empty-message -m "" || true
echo "Pushing to origin main…"
git -C "${PRJ}" push -u origin main
EOF
chmod +x "${GITHUB_DIR}/init-repo.sh"
say "✓ init-repo.sh"

# --- wipe-remote-repo.sh (hard/soft/dry menu) ---
cat > "${GITHUB_DIR}/wipe-remote-repo.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
PRJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${PRJ}/github/env.sh" 2>/dev/null || true
if ! command -v git >/dev/null 2>&1; then echo "✖ git not found"; exit 1; fi
REMOTE="${1:-origin}"
BRANCH="$(git -C "${PRJ}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
echo "════════ Wipe Remote Repo ════════"
echo "Remote  : ${REMOTE}"
echo "Branch  : ${BRANCH}"
echo "1) Dry-run  2) Soft  3) Hard [default]"
read -r -p "Select [1-3, default 3]: " sel; sel="${sel:-3}"
case "$sel" in
  1) MODE="DRY";;
  2) MODE="SOFT";;
  *) MODE="HARD";;
esac
echo "Mode: ${MODE}"
read -r -p "Type ${BRANCH} to proceed: " confirm
[ "$confirm" = "$BRANCH" ] || { echo "Aborted."; exit 1; }

git -C "${PRJ}" fetch "${REMOTE}" "${BRANCH}" || true

if [ "$MODE" = "DRY" ]; then
  echo "Would wipe ${REMOTE}/${BRANCH} (no changes)."
  exit 0
elif [ "$MODE" = "SOFT" ]; then
  git -C "${PRJ}" checkout -B "${BRANCH}" "refs/remotes/${REMOTE}/${BRANCH}" || git -C "${PRJ}" checkout -B "${BRANCH}"
  git -C "${PRJ}" ls-files -z | xargs -0 git -C "${PRJ}" rm -f || true
  git -C "${PRJ}" commit --allow-empty-message -m "" || true
  git -C "${PRJ}" push "${REMOTE}" "${BRANCH}"
  echo "✓ Soft wipe pushed."
else
  TMP="wipe-$(date +%s)"
  git -C "${PRJ}" checkout --orphan "${TMP}"
  git -C "${PRJ}" rm -rf . >/dev/null 2>&1 || true
  : > .gitkeep
  git -C "${PRJ}" add .gitkeep
  git -C "${PRJ}" commit --allow-empty-message -m "" || true
  git -C "${PRJ}" branch -M "${BRANCH}"
  git -C "${PRJ}" push -f "${REMOTE}" "${BRANCH}"
  echo "✓ Hard wipe pushed."
fi
EOF
chmod +x "${GITHUB_DIR}/wipe-remote-repo.sh"
say "✓ wipe-remote-repo.sh"

# --- test.sh (status + dry-run push plan) ---
cat > "${GITHUB_DIR}/test.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
PRJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "▶ GitHub Test (dry-run)"
echo "Project Root : ${PRJ}"
"${PRJ}/github/status.sh" || true
echo; echo "▶ Dry-run push plan"
if ! command -v git >/dev/null 2>&1; then
  echo "⚠ git not installed — cannot evaluate repo state"
  exit 0
fi
( cd "${PRJ}" && \
  echo "Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')" && \
  echo "Remote: $(git remote get-url origin 2>/dev/null || echo 'origin: unset')" && \
  echo "Staged:" && git diff --name-only --cached || true && \
  echo "Unstaged:" && git diff --name-only || true )
EOF
chmod +x "${GITHUB_DIR}/test.sh"
say "✓ test.sh"

say "✅ GitHub helpers restored in: ${GITHUB_DIR}"
say "Next:"
echo "  1) Run: github/setup-git-ssh.sh  (generate key/config, print pubkey)"
echo "  2) Add the PUBLIC key to GitHub → Settings → SSH and GPG keys"
echo "  3) (Optional) github/init-repo.sh to set origin + first push"
echo "  4) Use github/push.sh for later updates"

