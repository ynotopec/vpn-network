#!/usr/bin/env bash
set -euo pipefail

WG_IF="${WG_IF:-wg0}"
WG_DIR="/etc/wireguard"
WG_CONF="${WG_DIR}/${WG_IF}.conf"

if systemctl list-unit-files | awk '{print $1}' | grep -qx "wg-quick@${WG_IF}.service"; then
  systemctl disable --now "wg-quick@${WG_IF}" || true
fi

ip link delete dev "${WG_IF}" 2>/dev/null || true
rm -f "${WG_CONF}"

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get remove -y wireguard || true
  apt-get autoremove -y || true
fi

echo "=== Client WireGuard removed (${WG_IF}) ==="
