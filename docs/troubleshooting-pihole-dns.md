# Pi-hole / DNS troubleshooting

Ordered log of the issues hit while bringing pihole up on this host (Arch Linux + Docker), with the diagnostics used at each step and the fix applied. Use as a runbook the next time something on this stack goes wrong.

## Issue 1 — port 53 already in use (compose start fails)

### Symptom

```
docker compose -f net-docker-compose.yaml up -d
Error response from daemon: failed to set up container networking: driver failed
programming external connectivity on endpoint pihole (...):
failed to bind host port 0.0.0.0:53/tcp: address already in use
```

### Diagnostic

```sh
sudo ss -tulpn | grep ':53 '
```

Output showed `systemd-resolve` holding the port:

```
udp ... 127.0.0.53%lo:53 ... users:(("systemd-resolve",pid=937,fd=20))
tcp ... 127.0.0.53%lo:53 ... users:(("systemd-resolve",pid=937,fd=21))
udp ... 172.17.0.1:53    ... users:(("systemd-resolve",pid=937,fd=24))
tcp ... 172.17.0.1:53    ... users:(("systemd-resolve",pid=937,fd=25))
```

Two listeners:

1. The local stub on `127.0.0.53` (default systemd-resolved behavior).
2. An extra listener on the docker bridge `172.17.0.1`, configured by `/etc/systemd/resolved.conf.d/20-docker-dns.conf` to give bridge containers DNS via the host.

### Fix

**Disable the local stub listener** so `0.0.0.0:53` becomes available:

```sh
sudo mkdir -p /etc/systemd/resolved.conf.d
echo -e "[Resolve]\nDNSStubListener=no" \
  | sudo tee /etc/systemd/resolved.conf.d/no-stub.conf

sudo systemctl restart systemd-resolved

# /etc/resolv.conf was symlinked to the stub; switch to the real one
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

sudo ss -tulpn | grep ':53 '   # 127.0.0.53 entries gone
```

This freed `127.0.0.53:53`, but `172.17.0.1:53` was still bound (the docker-bridge listener is set elsewhere). Pi-hole's compose mapping `0.0.0.0:53:53` overlapped with that and still failed.

**Bind pihole to the LAN IP only** rather than `0.0.0.0`:

```yaml
# net-docker-compose.yaml
ports:
  - "${HOST_LAN_IP}:53:53/tcp"
  - "${HOST_LAN_IP}:53:53/udp"
```

Add `HOST_LAN_IP=192.168.X.Y` to `.env`. systemd-resolved keeps `172.17.0.1:53` for docker containers; pihole owns `192.168.X.Y:53` for LAN/VPN clients. No conflict.

```sh
docker compose -f net-docker-compose.yaml up -d --force-recreate pihole
sudo ss -tulpn | grep ':53 '   # pihole's docker-proxy listening on the LAN IP
```

> Lesson: don't blindly nuke `20-docker-dns.conf`. It exists so containers on the default bridge can resolve via the host. Removing it breaks DNS inside any non-pihole bridge container.

---

## Issue 2 — pihole keeps restarting, log says "DNS resolution is currently unavailable"

### Symptom

```sh
docker logs pihole 2>&1 | tail -30
```

Showed:

```
[i] No DNS upstream set in environment or config file, defaulting to Google DNS
...
[i] /etc/pihole/gravity.db does not exist (Likely due to a fresh volume).
[i] Gravity will now be run to create the database
[✗] DNS resolution is currently unavailable
```

The container was healthy but pihole-FTL wasn't binding port 53 because gravity (the blocklist DB) couldn't be built.

### Diagnostic

The compose file pointed pihole at its own removed cloudflared sidecar:

```yaml
- PIHOLE_DNS_=127.0.0.1#5054   # ← was the cloudflared service we deleted
```

Gravity downloads adlist URLs over DNS, and there was no resolver listening on 5054. Without working DNS, gravity stalls and FTL never finishes startup.

### Fix

Point upstream DNS at real public resolvers:

```yaml
- PIHOLE_DNS_=1.1.1.1;1.0.0.1;8.8.8.8;8.8.4.4
```

```sh
docker compose -f net-docker-compose.yaml up -d --force-recreate pihole
docker logs -f pihole          # wait for "DNS resolution is now available"
```

> Lesson: when removing a service that another service depends on (here, cloudflared was the upstream DNS for pihole), update the dependent service's config too.

---

## Issue 3 — `dig` from the host returns "connection refused"

### Symptom

```
dig @192.168.1.10 shelfmark.home.example.com +short
;; communications error to 192.168.1.10#53: connection refused
```

### Diagnostic

`docker ps` and `docker logs pihole` showed the container restarting because of either Issue 1 or Issue 2 above. After fixing those, port 53 came up but the next attempt timed out instead of refusing.

### Fix

Resolve Issue 1 + 2 first, then move on to Issue 4.

---

## Issue 4 — `dig` times out (port open, no answer)

### Symptom

```
dig @192.168.1.10 shelfmark.home.example.com +short
;; communications error to 192.168.1.10#53: timed out
```

### Diagnostic

```sh
docker logs pihole 2>&1 | tail -20
```

Found:

```
WARNING: dnsmasq: ignoring query from non-local network 192.168.1.10 (logged only once)
```

dnsmasq's `local-service` flag rejects queries whose source IP is "non-local" from its perspective. Through Docker's NAT, the source address looked like an external network even when sent from the host itself.

### Fix

Set Pi-hole's listening mode to `ALL`:

```yaml
- FTLCONF_dns_listeningMode=ALL
```

```sh
docker compose -f net-docker-compose.yaml up -d --force-recreate pihole
sleep 5
dig @192.168.1.10 shelfmark.home.example.com +short
```

Empty / NXDOMAIN now means we hit Issue 5 — pihole answered but didn't have the override loaded.

> Lesson: Pi-hole v6's default `LOCAL` listening mode is too restrictive when packets arrive via Docker NAT. Use `ALL` for a containerized pihole that serves a real LAN.

---

## Issue 5 — NXDOMAIN: dnsmasq.d override not applied

### Symptom

```
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 25004
;; AUTHORITY SECTION:
example.com. 1726 IN SOA gabe.ns.cloudflare.com. dns.cloudflare.com. ...
```

Pi-hole forwarded the query upstream and got NXDOMAIN from authoritative DNS — meaning the local override wasn't loaded.

### Diagnostic

The file existed inside the container:

```sh
docker exec pihole ls -la /etc/dnsmasq.d/
# 02-home.conf present
docker exec pihole cat /etc/dnsmasq.d/02-home.conf
# address=/home.example.com/192.168.1.10
```

But `pihole-FTL --list-config | grep etc_dnsmasq` returned **empty** — Pi-hole v6 ignores `/etc/dnsmasq.d/` by default.

### Fix

Enable the legacy dnsmasq.d include in v6:

```yaml
- FTLCONF_misc_etc_dnsmasq_d=true
```

```sh
docker compose -f net-docker-compose.yaml up -d --force-recreate pihole
sleep 5
dig @192.168.1.10 shelfmark.home.example.com +short
# 192.168.1.10
```

> Lesson: Pi-hole v6 moved its dnsmasq config to native TOML. Custom `/etc/dnsmasq.d/*.conf` files require an explicit opt-in via `FTLCONF_misc_etc_dnsmasq_d=true`.

---

## Quick triage cheat sheet

| Symptom                           | First check                                                            | Likely cause                                          |
| --------------------------------- | ---------------------------------------------------------------------- | ----------------------------------------------------- |
| `bind: address already in use`    | `sudo ss -tulpn \| grep ':53 '`                                       | systemd-resolved on `127.0.0.53` or `172.17.0.1`      |
| Container restarts, no port open  | `docker logs pihole \| tail -30`                                       | Gravity build stalled — bad upstream DNS              |
| `connection refused`              | `docker ps`, port-mapping in `docker ps`                               | Container not running / port not bound                |
| `connection timed out`            | `docker logs pihole \| grep ignoring`                                  | `listeningMode=LOCAL` rejects NATed source            |
| NXDOMAIN for local-only host      | `docker exec pihole pihole-FTL --list-config \| grep etc_dnsmasq`     | dnsmasq.d include disabled (v6 default)               |
| Query slow but eventually answers | `dig +trace ...`                                                       | Override missing, falling back upstream               |

## Useful commands while debugging

```sh
# Who's holding port 53?
sudo ss -tulpn | grep ':53 '

# Pihole effective config (shows what FTL is reading)
docker exec pihole pihole-FTL --list-config

# Reload dnsmasq.d files without restarting the container
docker exec pihole pihole reloaddns

# Recreate pihole picking up new env vars
docker compose -f net-docker-compose.yaml up -d --force-recreate pihole

# Watch FTL logs live
docker exec pihole tail -f /var/log/pihole/FTL.log

# Verify env reached the container
docker exec pihole sh -c 'env | grep -i FTLCONF'
```
