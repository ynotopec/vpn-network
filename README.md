# vpn-network

Configuration WireGuard **hub-and-spoke via VPS public** pour Ubuntu/Debian.

- Le VPS joue le rôle de hub (IP publique).
- Les clients peuvent être derrière NAT (connexion sortante vers le VPS).
- Les scripts sont non-interactifs et idempotents.

## Plan d’adressage par défaut

- Réseau WG : `10.10.0.0/24`
- Serveur : `10.10.0.1`
- Port : `51820/udp`
- Interface : `wg0`

## Scripts versionnés

- `scripts/wg-server-install.sh`
  - Installe WireGuard côté VPS
  - Active forwarding + NAT iptables
  - Crée la config serveur si absente
- `scripts/wg-server-add-peer.sh`
  - Ajoute un peer au serveur si absent
  - Génère une config client sur stdout
  - Validation de base des entrées (`octet`, `allowed_ips`)
- `scripts/wg-client-install.sh`
  - Installe WireGuard côté client
  - Déploie `/etc/wireguard/wg0.conf`
  - Active `wg-quick@wg0`

## Utilisation

### 1) Installer le serveur (VPS)

```bash
chmod +x scripts/wg-server-install.sh
sudo WAN_IF=eth0 WG_PORT=51820 ./scripts/wg-server-install.sh
```

### 2) Ajouter un client depuis le VPS

```bash
chmod +x scripts/wg-server-add-peer.sh

# Client "laptop" => 10.10.0.2
sudo SERVER_ENDPOINT=vps.example.com ./scripts/wg-server-add-peer.sh laptop 2 > laptop.conf

# Full tunnel depuis le client
sudo SERVER_ENDPOINT=vps.example.com ./scripts/wg-server-add-peer.sh laptop 2 "0.0.0.0/0" > laptop.conf
```

### 3) Installer le client

```bash
chmod +x scripts/wg-client-install.sh
sudo ./scripts/wg-client-install.sh ./laptop.conf
```

## Vérifications rapides

Sur serveur :

```bash
sudo wg show
sudo ss -lunp | grep 51820
```

Sur client :

```bash
sudo wg show
ping -c1 10.10.0.1
```

## CI

Un workflow GitHub Actions est ajouté pour valider la syntaxe bash (`bash -n`) et exécuter `shellcheck` sur les scripts.
