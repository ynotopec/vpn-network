#!/usr/bin/env bash
set -euo pipefail

WG_IF="${WG_IF:-wg0}"
WG_DIR="/etc/wireguard"
WG_CONF="${WG_DIR}/${WG_IF}.conf"
WG_PRIV="${WG_DIR}/${WG_IF}.key"
WG_PUB="${WG_DIR}/${WG_IF}.pub"
SYSCTL_FILE="/etc/sysctl.d/99-wireguard-forward.conf"

if systemctl list-unit-files | awk '{print $1}' | grep -qx "wg-quick@${WG_IF}.service"; then
  systemctl disable --now "wg-quick@${WG_IF}" || true
fi

ip link delete dev "${WG_IF}" 2>/dev/null || true

rm -f "${WG_CONF}" "${WG_PRIV}" "${WG_PUB}" "${SYSCTL_FILE}"

# Re-apply sysctl files if available.
if command -v sysctl >/dev/null 2>&1; then
  sysctl --system >/dev/null || true
fi

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get remove -y wireguard || true
  apt-get autoremove -y || true
fi

echo "=== Server WireGuard removed (${WG_IF}) ==="
