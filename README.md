# claudius-setup

Reproducible setup for the **claudius** home server (Lenovo ThinkCentre M900,
Ubuntu 24.04, `192.168.1.22`) — and for any Ubuntu server that should look
like it, including DigitalOcean droplets. If a box dies, gets reflashed, or
moves house, this repo recreates it from a blank disk with (almost) one command.

Machine differences live in **profiles** (`ansible/profiles/*.yml`):
`claudius` (home box: desktop kept, LAN conveniences) and `do` (cloud VPS:
key-only, headless, Coolify on, dashboard not public).

```
┌─ Layer 0: reflash ────────────────────────────────────────────┐
│ autoinstall/ — unattended Ubuntu Server install from USB.     │
│ Renders secrets from 1Password at USB-creation time.          │
└──────────────────────────────┬────────────────────────────────┘
                               ▼ first boot (or any time later)
┌─ Layer 1: configuration ──────────────────────────────────────┐
│ bootstrap.sh → ansible/ — packages, ssh keys + hardening,     │
│ ufw, docker, tailscale, claude code, headless toggle.         │
│ Idempotent; re-run to converge after any drift.               │
└──────────────────────────────┬────────────────────────────────┘
                               ▼
┌─ Layer 2: services (future) ──────────────────────────────────┐
│ compose/ — coolify / photo display / notes app / etc.         │
└───────────────────────────────────────────────────────────────┘
```

## Everyday use

```sh
# on the box — converge to the declared state (safe to re-run whenever):
cd ~/claudius-setup && git pull && ./bootstrap.sh --local .

# fresh Ubuntu machine that isn't reflash-born:
curl -fsSL https://raw.githubusercontent.com/mitchazj/claudius-setup/main/bootstrap.sh | bash
```

Change what the machine *is* by editing `ansible/group_vars/all.yml`
(shared: packages, firewall, authorized keys) or its profile in
`ansible/profiles/` (per-machine: headless, coolify, sudo policy) and re-running.

## DigitalOcean (or any cloud VPS)

Create a droplet (Ubuntu 24.04 x64) with `digitalocean/user-data.yml` pasted
into "User data" — it creates the user and runs the bootstrap with
`--profile do` on first boot. Or by hand on any existing server:

```sh
curl -fsSL https://raw.githubusercontent.com/mitchazj/claudius-setup/main/bootstrap.sh \
  | bash -s -- --profile do
```

The `do` profile is key-only SSH + ufw + docker + tailscale + **Coolify**,
with the Coolify dashboard reachable only via tailscale or an SSH tunnel
(`ssh -L 8000:localhost:8000 <host>`), never the public internet.

## Coolify

The `coolify` role installs Coolify v4 via its official installer, opens
80/443 for hosted sites, and health-checks the dashboard. Off by default on
the home box — enable by setting `install_coolify: true` in
`ansible/profiles/claudius.yml` and re-running bootstrap. Coolify's own data
lives in `/data/coolify` (back this up; it is state, not config).

## Reflashing from scratch

1. On the Mac, at your desk (1Password prompts): `./autoinstall/make-usb.sh`
2. Flash the Ubuntu 24.04 **Server** ISO to USB stick A; put the rendered
   seed on a FAT32 stick B labelled `CIDATA` (`make-usb.sh --usb /Volumes/CIDATA`).
3. Boot the box from stick A (stick B inserted), add `autoinstall` to the
   kernel line at GRUB (`e`, append, `Ctrl-X`).
4. Walk away. It installs, reboots, and `claudius-firstboot.service` runs the
   full convergence. SSH in when it's done.

Wi-Fi note: the template configures `wlp1s0`, but plugging ethernet in for
the 15-minute install is the more reliable path.

## Secrets — the rules

This repo is **public**. The design assumes it:

| Secret | Where it lives | How it's used |
|---|---|---|
| claudius password | 1Password `Claudius Local Machine` | hashed (SHA-512 crypt) into the rendered seed at `make-usb.sh` time; rendered files are gitignored |
| Wi-Fi SSID/PSK | 1Password `Home Wi-Fi` | same |
| Tailscale auth key | `ansible/vault/secrets.yml` (ansible-vault encrypted) | vault password lives in 1Password `claudius-setup ansible vault`; without it, tailscale auth is skipped and `sudo tailscale up` works interactively |

Hard rules: no plaintext secrets in git, ever — including password *hashes*.
CI runs gitleaks plus a check that `vault/secrets.yml` is actually encrypted.
The machine's SSH **public** key allowlist is committed (public keys are public).

## Testing the self-recreation

| Tier | What | Command |
|---|---|---|
| inner loop | fresh arm64 Ubuntu VM on the Mac (OrbStack), converge + idempotence + verify | `./test/orbstack-test.sh` |
| continuous | real x86_64 ubuntu-24.04 from zero on every push | `.github/workflows/ci.yml` |
| dress rehearsal | boot the *actual installer ISO + autoinstall seed* in KVM on the box | `./test/kvm-autoinstall-test.sh` |

`test/verify.sh` is the shared assertion list — extend it whenever the
machine gains a responsibility, so "reproducible" stays provable.

## Layout

```
bootstrap.sh                 curl-able entrypoint (installs ansible, runs playbook)
ansible/
  playbook.yml               role list
  group_vars/all.yml         THE machine definition — edit this
  roles/{base,ssh,docker,tailscale,claude-code,headless}/
  vault/secrets.yml          encrypted secrets (see secrets.yml.example)
autoinstall/
  user-data.tmpl             Layer 0 template (placeholders, no secrets)
  make-usb.sh                render + write USB seed (Mac, needs op)
test/                        verify.sh, orbstack-test.sh, kvm-autoinstall-test.sh
scripts/vault-pass.sh        vault password via 1Password
```
