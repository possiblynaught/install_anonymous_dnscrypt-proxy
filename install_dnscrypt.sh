#!/bin/bash

# Debug
#set -x
set -Eeo pipefail

################################################################################
# Uncomment this line to disable signiture verification and therefore installation of minisign
SKIP_VERIFY=1
# Location where dnscrypt-proxy folder+binary will be installed
INSTALL_LOCATION="$HOME/Documents"
################################################################################

# Save script dir
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
GEN_SCRIPT="$SCRIPT_DIR/dnscrypt-proxy_config_generator/generate_anondns_and_odoh.sh"

# Check for linux version, expecting linux x86/64
if ! uname -a | grep -q 'x86_64\|Linux'; then
  echo "Error, x86_64 linux architecture not found"
  exit 1
fi

# Check for generate script
if [[ ! -x "$GEN_SCRIPT" ]]; then
  echo "Error, executable generate script not found: $GEN_SCRIPT
Make sure you have initialized the submodules with:
  git submodule init
  git submodule update"
  exit 1
fi

# Make sure v1 isn't already installed
if command -v dnscrypt-proxy &> /dev/null; then
  echo "Error, dnscrypt-proxy appears to be already installed, please remove it and run this script again."
  exit 1
fi

# Check for v2 or existing service
EXISTING_SERVICE="/etc/systemd/system/dnscrypt-proxy.service"
if [[ -f "$EXISTING_SERVICE" ]]; then
  echo "Error, dnscrypt service aleady exists, please remove the existing service:
  systemctl stop dnscrypt-proxy.service
  systemctl disable dnscrypt-proxy.service
  sudo rm $EXISTING_SERVICE

  You might also need to reset or edit /etc/resolv.conf to reset dns"
  exit 1
fi

# Download latest binary and minisig, verify, and unpack
DL_LOC="/tmp"
TEMP_DOWNLOAD=$(mktemp /tmp/install_dnscrypt.XXXXXX || exit 1)
# Get latest release links
wget "https://api.github.com/repos/DNSCrypt/dnscrypt-proxy/releases/latest" -O "$TEMP_DOWNLOAD"
DL_LINKS=$(grep -F "dnscrypt-proxy-linux_x86_64" < "$TEMP_DOWNLOAD")
DL_FILE="$DL_LOC/$(echo "$DL_LINKS" | grep -F "\"name\":" | grep -vF "minisig" | cut -d "\"" -f 4)"
DL_SIG_FILE="$DL_LOC/$(echo "$DL_LINKS" | grep -F "\"name\":" | grep -F "minisig" | cut -d "\"" -f 4)"
rm -f "$DL_FILE"
rm -f "$DL_SIG_FILE"
# Download releases
echo "$DL_LINKS" | grep -F "\"browser_download_url\":" | cut -d "\"" -f 4 | \
  wget -i - -P "$DL_LOC"
rm -f "$TEMP_DOWNLOAD"

# Verify files
if [[ ! "$SKIP_VERIFY" -eq 1 ]]; then
  # Install minisign if not already present
  if ! command -v minisign &> /dev/null; then
    sudo apt update; sudo apt install -y cmake build-essential
  # TODO: Install libsodium
  # TODO: Install minisign
  fi
fi

# Unpack
EXTRACT_DIR="/tmp"
UNPACK_DIR="$EXTRACT_DIR/linux-x86_64"
rm -rf "$UNPACK_DIR"
mkdir -p "$EXTRACT_DIR"
echo $(tar -xf "$DL_FILE" -C "$EXTRACT_DIR")
[ -f "$UNPACK_DIR/dnscrypt-proxy" ] || (echo "Error, download failed for binary in dir: $UNPACK_DIR"; exit 1)
# Delete example files
find "$UNPACK_DIR/." -type f -name 'example-*' -exec rm {} \;

# Generate toml
TOML_FILE="$UNPACK_DIR/dnscrypt-proxy.toml"
"$GEN_SCRIPT" "$TOML_FILE"
# Pull dns listen address from toml
LISTEN_ADDRESS=$(grep -F "listen_addresses = " < "$TOML_FILE" | grep -vF "#" | cut -d "'" -f 2 | cut -d ":" -f 1)
[ -n "$LISTEN_ADDRESS" ] || (echo "Error, unable to get listen_address from: $TOML_FILE"; exit 1)
# Check for and backup resolv.conf
RESOLV_FILE="/etc/resolv.conf"
OLD_RESOLV_FILE="/etc/resolv.conf.old"
if [[ ! -f "$RESOLV_FILE" ]]; then
  echo "Error, couldn't find $RESOLV_FILE, you may need to remove resolvconf with:
  sudo apt remove -y resolvconf"
  exit 1
fi
sudo mv "$RESOLV_FILE" "$OLD_RESOLV_FILE"
# Write listen address to resolv.conf
echo "nameserver $LISTEN_ADDRESS
options edns0
#nameserver 8.8.8.8" | sudo tee -a "$RESOLV_FILE" > /dev/null

# Install dnscrypt-proxy2
FINAL_DIR="$INSTALL_LOCATION/dnscrypt-proxy"
mkdir -p "$INSTALL_LOCATION"
rm -rf "$FINAL_DIR"
mv "$UNPACK_DIR" "$FINAL_DIR/"
# Install service
DNSCRYPT_BINARY="$FINAL_DIR/dnscrypt-proxy"
[ -x "$DNSCRYPT_BINARY" ] || (echo "Error, dnscrypt binary not found in install location: $DNSCRYPT_BINARY"; exit 1)

# Install service and run
echo
sudo "$DNSCRYPT_BINARY" -service install
sudo "$DNSCRYPT_BINARY" -service start
sleep 1
systemctl status dnscrypt-proxy.service

# Notify of completion
echo "
################################################################################
Installation completed to directory: $FINAL_DIR
The old version of the resolv file was saved to: $OLD_RESOLV_FILE
If the internet connection doesn't work after this script, reset to old config with:
  sudo mv $OLD_RESOLV_FILE $RESOLV_FILE
################################################################################"
