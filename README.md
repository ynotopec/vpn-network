# vpn-network

Ci-dessous une solution **WireGuard hub-and-spoke via VPS public** avec scripts **minimaux, idempotents**, non-interactifs (Ubuntu/Debian).
Hypothèse : le **VPS** a une IP publique (hub). Les **clients** sont derrière NAT et initient tous une connexion sortante vers le VPS.

---

## 0) Variables communes

Plan d’adressage (modifiable) :

* Réseau WG : `10.10.0.0/24`
* Serveur (VPS) : `10.10.0.1`
* Port WG : `51820/udp`
* Interface WG : `wg0`

---

## 1) Script serveur (VPS) : `wg-server-install.sh`

* Installe WireGuard
* Active l’IP forwarding
* Active NAT (iptables) vers l’interface WAN
* Génère clés si absentes
* Crée `/etc/wireguard/wg0.conf` si absent
* Démarre/enable `wg-quick@wg0`

```bash
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

# Detect default egress interface (WAN)
WAN_IF="${WAN_IF:-$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')}"
: "${WAN_IF:?Unable to detect WAN_IF. Set WAN_IF=eth0 (example).}"

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y --no-install-recommends wireguard iptables iproute2 ca-certificates

install -d -m 700 "${WG_DIR}"

# Keys (idempotent)
if [[ ! -s "${WG_PRIV}" ]]; then
  umask 077
  wg genkey | tee "${WG_PRIV}" | wg pubkey > "${WG_PUB}"
fi

# Sysctl forwarding (idempotent)
SYSCTL_FILE="/etc/sysctl.d/99-wireguard-forward.conf"
cat > "${SYSCTL_FILE}" <<EOF
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
sysctl --system >/dev/null

# Create base config only if missing (peers are appended later)
if [[ ! -f "${WG_CONF}" ]]; then
  umask 077
  cat > "${WG_CONF}" <<EOF
[Interface]
Address = ${WG_ADDR}
ListenPort = ${WG_PORT}
PrivateKey = $(cat "${WG_PRIV}")

# NAT + forward rules (iptables). Idempotent via -C checks.
PostUp = iptables -C FORWARD -i ${WG_IF} -j ACCEPT 2>/dev/null || iptables -A FORWARD -i ${WG_IF} -j ACCEPT; iptables -C FORWARD -o ${WG_IF} -j ACCEPT 2>/dev/null || iptables -A FORWARD -o ${WG_IF} -j ACCEPT; iptables -t nat -C POSTROUTING -s ${WG_NET} -o ${WAN_IF} -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s ${WG_NET} -o ${WAN_IF} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_IF} -j ACCEPT 2>/dev/null || true; iptables -D FORWARD -o ${WG_IF} -j ACCEPT 2>/dev/null || true; iptables -t nat -D POSTROUTING -s ${WG_NET} -o ${WAN_IF} -j MASQUERADE 2>/dev/null || true
EOF
fi

chmod 600 "${WG_CONF}" "${WG_PRIV}" "${WG_PUB}" || true

systemctl enable --now "wg-quick@${WG_IF}"

echo "=== Server ready ==="
echo "Public key: $(cat "${WG_PUB}")"
echo "Listen: UDP ${WG_PORT} on ${WAN_IF}"
```

Usage :

```bash
curl -fsSL https://example.invalid/wg-server-install.sh -o wg-server-install.sh
chmod +x wg-server-install.sh
WAN_IF=eth0 WG_PORT=51820 ./wg-server-install.sh
```

---

## 2) Script serveur : ajouter un client (peer) `wg-server-add-peer.sh`

* Ajoute un peer dans le fichier `wg0.conf` **si absent**
* Applique à chaud `wg syncconf`
* Sort une config client prête à copier (stdout)

```bash
#!/usr/bin/env bash
set -euo pipefail

WG_IF="${WG_IF:-wg0}"
WG_PORT="${WG_PORT:-51820}"
WG_NET_CIDR="${WG_NET_CIDR:-10.10.0.0/24}"
WG_SERVER_IP="${WG_SERVER_IP:-10.10.0.1}"
WG_DIR="/etc/wireguard"
WG_CONF="${WG_DIR}/${WG_IF}.conf"
WG_SERVER_PUB="${WG_DIR}/${WG_IF}.pub"

SERVER_ENDPOINT="${SERVER_ENDPOINT:?Set SERVER_ENDPOINT=your.vps.public.ip_or_dns}"
CLIENT_NAME="${1:?Usage: $0 <client_name> <client_ip_last_octet> [allowed_ips]}"
CLIENT_OCTET="${2:?Usage: $0 <client_name> <client_ip_last_octet> [allowed_ips]}"
CLIENT_ALLOWED="${3:-${WG_NET_CIDR}}"   # what client routes through wg; usually just WG net (mesh) or 0.0.0.0/0 (full tunnel)

CLIENT_IP="10.10.0.${CLIENT_OCTET}"
PEER_TAG="### peer:${CLIENT_NAME}"

# Client keys (generated on server for minimal interactions)
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
CLIENT_PRIV="${TMPDIR}/${CLIENT_NAME}.key"
CLIENT_PUB="${TMPDIR}/${CLIENT_NAME}.pub"
umask 077
wg genkey | tee "${CLIENT_PRIV}" | wg pubkey > "${CLIENT_PUB}"

# Append peer block if missing
if ! grep -qF "${PEER_TAG}" "${WG_CONF}"; then
  umask 077
  cat >> "${WG_CONF}" <<EOF

${PEER_TAG}
[Peer]
PublicKey = $(cat "${CLIENT_PUB}")
AllowedIPs = ${CLIENT_IP}/32
EOF
fi

# Apply live
wg syncconf "${WG_IF}" <(wg-quick strip "${WG_IF}")

# Emit client config
cat <<EOF
# ===== Client config: ${CLIENT_NAME} =====
[Interface]
Address = ${CLIENT_IP}/32
PrivateKey = $(cat "${CLIENT_PRIV}")
DNS = 1.1.1.1

[Peer]
PublicKey = $(cat "${WG_SERVER_PUB}")
Endpoint = ${SERVER_ENDPOINT}:${WG_PORT}
AllowedIPs = ${CLIENT_ALLOWED}
PersistentKeepalive = 25
EOF
```

Usage (sur VPS) :

```bash
chmod +x wg-server-add-peer.sh

# Exemple: client "laptop" = 10.10.0.2, routage uniquement du réseau WG
SERVER_ENDPOINT=vps.example.com ./wg-server-add-peer.sh laptop 2 > laptop.conf

# Exemple full-tunnel (tout passe dans le VPN depuis ce client) :
SERVER_ENDPOINT=vps.example.com ./wg-server-add-peer.sh laptop 2 "0.0.0.0/0" > laptop.conf
```

---

## 3) Script client (machine derrière NAT) : `wg-client-install.sh`

* Installe WireGuard
* Dépose `/etc/wireguard/wg0.conf` depuis un fichier fourni
* Démarre/enable

```bash
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

# Idempotent: replace config only if different
umask 077
if [[ ! -f "${WG_CONF}" ]] || ! cmp -s "${CLIENT_CONF_FILE}" "${WG_CONF}"; then
  install -m 600 "${CLIENT_CONF_FILE}" "${WG_CONF}"
fi

systemctl enable --now "wg-quick@${WG_IF}"
wg show "${WG_IF}" || true
```

Usage (sur client) :

```bash
chmod +x wg-client-install.sh
sudo ./wg-client-install.sh ./laptop.conf
```

---

## 4) Tests rapides

Sur serveur :

```bash
wg show
ss -lunp | grep 51820
```

Sur client :

```bash
wg show
ping -c1 10.10.0.1
ping -c1 10.10.0.2   # si un autre client existe
```

---

## Notes importantes (pratiques)

* Si le VPS est derrière pare-feu cloud, ouvrir **UDP 51820**.
* Si tu veux que les clients accèdent aussi au LAN du serveur (ou inverse), il faut ajouter des routes/AllowedIPs spécifiques (on peut le faire proprement après).
* Pour un réseau “mesh” (clients ↔ clients), la config ci-dessus marche : tout passe par le hub (VPS).

Si tu me donnes :

* l’interface WAN réelle du VPS (`ip route get 1.1.1.1`),
* si tu veux **full-tunnel** pour certains clients ou non,
* et le nombre de clients prévu,

je te fournis une variante “tout en un” (1 script serveur qui génère N conf clients d’un coup) et une version nftables (plus propre que iptables si tu préfères).
