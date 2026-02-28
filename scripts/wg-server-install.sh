#!/usr/bin/env bash
set -euo pipefail

WG_IF="${WG_IF:-wg0}"
WG_PORT="${WG_PORT:-51820}"
WG_NET="${WG_NET:-10.10.0.0/24}"
WG_ADDR="${WG_ADDR:-10.10.0.1/24}"
WG_DIR="/etc/wireguard"
WG_CONF="${WG_DIR}/${WG_IF}.conf"
WG_PRIV="${WG_DIR}/${WG_IF}.key"
WG_PUB="${WG_DIR}/${WG_IF}.pub"

WAN_IF="${WAN_IF:-$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')}"
: "${WAN_IF:?Unable to detect WAN_IF. Set WAN_IF=eth0 (example).}"

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y --no-install-recommends wireguard iptables iproute2 ca-certificates

install -d -m 700 "${WG_DIR}"

if [[ ! -s "${WG_PRIV}" ]]; then
  umask 077
  wg genkey | tee "${WG_PRIV}" | wg pubkey > "${WG_PUB}"
fi

SYSCTL_FILE="/etc/sysctl.d/99-wireguard-forward.conf"
cat > "${SYSCTL_FILE}" <<EOF_SYSCTL
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF_SYSCTL
sysctl --system >/dev/null

if [[ ! -f "${WG_CONF}" ]]; then
  umask 077
  cat > "${WG_CONF}" <<EOF_CONF
[Interface]
Address = ${WG_ADDR}
ListenPort = ${WG_PORT}
PrivateKey = $(cat "${WG_PRIV}")

# NAT + forward rules (iptables). Idempotent via -C checks.
PostUp = iptables -C FORWARD -i ${WG_IF} -j ACCEPT 2>/dev/null || iptables -A FORWARD -i ${WG_IF} -j ACCEPT; iptables -C FORWARD -o ${WG_IF} -j ACCEPT 2>/dev/null || iptables -A FORWARD -o ${WG_IF} -j ACCEPT; iptables -t nat -C POSTROUTING -s ${WG_NET} -o ${WAN_IF} -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s ${WG_NET} -o ${WAN_IF} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_IF} -j ACCEPT 2>/dev/null || true; iptables -D FORWARD -o ${WG_IF} -j ACCEPT 2>/dev/null || true; iptables -t nat -D POSTROUTING -s ${WG_NET} -o ${WAN_IF} -j MASQUERADE 2>/dev/null || true
EOF_CONF
fi

chmod 600 "${WG_CONF}" "${WG_PRIV}" "${WG_PUB}" || true

systemctl enable --now "wg-quick@${WG_IF}"

echo "=== Server ready ==="
echo "Public key: $(cat "${WG_PUB}")"
echo "Listen: UDP ${WG_PORT} on ${WAN_IF}"
