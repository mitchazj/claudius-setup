#!/usr/bin/env bash
# Render the autoinstall template with secrets from 1Password and
# (optionally) write a CIDATA seed to a USB stick.
#
# Run on the Mac, at your desk (op will prompt for approval).
#
# Usage:
#   ./make-usb.sh                        # render only -> autoinstall/rendered/
#   ./make-usb.sh --usb /Volumes/CIDATA  # also copy seed files to a mounted FAT32 volume
#
# Reflash procedure (two USB sticks):
#   1. Flash Ubuntu 24.04 Server ISO to stick A (balenaEtcher or dd).
#   2. Format stick B as FAT32 with volume label exactly "CIDATA",
#      run this script with --usb /Volumes/CIDATA.
#   3. Boot the box from stick A with stick B also inserted.
#   4. At the GRUB menu, press `e` and append the word `autoinstall` to the
#      linux line (this skips the "continue with autoinstall?" prompt),
#      then Ctrl-X. Walk away; the box installs, reboots, and converges
#      itself via the claudius-firstboot service.
set -euo pipefail

cd "$(dirname "$0")"
OUT_DIR="rendered"
USB_PATH=""

while [ $# -gt 0 ]; do
  case "$1" in
    --usb) USB_PATH="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

command -v op >/dev/null || { echo "1Password CLI (op) required" >&2; exit 1; }

echo "fetching secrets from 1Password..."
PASSWORD=$(op item get "Claudius Local Machine" --fields password --reveal)
WIFI_SSID=$(op item get "Home Wi-Fi" --fields username --reveal 2>/dev/null || true)
WIFI_PSK=$(op item get "Home Wi-Fi" --fields password --reveal 2>/dev/null || true)

if [ -z "$WIFI_SSID" ] || [ -z "$WIFI_PSK" ]; then
  echo "note: 1Password item 'Home Wi-Fi' not found (expects SSID in username field, PSK in password field)."
  read -r -p "Wi-Fi SSID: " WIFI_SSID
  read -r -s -p "Wi-Fi PSK: " WIFI_PSK; echo
fi

# SHA-512 crypt hash. openssl on macOS supports passwd -6.
PASSWORD_HASH=$(printf '%s' "$PASSWORD" | openssl passwd -6 -stdin)

mkdir -p "$OUT_DIR"
export PASSWORD_HASH WIFI_SSID WIFI_PSK
# envsubst with an explicit variable list so yaml ${...} elsewhere is untouched
envsubst '${PASSWORD_HASH} ${WIFI_SSID} ${WIFI_PSK}' \
  < user-data.tmpl > "$OUT_DIR/user-data"
touch "$OUT_DIR/meta-data"   # required by the NoCloud datasource, may be empty

echo "rendered -> $OUT_DIR/user-data (gitignored — contains secrets)"

if [ -n "$USB_PATH" ]; then
  [ -d "$USB_PATH" ] || { echo "$USB_PATH is not a mounted volume" >&2; exit 1; }
  cp "$OUT_DIR/user-data" "$OUT_DIR/meta-data" "$USB_PATH/"
  echo "seed written to $USB_PATH — eject it and you're ready to reflash."
fi
