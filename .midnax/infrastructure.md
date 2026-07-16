# Infrastructure

**Cloud & IaC**
- No cloud provider IaC across the org. GitHub Actions for CI/CD (GitHub-hosted runners).
- flagsmith-charts: Kubernetes target (OpenShift also documented); Helm for packaging. Chart dependencies: Bitnami PostgreSQL, InfluxDB2, local Graphite sub-chart. GitHub Pages hosts Helm repo index.
- home-server: Self-hosted bare-metal/Linux (Arch Linux); Docker Compose for orchestration. Cloudflare DNS-01 for TLS wildcard certs; Cloudflare Zero Trust tunnels for public access; Zerotier for VPN LAN routing.

**Containers & Orchestration**
- Docker Compose (home-server, rinha-de-backend-2024-q1 participant submissions).
- Kubernetes (flagsmith-charts target).

**Managed Services**
- Cloudflare (DNS, Zero Trust tunnels, TLS).
- GitHub (Releases, Pages, Actions).

**Local/Standalone**
- lazyswap: Pure local binary; data in `~/.lazyswap/` (SQLite DB + log). Connects to public EVM RPC endpoints and THORchain API at runtime.
- resume: No runtime infra; GitHub Releases for PDF distribution.
