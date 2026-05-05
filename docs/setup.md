# Initial setup

Steps to perform once before bringing the proxied stacks up.

## Required actions

1. Fill `.env` with `ACME_EMAIL`, `CF_API_TOKEN`, and `HOST_LAN_IP`. The Cloudflare token must have `Zone:DNS:Edit` on `example.com` (see [Cloudflare API token](#1-cloudflare-api-token)).
2. `make net-create` (one time) — creates the shared `caddy` docker network.
3. Configure pihole local DNS (see [dnsmasq.d for Pi-hole](#3-dnsmasqd-for-pi-hole)).
4. Zerotier Central: set network DNS to pihole IP, add managed route for LAN CIDR via host zerotier IP.
5. Host: enable IP forward + iptables MASQUERADE.

After these, `make proxy` builds the Caddy image and starts it. `make books` (or any other proxied stack) adds its routes automatically via Docker labels.

> **Caveat**: the Caddyfile uses `{$VAR}` substitution that runs at Caddy startup, not at compose render time — variables come from container env. Pre-issuing the wildcard requires Caddy to validate the DNS-01 challenge against `*.${HOME_DOMAIN}` once on startup; subsequent label-generated subdomains reuse the wildcard cert from `/data` storage.

---

## 1. Cloudflare API token

Steps in the Cloudflare dashboard:

1. Log in → top-right profile → **My Profile** → **API Tokens** tab.
2. Click **Create Token**.
3. Use template **Edit zone DNS** (or **Create Custom Token** for tighter scope).
4. Configure:
   - **Token name**: `caddy-home-server-dns01`
   - **Permissions**:
     - `Zone` · `DNS` · `Edit`
     - `Zone` · `Zone` · `Read`
   - **Zone Resources**: `Include` → `Specific zone` → `example.com`
   - **Client IP Address Filtering**: leave empty (DNS-01 challenge runs from your home server outbound; Cloudflare API has no fixed source IP requirement).
   - **TTL**: optional. Set 1y or leave empty.
5. **Continue to summary** → **Create Token**.
6. Copy the token (shown once). Paste into `.env` as `CF_API_TOKEN=...`.

Verify:

```sh
curl -H "Authorization: Bearer <token>" https://api.cloudflare.com/client/v4/user/tokens/verify
```

Should return `"status":"active"`.

---

## 2. Find your host LAN IP

Needed for `HOST_LAN_IP` in `.env` and for the dnsmasq.d address rule.

```sh
ip -4 addr show | grep -E 'inet (192\.168|10\.|172\.)' | grep -v docker | grep -v zt
```

Sample output:

```
inet 192.168.1.42/24 brd 192.168.1.255 scope global eth0
```

LAN IP = `192.168.1.42`.

Alternatives:

```sh
ip route get 1.1.1.1 | awk '{for (i=1;i<=NF;i++) if ($i=="src") print $(i+1)}'
```

> **Recommended**: assign a static DHCP lease in your router for the host's MAC address so the IP never changes. Otherwise pihole's `address=/.../<ip>` rule becomes stale on lease renewal.

---

## 3. dnsmasq.d for Pi-hole

Pi-hole reads `*.conf` files in its dnsmasq directory (mounted at `./pihole/etc-dnsmasq.d` per `net-docker-compose.yaml`).

Pi-hole v6 ignores this directory by default — `FTLCONF_misc_etc_dnsmasq_d=true` is already set in `net-docker-compose.yaml` to enable it.

Copy the tracked template into place and edit with your `HOME_DOMAIN` and `HOST_LAN_IP`:

```sh
cp ./pihole/etc-dnsmasq.d/02-home.conf.example ./pihole/etc-dnsmasq.d/02-home.conf
$EDITOR ./pihole/etc-dnsmasq.d/02-home.conf
```

Final content (example):

```conf
# Resolve every *.home.example.com to the home-server LAN IP.
address=/home.example.com/192.168.1.10
```

> The runtime `02-home.conf` is gitignored (along with the rest of `pihole/`) so each clone keeps its own values; only `02-home.conf.example` is committed.

Apply (recreate pihole so the file is read on startup):

```sh
docker compose -f net-docker-compose.yaml up -d --force-recreate pihole
# OR hot-reload without restart:
docker exec pihole pihole reloaddns
```

Test from a LAN client:

```sh
dig @<pihole-ip> shelfmark.home.example.com +short
# Should return 192.168.1.10
```

Then point router DHCP DNS at the pihole IP so all LAN devices use it automatically (see [Point router DHCP DNS at pihole](#point-router-dhcp-dns-at-pihole)).

---

## Point router DHCP DNS at pihole

UI varies per router. General path:

1. Open router admin. Find your gateway IP first:
   ```sh
   ip route | awk '/default/ {print $3}'
   ```
   Open `http://<gateway-ip>` in a browser. Login.
2. Find the DHCP server section. Menu names by vendor:
   - TP-Link: *Advanced → Network → DHCP Server*
   - ASUS: *LAN → DHCP Server*
   - Ubiquiti UniFi: *Settings → Networks → LAN → DHCP Service*
   - OpenWrt: *Network → DHCP and DNS*
   - Mikrotik: *IP → DHCP Server → Networks*
   - ISP combo modem: usually *Home Network* / *LAN setup*
3. Field name: **DNS Server 1** / **Primary DNS** / **DNS Servers Issued To Clients**.
4. Set:
   - **Primary DNS**: `192.168.1.10` (your pihole / host LAN IP)
   - **Secondary DNS**: empty (strict pihole) **or** `1.1.1.1` (fallback when pihole is down — clients bypass it in that case)
5. Save / Apply.
6. While in the same UI, reserve a **static DHCP lease** for the host's MAC → `192.168.1.10`. Stops IP drift from breaking the pihole `address=` rule.
7. Renew DHCP on a client to verify:
   ```sh
   # Linux
   sudo dhclient -r && sudo dhclient

   # Windows
   ipconfig /release && ipconfig /renew

   # macOS
   # System Settings → Network → Wi-Fi → Details → TCP/IP → Renew DHCP Lease
   ```
8. Confirm the client picked up pihole as DNS:
   ```sh
   resolvectl status | grep "DNS Servers"      # Linux/systemd
   scutil --dns | grep nameserver              # macOS
   ipconfig /all | findstr "DNS Servers"       # Windows
   ```
   Should show `192.168.1.10`.

### Caveats

- **ISP-locked modems** sometimes forbid custom DHCP DNS. Workaround: put the modem in bridge mode and use your own router, or configure DNS manually per-device.
- **IPv6**: if the router advertises IPv6 DNS via SLAAC / DHCPv6, also set the pihole's IPv6 address there (or disable IPv6 DNS advertisement), otherwise clients prefer IPv6 DNS and bypass pihole.
- Some firmware requires a **router reboot** before already-leased clients pick up the new DNS.

---

## 4 + 5. Zerotier routing + host forwarding

Goal: VPN clients reach `192.168.1.0/24` (your LAN) via the home server's Zerotier IP, with Pi-hole as DNS.

### Discover values

```sh
# Host LAN IP and interface (e.g. 192.168.1.10 / eth0)
ip -4 addr show | grep -E "inet 192\.|inet 10\."

# Zerotier interface and IP on the host (after joining network) — e.g. ztabcd1234, 10.147.17.5/24
ip -4 addr show | grep zt

# Zerotier network ID
docker exec myzerotier zerotier-cli listnetworks
```

Substitute these in the steps below.

### 5a. Enable IP forwarding on the host (persistent)

```sh
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-zerotier-forward.conf
sudo sysctl --system
sysctl net.ipv4.ip_forward      # confirm shows 1
```

### 5b. NAT / MASQUERADE

Translate VPN-sourced packets so LAN hosts reply to the gateway (the home server) instead of the unknown Zerotier IP.

Replace `eth0` and `ztabcd1234` with your interfaces:

```sh
# Outbound: VPN traffic leaving on the LAN interface gets NATed
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Allow forwarding both directions
sudo iptables -A FORWARD -i ztabcd1234 -o eth0 -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o ztabcd1234 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

Persist on Arch:

```sh
sudo pacman -S iptables-nft     # if not already
sudo iptables-save | sudo tee /etc/iptables/iptables.rules
sudo systemctl enable --now iptables
```

### 4. Zerotier Central — DNS + managed route

Open <https://my.zerotier.com> → your network.

**Managed Routes**:

| Destination      | (Via) Gateway                              |
| ---------------- | ------------------------------------------ |
| `10.147.17.0/24` | _(blank — default Zerotier subnet)_        |
| `192.168.1.0/24` | `10.147.17.5`                              |

Replace `192.168.1.0/24` with your real LAN CIDR and `10.147.17.5` with the home server's Zerotier IP.

**DNS**:

- **Search Domain**: `home.example.com`
- **Server Address**: `<pihole-ip>` — use the host LAN IP since pihole binds DNS port 53 on host via the `:53:53` mapping. Alternatively the Zerotier IP of the host.

> **Paid feature.** The DNS section in Zerotier Central is **not available on the free plan** — controller-side DNS push requires a paid tier. On free, set DNS manually per client instead: configure each device's resolver to `<pihole-ip>` (LAN setting on the router for LAN devices, or per-app/per-network DNS override on the VPN client). Custom DNS in the mobile Zerotier app works on the free plan and is the simplest workaround for phones.

**Members**:

- Authorize each device.
- Tick **Allow Default Route Override** on the network if you want all client traffic (not just LAN) tunneled. Optional.

### 5c. Client side (per device)

- macOS / iOS / Windows / Android: install Zerotier client, join network ID, accept the **Allow Managed DNS** / **Allow Default Route** prompts (some platforms require these to be opted-in even after the controller pushes them).
- Linux: `sudo zerotier-cli join <network-id>` then `sudo zerotier-cli set <network-id> allowDNS=1 allowGlobal=1 allowDefault=1`.

> **DNS over HTTPS / Private DNS breaks pushed DNS.** If the phone has **Private DNS** (Android: Settings → Network → Private DNS) set to anything other than _Off_ / _Automatic_, or iOS has a DoH/DoT profile installed, the OS bypasses VPN-pushed DNS and queries the encrypted resolver directly. Pi-hole never sees the query and `*.home.example.com` returns NXDOMAIN. Disable Private DNS / remove DoH profiles on every client that should resolve via pihole.
>
> **Termux is misleading.** `nslookup` inside Termux uses a hardcoded 8.8.8.8 and ignores Android system DNS entirely — not a valid test of whether the OS is using pihole. Test in the actual browser or with `nslookup <host> 192.168.1.10` (explicit server) instead.

### 5d. Smoke test (from outside your LAN, on Zerotier)

```sh
# Should resolve to LAN IP
nslookup shelfmark.home.example.com

# Should reach Caddy on the home server LAN IP through the tunnel
curl -kI https://shelfmark.home.example.com
```

If DNS resolves but TCP fails: forwarding/MASQUERADE wrong. Check `iptables -t nat -L POSTROUTING -n -v` shows packets in the `MASQUERADE` row.

If DNS fails: Zerotier client didn't apply pushed DNS — confirm with `resolvectl status` (Linux) or check macOS Network → DNS pane.

---

## Caveats

- **Pi-hole port 53 binding**: pihole publishes `${HOST_LAN_IP}:53:53` to avoid conflicting with `systemd-resolved`'s docker bridge listener (`172.17.0.1:53`). If `systemd-resolved`'s stub listener (`127.0.0.53:53`) is still enabled it will not conflict, but if you ever change to `0.0.0.0:53` you must disable the stub. See [`troubleshooting-pihole-dns.md`](./troubleshooting-pihole-dns.md).
- **iptables rules** above are basic. If you run `ufw`/`firewalld`, integrate via those tools instead.
- **Zerotier `myzerotier` container** uses `network_mode: host` already — no port adjustments needed.
