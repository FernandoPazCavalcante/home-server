# Observability

**Backend**
- lazyswap: File-based logger only (`internal/applog` → `~/.lazyswap/lazyswap.log`). No external monitoring/tracing.

**Infrastructure**
- flagsmith-charts: Prometheus ServiceMonitor support configurable in `values.yaml` (`serviceMonitor.enabled`). No external monitoring tooling configured in repo itself.

All other repos: No observability tooling configured.
