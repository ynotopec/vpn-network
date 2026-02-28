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
- `scripts/wg-client-uninstall.sh`
  - Arrête/désactive `wg-quick@wg0` côté client
  - Supprime `/etc/wireguard/wg0.conf`
  - Désinstalle le paquet `wireguard`
- `scripts/wg-server-uninstall.sh`
  - Arrête/désactive `wg-quick@wg0` côté serveur
  - Supprime la configuration et les clés du serveur
  - Désinstalle le paquet `wireguard`

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

# Port custom (ex: si WireGuard écoute sur 443/udp)
sudo SERVER_ENDPOINT=vps.example.com:443 ./scripts/wg-server-add-peer.sh laptop 2 > laptop.conf

# Full tunnel depuis le client
sudo SERVER_ENDPOINT=vps.example.com ./scripts/wg-server-add-peer.sh laptop 2 "0.0.0.0/0" > laptop.conf
```

> `SERVER_ENDPOINT` accepte un hôte/IP seul (port détecté depuis `ListenPort` de `/etc/wireguard/wg0.conf`, sinon `51820`) ou un endpoint déjà port-aware (`host:port`, `1.2.3.4:port`, `[IPv6]:port`).
>
> Si besoin, vous pouvez forcer le port côté client via `WG_PORT=<port>` lors de l'exécution de `wg-server-add-peer.sh`.

### 3) Installer le client

```bash
chmod +x scripts/wg-client-install.sh
sudo ./scripts/wg-client-install.sh ./laptop.conf
```

### 4) Désinstaller (optionnel)

Client :

```bash
chmod +x scripts/wg-client-uninstall.sh
sudo ./scripts/wg-client-uninstall.sh
```

Serveur :

```bash
chmod +x scripts/wg-server-uninstall.sh
sudo ./scripts/wg-server-uninstall.sh
```

## Vérifications rapides

Sur serveur :

```bash
sudo wg show
sudo ss -lunp | grep wg
```

Sur client :

```bash
sudo wg show
ping -c1 10.10.0.1
```

## CI

Un workflow GitHub Actions est ajouté pour valider la syntaxe bash (`bash -n`) et exécuter `shellcheck` sur les scripts.
