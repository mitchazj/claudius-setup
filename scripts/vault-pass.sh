#!/usr/bin/env bash
# Ansible vault password source: 1Password item "claudius-setup ansible vault".
# Used automatically by bootstrap.sh when op is available; on the box you can
# instead store the password in ~/.claudius-vault-pass (chmod 600).
set -euo pipefail
exec op item get "claudius-setup ansible vault" --fields password --reveal
