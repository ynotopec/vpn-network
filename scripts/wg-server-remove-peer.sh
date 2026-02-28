#!/usr/bin/env bash
set -euo pipefail

WG_IF="${WG_IF:-wg0}"
WG_DIR="${WG_DIR:-/etc/wireguard}"
WG_CONF="${WG_DIR}/${WG_IF}.conf"

CLIENT_NAME="${1:?Usage: $0 <client_name>}"
PEER_TAG="### peer:${CLIENT_NAME}"

validate_client_name() {
  [[ "$1" =~ ^[a-zA-Z0-9._-]+$ ]]
}

validate_client_name "${CLIENT_NAME}" || {
  echo "Error: client_name must contain only letters, digits, dot, underscore, or dash." >&2
  exit 1
}

[[ -r "${WG_CONF}" ]] || {
  echo "Error: server config not found/readable at ${WG_CONF}." >&2
  exit 1
}

grep -qF "${PEER_TAG}" "${WG_CONF}" || {
  echo "Error: peer '${CLIENT_NAME}' not found in ${WG_CONF}." >&2
  exit 1
}

wg show "${WG_IF}" >/dev/null 2>&1 || {
  echo "Error: interface ${WG_IF} is not active. Start wg-quick@${WG_IF} first." >&2
  exit 1
}

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
TMP_CONF="${TMPDIR}/${WG_IF}.conf"

CLIENT_PUB="$({
  awk -v tag="${PEER_TAG}" '
    BEGIN {in_block=0}
    $0 == tag {in_block=1; next}
    in_block && /^### peer:/ {exit}
    in_block && /^[[:space:]]*PublicKey[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, "", $0)
      gsub(/[[:space:]]+$/, "", $0)
      print
      exit
    }
  ' "${WG_CONF}"
} || true)"

awk -v tag="${PEER_TAG}" '
  BEGIN {skip=0}
  $0 == tag {skip=1; next}
  skip && /^### peer:/ {skip=0}
  !skip {print}
' "${WG_CONF}" > "${TMP_CONF}"

awk '
  NF {
    if (pending_blank) {
      print ""
      pending_blank=0
    }
    print
    next
  }
  { pending_blank=1 }
' "${TMP_CONF}" > "${TMPDIR}/${WG_IF}.normalized.conf"

install -m 600 "${TMPDIR}/${WG_IF}.normalized.conf" "${WG_CONF}"
wg syncconf "${WG_IF}" <(wg-quick strip "${WG_IF}")

if [[ -n "${CLIENT_PUB}" ]]; then
  echo "Removed peer '${CLIENT_NAME}' (PublicKey: ${CLIENT_PUB}) from ${WG_IF}."
else
  echo "Removed peer '${CLIENT_NAME}' from ${WG_IF}."
fi
