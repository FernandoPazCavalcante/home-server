## Organization context

This repository is part of the **FernandoPazCavalcante's Org** organization. Shared org-wide context (overview, tech stack, CI/CD, observability, infrastructure, ticket workflow, integrations) lives in [`.midnax/`](./.midnax/) — read `.midnax/overview.md` first, then the domain files.

## What this is

Docker Compose stacks for a self-hosted home server. Each stack lives in its own `*-docker-compose.yaml` and can be started, stopped, and tailed independently. A `Makefile` wraps all common operations. A root `docker-compose.yaml` uses `include:` to aggregate every stack so `docker compose up` starts everything at once.

---

## Stacks

| Stack   | File                        | Key services                                                                                    | Exposed via                    |
|---------|-----------------------------|-------------------------------------------------------------------------------------------------|--------------------------------|
| `proxy` | `proxy-docker-compose.yaml` | Caddy (reverse proxy + TLS)                                                                     | host ports 80/443              |
| `books` | `books-docker-compose.yaml` | calibre-web-automated, shelfmark, cloudflared                                                   | shelfmark → caddy; calibre → cloudflared |
| `media` | `media-docker-compose.yaml` | qbittorrent, jackett, overseerr, radarr, sonarr, lidarr, flaresolverr, prowlarr, bazarr        | caddy                          |
| `net`   | `net-docker-compose.yaml`   | pihole                                                                                          | caddy + DNS :53 on `HOST_LAN_IP` |
| `utils` | `utils-docker-compose.yaml` | portainer, librespeed, watchtower, zerotier                                                     | portainer/librespeed → caddy   |
| `plex`  | `plex-docker-compose.yaml`  | plex, cloudflared                                                                               | cloudflared (public tunnel)    |

---

## Key directories and files

```
.env.example              # copy to .env and fill all values before first run
docker-compose.yaml       # root file: includes all stacks via `include:`
proxy-docker-compose.yaml # caddy stack
books-docker-compose.yaml
media-docker-compose.yaml
net-docker-compose.yaml
utils-docker-compose.yaml
plex-docker-compose.yaml
Makefile                  # all operational commands
proxy/
  Dockerfile              # xcaddy build: caddy-docker-proxy + cloudflare DNS plugin
  Caddyfile               # global TLS config; wildcard cert pre-issue for *.HOME_DOMAIN
pihole/
  etc-dnsmasq.d/
    02-home.conf.example  # template: copy to 02-home.conf, set HOME_DOMAIN + HOST_LAN_IP
docs/
  setup.md                # first-run checklist (Cloudflare token, dnsmasq, Zerotier, forwarding)
  troubleshooting-pihole-dns.md  # runbook for Pi-hole/DNS issues
```

---

## First-run setup

1. Copy and fill the env file:
   ```sh
   cp .env.example .env
   $EDITOR .env
   ```
   Required variables: `HOME_DOMAIN`, `ACME_EMAIL`, `CF_API_TOKEN` (Zone:DNS:Edit), `HOST_LAN_IP`, `TZ`, `PUID`, `PGID`, `BOOKS_DATA_DIR`, `MEDIA_DATA_DIR`, `TUNNEL_TOKEN_BOOKS`, `TUNNEL_TOKEN_PLEX`, `HARDCOVER_TOKEN`, `FTLCONF_webserver_api_password`.

2. Create the shared Docker network (one-time):
   ```sh
   make net-create
   ```

3. Configure Pi-hole local DNS override:
   ```sh
   cp ./pihole/etc-dnsmasq.d/02-home.conf.example ./pihole/etc-dnsmasq.d/02-home.conf
   $EDITOR ./pihole/etc-dnsmasq.d/02-home.conf
   # Set: address=/<HOME_DOMAIN>/<HOST_LAN_IP>
   ```

4. See `docs/setup.md` for Zerotier routing and host IP-forwarding steps.

---

## Makefile commands

### Bring up / tear down

```sh
make all          # create caddy network + bring up every stack (builds caddy image)
make down         # stop every stack

make proxy        # start caddy only
make books        # auto-starts proxy, then books
make media        # auto-starts proxy, then media
make net          # auto-starts proxy, then net (pihole)
make utils        # auto-starts proxy, then utils
make plex         # plex stack (no caddy dependency)

make proxy-down
make books-down
make media-down
make net-down
make utils-down
make plex-down
```

### Observe

```sh
make ps           # list all containers
make logs         # tail logs from every stack

make proxy-logs
make books-logs
make media-logs
make net-logs
make utils-logs
make plex-logs
```

### One-time

```sh
make net-create   # create external 'caddy' docker network (idempotent)
make help         # list all targets with descriptions
```

---

## Without Makefile (raw Docker Compose)

```sh
docker network create caddy                                       # one-time
docker compose -f proxy-docker-compose.yaml up -d --build        # caddy
docker compose -f books-docker-compose.yaml up -d                # books

docker compose up -d --build   # all stacks via root docker-compose.yaml
docker compose down
```

---

## Reverse proxy (Caddy)

- Custom Caddy image built from `proxy/Dockerfile` using `xcaddy` with two plugins:
  - `caddy-docker-proxy` — reads Docker labels to auto-generate virtual hosts
  - `caddy-dns/cloudflare` — DNS-01 challenge for wildcard TLS cert
- `proxy/Caddyfile` pre-issues a wildcard cert for `*.${HOME_DOMAIN}` at startup; per-service subdomains reuse it from `/data` storage.
- Services join the external `caddy` network and declare their hostname via Docker labels:
  ```yaml
  labels:
    caddy: myservice.${HOME_DOMAIN}
    caddy.reverse_proxy: "{{upstreams <port>}}"
  ```
- Pi-hole must resolve `*.${HOME_DOMAIN}` → `HOST_LAN_IP` via the `02-home.conf` dnsmasq rule.

---

## Pi-hole (net stack)

- Binds DNS on `${HOST_LAN_IP}:53` only (avoids conflict with `systemd-resolved` on `172.17.0.1:53`).
- Key env flags already set in `net-docker-compose.yaml`:
  - `FTLCONF_dns_listeningMode=ALL` — required when packets arrive via Docker NAT
  - `FTLCONF_misc_etc_dnsmasq_d=true` — enables `/etc/dnsmasq.d/*.conf` in Pi-hole v6
- Runtime data (`pihole/etc-pihole/`, `pihole/etc-dnsmasq.d/02-home.conf`) is gitignored; only `02-home.conf.example` is tracked.
- Hot-reload dnsmasq without restart: `docker exec pihole pihole reloaddns`

---

## Plex stack

- Runs with `network_mode: host` (both plex and cloudflared containers).
- Hardware transcoding via `/dev/dri` device passthrough; `VA_DRIVER=IHD`.
- Exposed publicly via Cloudflare Zero Trust tunnel (`TUNNEL_TOKEN_PLEX`).

---

## Conventions

- All proxied stacks (`books`, `media`, `net`, `utils`) depend on the `proxy` stack; `make <stack>` starts proxy first automatically.
- `proxy` is intentionally left running when individual stacks are stopped.
- Caddy runtime state (`proxy/data/`, `proxy/config/`) is gitignored — cert storage persists across rebuilds.
- `.env` is gitignored; `.env.example` is the canonical reference for all required variables.
- `PUID`/`PGID`/`UMASK`/`TZ` are passed uniformly to LinuxServer.io images.
- `bind.create_host_path: false` is used on data volume mounts — host paths must exist before `up`.

---

## Troubleshooting

See `docs/troubleshooting-pihole-dns.md` for a full runbook covering:
- Port 53 conflicts with `systemd-resolved`
- Pi-hole gravity build failures (bad upstream DNS)
- `FTLCONF_dns_listeningMode=ALL` requirement
- Pi-hole v6 dnsmasq.d opt-in (`FTLCONF_misc_etc_dnsmasq_d=true`)

Quick triage:
```sh
# Who holds port 53?
sudo ss -tulpn | grep ':53 '

# Pi-hole effective config
docker exec pihole pihole-FTL --list-config

# Reload dnsmasq overrides live
docker exec pihole pihole reloaddns

# Verify env vars reached the container
docker exec pihole sh -c 'env | grep -i FTLCONF'
```
