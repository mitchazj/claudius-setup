#!/usr/bin/env bash
# Fast inner-loop test on the Mac: fresh Ubuntu 24.04 VM via OrbStack,
# run bootstrap twice (converge + idempotence), verify, delete.
#
# Note: OrbStack VMs are arm64 — great for catching arch assumptions, but the
# real x86_64 test is CI / the KVM rehearsal.
#
#   ./test/orbstack-test.sh           # full cycle, deletes VM on success
#   KEEP_VM=1 ./test/orbstack-test.sh # leave the VM around for poking
set -euo pipefail

VM="claudius-test"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> recreating VM $VM (ubuntu:noble)"
orb delete -f "$VM" >/dev/null 2>&1 || true
orb create ubuntu:noble "$VM"

run() { orb -m "$VM" -u "$(whoami)" bash -c "$*"; }

echo "==> run 1: bootstrap (should converge)"
run "cd '$REPO_DIR' && ./bootstrap.sh --local '$REPO_DIR' --ci --user \$(whoami)"

echo "==> verify"
run "cd '$REPO_DIR' && sudo TARGET_USER=\$(whoami) ./test/verify.sh --ci"

echo "==> run 2: idempotence (expect changed=0)"
run "cd '$REPO_DIR/ansible' && ansible-playbook playbook.yml --skip-tags firewall,never-ci -e target_user=\$(whoami) -e ci_mode=true | tee /tmp/idem.log; grep -E 'changed=0.*failed=0' /tmp/idem.log"

if [ -z "${KEEP_VM:-}" ]; then
  echo "==> cleaning up"
  orb delete -f "$VM"
else
  echo "==> VM kept: orb -m $VM"
fi
echo "ORBSTACK TEST PASSED"
