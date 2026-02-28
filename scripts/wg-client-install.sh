#!/usr/bin/env bash
set -euo pipefail

WG_IF="${WG_IF:-wg0}"
WG_DIR="/etc/wireguard"
WG_CONF="${WG_DIR}/${WG_IF}.conf"

CLIENT_CONF_FILE="${1:?Usage: $0 <client.conf>}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends wireguard iproute2 ca-certificates

install -d -m 700 "${WG_DIR}"

umask 077
if [[ ! -f "${WG_CONF}" ]] || ! cmp -s "${CLIENT_CONF_FILE}" "${WG_CONF}"; then
  install -m 600 "${CLIENT_CONF_FILE}" "${WG_CONF}"
fi

systemctl enable --now "wg-quick@${WG_IF}"
wg show "${WG_IF}" || true
