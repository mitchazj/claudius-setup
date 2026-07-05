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
#   --local <dir>     use an existing checkout instead of cloning
#   --ci              CI/test mode: skips tags that need secrets or real hardware
#   --user <name>     target user to configure (default: invoking user)
#   --profile <name>  machine profile from ansible/profiles/ (default: claudius;
#                     use "do" for DigitalOcean droplets)
#   --tags <t>        only run these ansible tags
#   --skip-tags <t>   additionally skip these ansible tags
set -euo pipefail

REPO_URL="${CLAUDIUS_SETUP_REPO:-https://github.com/mitchazj/claudius-setup.git}"
BRANCH="${CLAUDIUS_SETUP_BRANCH:-main}"
CHECKOUT_DIR="${CLAUDIUS_SETUP_DIR:-$HOME/claudius-setup}"

LOCAL_DIR=""
CI_MODE=0
# id -un fallback matters: systemd units (first-boot) have neither SUDO_USER nor USER
TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"
PROFILE="claudius"
ONLY_TAGS=""
SKIP_TAGS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --local) LOCAL_DIR="$2"; shift 2 ;;
    --ci) CI_MODE=1; shift ;;
    --user) TARGET_USER="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
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

PROFILE_FILE="$CHECKOUT_DIR/ansible/profiles/$PROFILE.yml"
[ -f "$PROFILE_FILE" ] || { echo "unknown profile: $PROFILE (no $PROFILE_FILE)" >&2; exit 2; }

PLAY_ARGS=(-e "target_user=$TARGET_USER" -e "@$PROFILE_FILE")

if [ "$CI_MODE" -eq 1 ]; then
  # firewall: ufw rules can break CI runner / container networking
  # never-ci: anything that must only touch the real box
  SKIP_TAGS="${SKIP_TAGS:+$SKIP_TAGS,}firewall,never-ci"
  PLAY_ARGS+=(-e ci_mode=true)
fi

[ -n "$ONLY_TAGS" ] && PLAY_ARGS+=(--tags "$ONLY_TAGS")
[ -n "$SKIP_TAGS" ] && PLAY_ARGS+=(--skip-tags "$SKIP_TAGS")

# hook for tests: CLAUDIUS_EXTRA_VARS="-e install_coolify=true"
if [ -n "${CLAUDIUS_EXTRA_VARS:-}" ]; then
  # shellcheck disable=SC2206
  PLAY_ARGS+=($CLAUDIUS_EXTRA_VARS)
fi

# Use the vault password from 1Password when available, otherwise run
# without secrets (secret-dependent tasks self-skip on empty defaults).
# timeout: op can hang on an approval popup when nobody is at the desk
if [ -f "$HOME/.claudius-vault-pass" ]; then
  PLAY_ARGS+=(--vault-password-file "$HOME/.claudius-vault-pass")
elif command -v op >/dev/null 2>&1 \
    && timeout 5 op item get "claudius-setup ansible vault" >/dev/null 2>&1; then
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
