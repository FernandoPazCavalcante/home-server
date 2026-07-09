# Tech Stack

**Backend**
- Go 1.26+ (lazyswap): Bubble Tea (TUI), go-ethereum, btcd/btcutil, modernc.org/sqlite, charmbracelet/lipgloss+bubbles, go-bip39, go-qrcode; AES-256-GCM + PBKDF2 for key encryption.
- Node.js 18+ (marketingskills, resume): Playwright (Chromium) for PDF rendering; zero-dependency CLI scripts.
- Scala (rinha-de-backend-2024-q1): Gatling 3.10.3 (JDK 21) for load testing.
- Bash/Shell (home-server, flagsmith-charts): Docker Compose orchestration, Helm templating.

**Frontend**
- HTML/CSS (resume): static resumes (EN + PT).
- Markdown/YAML (marketingskills): Agent Skills content; Claude Code plugin marketplace.

**Infrastructure**
- Docker Compose (home-server, rinha-de-backend-2024-q1): multi-file stacks; Caddy v2 (xcaddy with docker-proxy + Cloudflare DNS plugins), Pi-hole v6, Cloudflare Tunnels, Zerotier VPN.
- Helm (flagsmith-charts): Kubernetes packaging; chart dependencies on Bitnami PostgreSQL, InfluxDB2.
- PostgreSQL, Nginx (rinha-de-backend-2024-q1 reference implementation).

