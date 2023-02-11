#!/bin/bash

# Debug
#set -x
set -Eeo pipefail

################################################################################
# Uncomment line to disable signiture verification and skip installing minisign
# SKIP_VERIFY=1
# Location where dnscrypt folder containing config+binary will be installed
INSTALL_DIRECTORY="/etc/dnscrypt-proxy"
################################################################################

# Save script dir
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
GEN_SCRIPT="$SCRIPT_DIR/dnscrypt-proxy_config_generator/generate_config.sh"

# TODO: Install from package repository if available
# Make sure dnscrypt-proxy isn't already installed via package manager
if command -v dnscrypt-proxy &> /dev/null; then
  echo "Error, dnscrypt-proxy appears to be already installed via package manager, 
  please remove it and run this script again."
  exit 1
fi

# Function to check for a service name (arg $1) and notify if present
check_service() {
  local SERVICE="$1"
  [ -n "$SERVICE" ] || (echo "Error, no service name passed to check_service()"; exit 1)
  if ! command -v systemctl &> /dev/null; then
    echo "Error, was expecting systemctl to be present for check_service()"
    exit 1
  fi
  local STATUS
  STATUS=$(systemctl status "$SERVICE" 2>&1 || true)
  if ! echo "$STATUS" | grep -qF " could not be found."; then
    echo "Error, existing service found for: $SERVICE"
    echo "Please stop, disable, and remove the service:
  systemctl stop $SERVICE
  systemctl disable $SERVICE
  sudo rm -f $(echo "$STATUS" | grep -F "Loaded: " | cut -d "(" -f 2 | cut -d ";" -f 1)
  systemctl daemon-reload"
    exit 1
  fi
}

# Check for existing binary and services
check_service "dnscrypt-proxy-resolvconf.service"
check_service "dnscrypt-proxy.socket"
check_service "dnscrypt-proxy.service"

# Check for linux + architecture
UARCH=$(uname -m)
if ! uname -a | grep -qF "Linux"; then
  echo "Error, please run this on a linux system"
  exit 1
elif [[ ! "${UARCH}" =~ arm|arm64|i386|mips|mips64|mips64le|mipsle|riscv64|x86_64 ]]; then
  echo "Unsupported architecture: $UARCH"
  exit 1
fi

# Check for generate script
if [[ ! -x "$GEN_SCRIPT" ]]; then
  echo "Error, executable generate script not found:
  $GEN_SCRIPT
Make sure you have initialized the submodules with:
  git submodule init
  git submodule update"
  exit 1
fi

# Download latest binary and minisig, verify, and unpack
DL_LOC="/tmp"
TEMP_DOWNLOAD=$(mktemp /tmp/install_dnscrypt.XXXXXX || exit 1)
# Get latest release links
echo "Getting latest dnscrypt-proxy 2 release information..."
wget -q "https://api.github.com/repos/DNSCrypt/dnscrypt-proxy/releases/latest" -O "$TEMP_DOWNLOAD" || \
  (echo "Error downloading dnscrypt-proxy release, please check your internet connection or /etc/resolv.conf"; exit 1)
DL_VERSION=$(grep -F "\"name\": \"Release" < "$TEMP_DOWNLOAD" | cut -d "\"" -f 4 | cut -d " " -f 2)
DL_LINKS=$(grep -F "dnscrypt-proxy-linux_$UARCH" < "$TEMP_DOWNLOAD")
DL_FILE="$DL_LOC/$(echo "$DL_LINKS" | grep -F "\"name\":" | grep -vF "minisig" | cut -d "\"" -f 4)"
DL_SIG_FILE="$DL_LOC/$(echo "$DL_LINKS" | grep -F "\"name\":" | grep -F "minisig" | cut -d "\"" -f 4)"
rm -f "$DL_FILE"
rm -f "$DL_SIG_FILE"
# Download releases
echo "Downloading dnscrypt-proxy 2, version $DL_VERSION for $UARCH..."
echo "$DL_LINKS" | grep -F "\"browser_download_url\":" | cut -d "\"" -f 4 | \
  wget -q -i - -P "$DL_LOC"
rm -f "$TEMP_DOWNLOAD"

# Verify files
if [[ ! "$SKIP_VERIFY" -eq 1 ]]; then
  # Install minisign if not already present
  if ! command -v minisign &> /dev/null; then
    INSTALL_MINISIGN="$SCRIPT_DIR/install_minisign/install_minisign.sh"
    if [[ ! -x "$INSTALL_MINISIGN" ]]; then
      echo "Error, executable minisign install script not found:
  $INSTALL_MINISIGN
Make sure you have initialized the submodules with:
  git submodule init
  git submodule update"
      exit 1
    else
      echo "--------------------------------------------------------------------------------"
      "${INSTALL_MINISIGN}"
      echo
    fi
  fi
  # Check signature
  SIG=$(minisign -VP RWTk1xXqcTODeYttYMCMLo0YJHaFEHn7a3akqHlb/7QvIQXHVPxKbjB5 -m "$DL_FILE")
  if ! (echo "$SIG" | grep -qF "Signature and comment signature verified"); then
    echo "Error, minisig verification of dnscrypt binary failed:
$SIG"
    exit 1
  else
    echo "Signature for dnscrypt-proxy binary verified successfully:
  $DL_FILE"
  fi
fi

# Unpack
EXTRACT_DIR="/tmp"
UNPACK_DIR="$EXTRACT_DIR/linux-$UARCH"
rm -rf "$UNPACK_DIR"
mkdir -p "$EXTRACT_DIR"
tar -xf "$DL_FILE" -C "$EXTRACT_DIR"
rm -f "$DL_FILE"
rm -f "$DL_SIG_FILE"
[ -f "$UNPACK_DIR/dnscrypt-proxy" ] || (echo "Error, download failed for binary in dir: $UNPACK_DIR"; exit 1)
# Delete example files
find "$UNPACK_DIR/." -type f -name 'example-*' -exec rm {} \;

# Generate toml
TOML_FILE="$UNPACK_DIR/dnscrypt-proxy.toml"
echo "--------------------------------------------------------------------------------"
"$GEN_SCRIPT" || true # TODO: Fix this
mv "/tmp/dnscrypt-proxy.toml" "$TOML_FILE"
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

# Install dnscrypt-proxy 2
mkdir -p "$(dirname "$INSTALL_DIRECTORY")"
sudo rm -rf "$INSTALL_DIRECTORY"
sudo mv "$UNPACK_DIR" "$INSTALL_DIRECTORY/"
# Install service
DNSCRYPT_BINARY="$INSTALL_DIRECTORY/dnscrypt-proxy"
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
Installation completed to directory: $INSTALL_DIRECTORY
The old version of the resolv file was saved to: $OLD_RESOLV_FILE
If the network connection doesn't work after this script, reset resolv with:
  sudo mv $OLD_RESOLV_FILE $RESOLV_FILE
################################################################################"

# Ask about dns test
read -p "Do you want to test your dns servers (Y/n)? " -n 1 -r
if [[ $REPLY =~ ^[Yy]$ ]]
then
  # Attempt dns leak test
  DNS_SCRIPT="$SCRIPT_DIR/minimal_dnsleaktest/leaktest.sh"
  if [ -x "$DNS_SCRIPT" ]; then
    echo -e "\nTesting DNS servers in 10 seconds..."
    sleep 10
    "${DNS_SCRIPT}"
  else
    echo "Error, no executable dns script found: 
  $DNS_SCRIPT"
    exit 1
  fi
fi
