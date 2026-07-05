#!/usr/bin/env bash
# Assert the machine actually converged. Used by CI, VM tests, and by hand.
#   TARGET_USER=claudius ./verify.sh          # full check
#   TARGET_USER=runner  ./verify.sh --ci      # skips firewall/hardening checks
set -uo pipefail

TARGET_USER="${TARGET_USER:-claudius}"
CI_MODE=0
[ "${1:-}" = "--ci" ] && CI_MODE=1

FAIL=0
pass() { printf '  \033[32mok\033[0m  %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=1; }
check() { # check <description> <command...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

echo "verifying convergence for user=$TARGET_USER (ci=$CI_MODE)"

check "git installed"            command -v git
check "curl installed"           command -v curl
check "neovim installed"         command -v nvim
check "jq installed"             command -v jq
check "build-essential (gcc)"    command -v gcc

check "docker installed"         command -v docker
check "docker daemon active"     systemctl is-active docker
check "docker compose plugin"    docker compose version
check "$TARGET_USER in docker group" bash -c "id -nG '$TARGET_USER' | grep -qw docker"

check "tailscale installed"      command -v tailscale

check "claude installed for $TARGET_USER" sudo -u "$TARGET_USER" test -x "/home/$TARGET_USER/.local/bin/claude"

if [ "${CHECK_COOLIFY:-0}" = "1" ]; then
  check "coolify stack present"  test -f /data/coolify/source/docker-compose.yml
  check "coolify healthy"        curl -fsS http://localhost:8000/api/health
fi

check "unattended-upgrades config" grep -q 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades

if [ "$CI_MODE" -eq 0 ]; then
  check "sshd running"           systemctl is-active ssh
  check "tailscaled running"     systemctl is-active tailscaled
  check "ufw active"             bash -c "ufw status | grep -q 'Status: active'"
  check "sshd: password auth off" bash -c "sshd -T | grep -qi '^passwordauthentication no'"
fi

if [ "$FAIL" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "CHECKS FAILED"; exit 1; fi
