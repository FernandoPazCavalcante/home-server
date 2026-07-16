# CI/CD

**Backend**
- lazyswap: GitHub Actions (`release.yml`) on push to `master`; cross-compiles Go (CGO_ENABLED=0) for linux/darwin × amd64/arm64 → `dist/`; runs `npx semantic-release@24`. Branch strategy: `master` → beta prereleases, `stable` → full releases. Artifacts: `.tar.gz` + `.sha256` to GitHub Releases.
- rinha-de-backend-2024-q1: GitHub Actions (`repo-lockdown.yml`) auto-closes PRs/issues post-deadline (2024-03-11). No build/deploy pipeline.

**Frontend**
- resume: GitHub Actions (`generate-pdf-release.yml`) on `v*` tags; Playwright renders HTML → A4 PDFs; creates GitHub Release with artifacts (90-day retention).
- marketingskills: GitHub Actions on `main` branch. `validate-skill.yml` (PR): Flash-Brew-Digital/validate-skill@v1 per changed skill. `sync-skills.yml` (push): node script updates `marketplace.json` + `README.md` via auto-commit.

**Infrastructure**
- flagsmith-charts: GitHub Actions on `main` / PRs. `lint-test.yaml` (PR): chart-testing (ct lint + ct install) with kind cluster. `release-please.yml` (push): googleapis/release-please-action manages versioning. `release.yaml` (tag): builds chart tarball, uploads to GitHub Release, updates gh-pages Helm repo index. Pre-commit: check-yaml + prettier. Conventional Commit enforcement.
