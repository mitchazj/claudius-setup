#!/usr/bin/env bash
# claudius-setup bootstrap
#
# Converges a fresh Ubuntu 24.04 machine into the claudius box.
# Safe to re-run at any time (idempotent via Ansible).
#
# Usage (fresh box):
#   curl -fsSL https://raw.githubusercontent.com/mitchazj/claudius-setup/main/bootstrap.sh | bash
#
# Usage (local checkout):
#   ./bootstrap.sh --local .
#
# Flags:
#   --local <dir>   use an existing checkout instead of cloning
#   --ci            CI/test mode: skips tags that need secrets or real hardware
#   --user <name>   target user to configure (default: invoking user)
#   --tags <t>      only run these ansible tags
#   --skip-tags <t> additionally skip these ansible tags
set -euo pipefail

REPO_URL="${CLAUDIUS_SETUP_REPO:-https://github.com/mitchazj/claudius-setup.git}"
BRANCH="${CLAUDIUS_SETUP_BRANCH:-main}"
CHECKOUT_DIR="${CLAUDIUS_SETUP_DIR:-$HOME/claudius-setup}"

LOCAL_DIR=""
CI_MODE=0
TARGET_USER="${SUDO_USER:-$USER}"
ONLY_TAGS=""
SKIP_TAGS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --local) LOCAL_DIR="$2"; shift 2 ;;
    --ci) CI_MODE=1; shift ;;
    --user) TARGET_USER="$2"; shift 2 ;;
    --tags) ONLY_TAGS="$2"; shift 2 ;;
    --skip-tags) SKIP_TAGS="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

log() { printf '\033[1;32m[bootstrap]\033[0m %s\n' "$*"; }

if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
  if ! sudo -n true 2>/dev/null; then
    log "sudo will prompt for ${USER}'s password"
  fi
fi

log "installing prerequisites (git, ansible)"
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq git ansible >/dev/null

if [ -n "$LOCAL_DIR" ]; then
  CHECKOUT_DIR="$(cd "$LOCAL_DIR" && pwd)"
  log "using local checkout: $CHECKOUT_DIR"
elif [ -d "$CHECKOUT_DIR/.git" ]; then
  log "updating existing checkout: $CHECKOUT_DIR"
  git -C "$CHECKOUT_DIR" pull --ff-only
else
  log "cloning $REPO_URL -> $CHECKOUT_DIR"
  git clone --branch "$BRANCH" "$REPO_URL" "$CHECKOUT_DIR"
fi

PLAY_ARGS=(-e "target_user=$TARGET_USER")

if [ "$CI_MODE" -eq 1 ]; then
  # firewall: ufw rules can break CI runner / container networking
  # never-ci: anything that must only touch the real box
  SKIP_TAGS="${SKIP_TAGS:+$SKIP_TAGS,}firewall,never-ci"
  PLAY_ARGS+=(-e ci_mode=true)
fi

[ -n "$ONLY_TAGS" ] && PLAY_ARGS+=(--tags "$ONLY_TAGS")
[ -n "$SKIP_TAGS" ] && PLAY_ARGS+=(--skip-tags "$SKIP_TAGS")

# Use the vault password from 1Password when available, otherwise run
# without secrets (secret-dependent tasks self-skip on empty defaults).
if [ -f "$HOME/.claudius-vault-pass" ]; then
  PLAY_ARGS+=(--vault-password-file "$HOME/.claudius-vault-pass")
elif command -v op >/dev/null 2>&1 && op item get "claudius-setup ansible vault" >/dev/null 2>&1; then
  PLAY_ARGS+=(--vault-password-file "$CHECKOUT_DIR/scripts/vault-pass.sh")
fi

# become-password handling: skip the prompt when sudo is passwordless
BECOME_ARGS=()
if [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
  BECOME_ARGS=(--ask-become-pass)
fi

log "running ansible playbook (target_user=$TARGET_USER)"
cd "$CHECKOUT_DIR/ansible"
ansible-playbook playbook.yml "${PLAY_ARGS[@]}" "${BECOME_ARGS[@]}"

log "done. re-run this script any time to re-converge."
