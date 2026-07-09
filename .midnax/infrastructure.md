# Infrastructure

**Cloud & IaC**
- No cloud provider (AWS/GCP/Azure) used. All repos are either local binaries, GitHub-hosted runners, or self-hosted bare-metal.
- No IaC tooling (Terraform, CloudFormation, etc.).

**Containerization & Orchestration**
- Docker Compose (home-server, rinha-de-backend-2024-q1): multi-file stacks; resource caps enforced (rinha: ≤1.5 CPU, ≤550 MB RAM).
- Kubernetes (flagsmith-charts): Helm charts for self-hosting; OpenShift also documented.
- GitHub Actions runners (ubuntu-latest, ubuntu-slim): lazyswap, marketingskills, resume, flagsmith-charts.

**Managed Services & Key Infrastructure**
- PostgreSQL (flagsmith-charts, rinha-de-backend-2024-q1 reference).
- InfluxDB2 (flagsmith-charts dependency).
- Cloudflare (home-server): DNS-01 TLS, Zero Trust tunnels, Zerotier VPN.
- GitHub Pages (flagsmith-charts): Helm repo index hosting.
- GitHub Releases (lazyswap, resume, flagsmith-charts): artifact distribution.

**Self-Hosted Services**
- home-server: Caddy v2 (reverse proxy), Pi-hole v6 (DNS), Plex, qBittorrent, Radarr, Sonarr, Lidarr, Prowlarr, Jackett, Bazarr, Overseerr, FlareSolverr, Portainer, Watchtower, LibreSpeed, Calibre-Web-Automated, Shelfmark.

