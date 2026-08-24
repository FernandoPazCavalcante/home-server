# home-server

Docker Compose stacks for a self-hosted home server. Each stack lives in its own `*-docker-compose.yaml` and can run independently. A `Makefile` wraps the common commands.

## Docs

- [`docs/setup.md`](docs/setup.md) — first-run checklist (Cloudflare token, dnsmasq, Zerotier, host forwarding).
- [`docs/troubleshooting-pihole-dns.md`](docs/troubleshooting-pihole-dns.md) — pihole/DNS issues hit during initial setup and their fixes.
- [`docs/calibre-gmail-oauth.md`](docs/calibre-gmail-oauth.md) — Gmail OAuth setup for Calibre-Web Automated (gmail.json, Docker workarounds, frozen-UI fix).

## Setup

Copy `.env.example` to `.env` and fill tokens (Cloudflare tunnels, Hardcover, ACME email, Cloudflare API token):

```sh
cp .env.example .env
```

Create the shared docker network for the reverse proxy (one-time):

```sh
make net-create
```

## Stacks

| Stack   | File                          | Services                                                            | Exposed via                |
| ------- | ----------------------------- | ------------------------------------------------------------------- | -------------------------- |
| `proxy` | `proxy-docker-compose.yaml`   | caddy (reverse proxy + TLS)                                         | binds host 80/443          |
| `books` | `books-docker-compose.yaml`   | calibre-web-automated, shelfmark, cloudflared                       | calibre/cloudflared, shelfmark/caddy |
| `media` | `media-docker-compose.yaml`   | qbittorrent, jackett, overseerr, radarr, sonarr, lidarr, flaresolverr, prowlarr, bazarr | caddy        |
| `net`   | `net-docker-compose.yaml`     | pihole                                                              | caddy + DNS :53            |
| `utils` | `utils-docker-compose.yaml`   | portainer, librespeed, watchtower, zerotier                         | portainer/librespeed via caddy |
| `plex`  | `plex-docker-compose.yaml`    | plex, cloudflared                                                   | cloudflared (public)       |
| `podcasts` | `podcasts-docker-compose.yaml` | audiobookshelf, cloudflared (castopod on standby, commented out) | cloudflared (public)    |
| `auth`  | `auth-docker-compose.yaml`    | keycloak, keycloak-db (postgres), cloudflared                       | cloudflared (public)       |

## Reverse proxy (Caddy)

Local-only (LAN + Zerotier VPN) services share one Caddy instance with a wildcard cert for `*.${HOME_DOMAIN}` issued via Cloudflare DNS-01. Each service self-declares its hostname through Docker labels — Caddy picks them up automatically when containers come up or down.

Hostnames:

| Service    | URL                                  |
| ---------- | ------------------------------------ |
| shelfmark  | `https://shelfmark.${HOME_DOMAIN}`   |
| pihole     | `https://pihole.${HOME_DOMAIN}`      |
| portainer  | `https://portainer.${HOME_DOMAIN}`   |
| librespeed | `https://speed.${HOME_DOMAIN}`       |
| qbittorrent| `https://qbittorrent.${HOME_DOMAIN}` |
| jackett    | `https://jackett.${HOME_DOMAIN}`     |
| overseerr  | `https://overseerr.${HOME_DOMAIN}`   |
| radarr     | `https://radarr.${HOME_DOMAIN}`      |
| sonarr     | `https://sonarr.${HOME_DOMAIN}`      |
| lidarr     | `https://lidarr.${HOME_DOMAIN}`      |
| prowlarr   | `https://prowlarr.${HOME_DOMAIN}`    |
| bazarr     | `https://bazarr.${HOME_DOMAIN}`      |

Calibre-Web Automated is not behind Caddy — it goes out through its own cloudflared tunnel at `https://library.fernandocavalcante.com` (host port `8083` on the LAN). Its OPDS catalog, for e-reader apps (KOReader, Moon+, Aldiko), is:

| Access | OPDS URL                                          |
| ------ | ------------------------------------------------- |
| Public | `https://library.fernandocavalcante.com/opds`     |
| LAN    | `http://<host-lan-ip>:8083/opds`                  |

OPDS uses HTTP Basic Auth with the calibre-web user/password.

Pi-hole local DNS must resolve `*.${HOME_DOMAIN}` to the host LAN IP (or use `dnsmasq.d` entry: `address=/${HOME_DOMAIN}/<host-lan-ip>`).

For VPN access via Zerotier:
- Set the Zerotier network DNS to the pihole IP (Zerotier Central → Network → DNS).
- Add a managed route for the LAN CIDR via the host's Zerotier IP.
- On the host: `sysctl net.ipv4.ip_forward=1` plus iptables MASQUERADE on the LAN interface.

## Run with Makefile

List all targets:

```sh
make help
```

### Run one stack

```sh
make proxy     # start caddy only
make books     # auto-starts proxy, then books
make media     # auto-starts proxy, then media
make net       # auto-starts proxy, then net (pihole)
make utils     # auto-starts proxy, then utils
make plex      # plex stack (uses its own cloudflared, no caddy dep)
make podcasts  # podcasts stack (own cloudflared, no caddy dep)
make auth      # auth stack (own cloudflared, no caddy dep)
```

### Stop one stack

```sh
make proxy-down
make books-down
make media-down
make net-down
make utils-down
make plex-down
make podcasts-down
make auth-down
```

`proxy` keeps running when individual proxied stacks are stopped, since other stacks may still need it.

### Tail logs of one stack

```sh
make proxy-logs
make books-logs
make media-logs
make net-logs
make utils-logs
make plex-logs
make podcasts-logs
make auth-logs
```

### Run everything

```sh
make all       # bring up every stack (creates caddy net first, builds caddy image)
make down      # stop every stack
make ps        # list all containers
make logs      # tail logs from every stack
```

## Run without Makefile

Equivalent docker compose commands:

```sh
docker network create caddy                                      # one-time
docker compose -f proxy-docker-compose.yaml up -d --build        # caddy
docker compose -f books-docker-compose.yaml up -d                # books

docker compose up -d --build                                     # all stacks
docker compose down                                              # stop all
```
