#!/usr/bin/env bash
set -euo pipefail

WG_IF="${WG_IF:-wg0}"
WG_NET_CIDR="${WG_NET_CIDR:-10.10.0.0/24}"
WG_SERVER_IP="${WG_SERVER_IP:-10.10.0.1}"
WG_DIR="${WG_DIR:-/etc/wireguard}"
WG_CONF="${WG_DIR}/${WG_IF}.conf"
WG_SERVER_PUB="${WG_DIR}/${WG_IF}.pub"

resolve_wg_port() {
  local conf_path="$1"

  if [[ -n "${WG_PORT:-}" ]]; then
    printf '%s\n' "${WG_PORT}"
    return
  fi

  if [[ -f "${conf_path}" ]]; then
    local detected_port
    detected_port="$(awk -F '=' '/^[[:space:]]*ListenPort[[:space:]]*=/{gsub(/[[:space:]]/,"",$2); print $2; exit}' "${conf_path}")"
    if [[ "${detected_port}" =~ ^[0-9]+$ ]]; then
      printf '%s\n' "${detected_port}"
      return
    fi
  fi

  printf '51820\n'
}

WG_PORT="$(resolve_wg_port "${WG_CONF}")"

SERVER_ENDPOINT="${SERVER_ENDPOINT:?Set SERVER_ENDPOINT=your.vps.public.ip_or_dns}"
CLIENT_NAME="${1:?Usage: $0 <client_name> <client_ip_last_octet> [allowed_ips]>}"
CLIENT_OCTET="${2:?Usage: $0 <client_name> <client_ip_last_octet> [allowed_ips]>}"
CLIENT_ALLOWED="${3:-${WG_NET_CIDR}}"

validate_ipv4() {
  local ip="$1"
  local IFS=.
  local -a parts
  read -r -a parts <<<"${ip}"
  [[ ${#parts[@]} -eq 4 ]] || return 1
  for octet in "${parts[@]}"; do
    [[ "$octet" =~ ^[0-9]+$ ]] || return 1
    (( octet >= 0 && octet <= 255 )) || return 1
  done
}

validate_client_name() {
  [[ "$1" =~ ^[a-zA-Z0-9._-]+$ ]]
}

validate_octet() {
  [[ "$1" =~ ^[0-9]+$ ]] || return 1
  (( "$1" >= 2 && "$1" <= 254 ))
}

validate_allowed_ips() {
  local value="$1"
  [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] || [[ "$value" =~ ^([0-9a-fA-F:]+)/[0-9]{1,3}$ ]]
}

validate_port() {
  [[ "$1" =~ ^[0-9]+$ ]] || return 1
  (( "$1" >= 1 && "$1" <= 65535 ))
}

render_endpoint() {
  local endpoint="$1"
  local default_port="$2"

  if [[ "$endpoint" =~ ^\[[0-9a-fA-F:]+\]:[0-9]+$ ]]; then
    printf '%s\n' "$endpoint"
    return
  fi

  if [[ "$endpoint" =~ ^\[[0-9a-fA-F:]+\]$ ]]; then
    printf '%s:%s\n' "$endpoint" "$default_port"
    return
  fi

  if [[ "$endpoint" =~ :[0-9]+$ ]] && [[ "$endpoint" != *:*:* ]]; then
    printf '%s\n' "$endpoint"
    return
  fi

  if [[ "$endpoint" == *:* ]]; then
    printf '[%s]:%s\n' "$endpoint" "$default_port"
    return
  fi

  printf '%s:%s\n' "$endpoint" "$default_port"
}

validate_octet "${CLIENT_OCTET}" || {
  echo "Error: client_ip_last_octet must be an integer between 2 and 254." >&2
  exit 1
}

validate_allowed_ips "${CLIENT_ALLOWED}" || {
  echo "Error: allowed_ips must look like an IPv4/IPv6 CIDR (e.g. 10.10.0.0/24 or 0.0.0.0/0)." >&2
  exit 1
}

validate_ipv4 "${WG_SERVER_IP}" || {
  echo "Error: WG_SERVER_IP must be a valid IPv4 address (e.g. 10.10.0.1)." >&2
  exit 1
}

validate_client_name "${CLIENT_NAME}" || {
  echo "Error: client_name must contain only letters, digits, dot, underscore, or dash." >&2
  exit 1
}

validate_port "${WG_PORT}" || {
  echo "Error: WG_PORT must be an integer between 1 and 65535." >&2
  exit 1
}

[[ -r "${WG_CONF}" ]] || {
  echo "Error: server config not found/readable at ${WG_CONF}. Run wg-server-install.sh first." >&2
  exit 1
}

[[ -r "${WG_SERVER_PUB}" ]] || {
  echo "Error: server public key not found/readable at ${WG_SERVER_PUB}." >&2
  exit 1
}

wg show "${WG_IF}" >/dev/null 2>&1 || {
  echo "Error: interface ${WG_IF} is not active. Start wg-quick@${WG_IF} first." >&2
  exit 1
}

CLIENT_SUBNET_PREFIX="${WG_SERVER_IP%.*}"
CLIENT_IP="${CLIENT_SUBNET_PREFIX}.${CLIENT_OCTET}"
PEER_TAG="### peer:${CLIENT_NAME}"
CLIENT_ENDPOINT="$(render_endpoint "${SERVER_ENDPOINT}" "${WG_PORT}")"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
CLIENT_PRIV="${TMPDIR}/${CLIENT_NAME}.key"
CLIENT_PUB="${TMPDIR}/${CLIENT_NAME}.pub"
umask 077
wg genkey | tee "${CLIENT_PRIV}" | wg pubkey > "${CLIENT_PUB}"

if ! grep -qF "${PEER_TAG}" "${WG_CONF}"; then
  umask 077
  cat >> "${WG_CONF}" <<EOF_PEER

${PEER_TAG}
[Peer]
PublicKey = $(cat "${CLIENT_PUB}")
AllowedIPs = ${CLIENT_IP}/32
EOF_PEER
fi

wg syncconf "${WG_IF}" <(wg-quick strip "${WG_IF}")

cat <<EOF_CLIENT
# ===== Client config: ${CLIENT_NAME} =====
[Interface]
Address = ${CLIENT_IP}/32
PrivateKey = $(cat "${CLIENT_PRIV}")
DNS = 1.1.1.1

[Peer]
PublicKey = $(cat "${WG_SERVER_PUB}")
Endpoint = ${CLIENT_ENDPOINT}
AllowedIPs = ${CLIENT_ALLOWED}
PersistentKeepalive = 25
EOF_CLIENT
