# Observability

**Backend**
- lazyswap: File-based logger only (`internal/applog` → `~/.lazyswap/lazyswap.log`). No external monitoring/tracing.

**Infrastructure**
- flagsmith-charts: Prometheus ServiceMonitor support configurable in `values.yaml` (`serviceMonitor.enabled`). No external monitoring tooling configured in repo.
- home-server: Watchtower for automatic container image updates. No logging/tracing stack configured.

**Not configured:** marketingskills, resume, rinha-de-backend-2024-q1.

