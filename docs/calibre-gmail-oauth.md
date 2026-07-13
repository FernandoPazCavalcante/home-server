# Calibre-Web Automated / Gmail OAuth setup

Ordered log of the issues hit while wiring the **Setup Gmail Account** button in Calibre-Web Automated (dockerized) to a real Google OAuth client, with the diagnostics used at each step and the fix applied. Use as a runbook if the setup has to be redone (e.g. token revoked, new Google account).

**TL;DR of the end state:** `gmail.json` (a Google OAuth *Desktop app* client secret) lives in the calibre config dir; the container publishes port `8085` for the OAuth loopback redirect; two ephemeral patches inside the container make the flow survive Docker. Once the button flow completes, the token is stored in `app.db` and everything except `gmail.json` can be removed.

> **Alternative that avoids all of this:** Gmail App Password + plain SMTP (`smtp.gmail.com`, port 587, STARTTLS) in the email settings. No gmail.json, no Google Cloud project, no container patching. The OAuth route below was chosen deliberately; if it breaks again, consider switching.

## How the button works (background)

`cps/services/gmail.py` in the container:

- Looks for `/config/gmail.json` (`CONFIG_DIR` + `gmail.json`). Missing file → *"Found no valid gmail.json file with OAuth information"*.
- Runs Google's `InstalledAppFlow.run_local_server()` — a one-shot local HTTP server that waits for the browser redirect from Google, then exchanges the code for a token.
- Stores the resulting token (with refresh token) in `app.db`, so the flow is **one-time**; gmail.json is only read again if the token is wiped.

Scopes requested: `openid`, `gmail.send`, `userinfo.email`.

## Issue 1 — "Found no valid gmail.json file with OAuth information"

### Symptom

Message shown when clicking **Setup Gmail Account** in Admin → Edit Email Server Settings.

### Diagnostic

```sh
docker exec calibre-web-automated grep -rn "gmail.json" /app --include="*.py"
# -> cps/services/gmail.py: cred_file = os.path.join(CONFIG_DIR, 'gmail.json')
```

`CONFIG_DIR` is `/config`, which is the bind mount `${BOOKS_DATA_DIR}/calibre/config` (see `books-docker-compose.yaml`). The file simply didn't exist.

### Fix

Create a Google OAuth client and drop its secret file at `${BOOKS_DATA_DIR}/calibre/config/gmail.json`:

1. [Google Cloud Console](https://console.cloud.google.com) → create/select a project.
2. **APIs & Services → Library** → enable **Gmail API**.
3. **OAuth consent screen** → External → add your own Gmail address as a *test user* (the app stays unverified; test users can still authorize it).
4. **Credentials → Create Credentials → OAuth client ID → Desktop app** → **Download JSON**.
5. Save the downloaded JSON as `gmail.json` in the config dir. Format for reference:

```json
{
  "installed": {
    "client_id": "<...>.apps.googleusercontent.com",
    "project_id": "<project>",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
    "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
    "client_secret": "<...>",
    "redirect_uris": ["http://localhost"]
  }
}
```

No container restart needed — the file is read on button click, not at startup.

## Issue 2 — "could not locate runnable browser"

### Symptom

Clicking the button after gmail.json exists raises `could not locate runnable browser`.

### Diagnostic

`gmail.py` calls `flow.run_local_server(port=0)`, which by default tries to `webbrowser.open()` the Google login URL — inside the container, where no browser exists. Even if it hadn't, `port=0` picks a random unpublished port, so Google's redirect to `localhost:<port>` could never reach the container.

### Fix

Two parts:

1. Publish a fixed port in `books-docker-compose.yaml` under `calibre-web-automated`:

```yaml
    ports:
      - 8083:8083
      # Temporary: loopback redirect for the Gmail OAuth setup flow, can be removed once the token is stored
      - 8085:8085
```

then `docker compose -f books-docker-compose.yaml up -d calibre-web-automated`.

2. Patch the call inside the (recreated) container:

```sh
docker exec calibre-web-automated sed -i \
  's/creds = flow.run_local_server(port=0)/creds = flow.run_local_server(host="localhost", bind_addr="0.0.0.0", port=8085, open_browser=False)/' \
  /app/calibre-web-automated/cps/services/gmail.py
docker restart calibre-web-automated
```

Why these parameters:

- `open_browser=False` — print the login URL instead of opening a browser.
- `port=8085`, `bind_addr="0.0.0.0"` — listen on a known, published port on all interfaces so the host-forwarded redirect reaches it.
- `host="localhost"` stays as-is — it is used to build the redirect URI, and Google only accepts `localhost`/`127.0.0.1` loopback redirects for Desktop clients. (`bind_addr` controls binding separately; do **not** set `host="0.0.0.0"`.)

> The patch lives in the container layer: it survives `docker restart` but is lost on image pull / `up -d` recreate. That's fine — the token persists in `app.db`, so the patch is only needed until the flow completes once.

## Issue 3 — container unhealthy, whole UI frozen after clicking the button

### Symptom

`docker ps` shows `Up (unhealthy)`; every request to `:8083` times out; health check log shows `Health check exceeded timeout (3s)` repeating. No login URL anywhere in `docker logs`.

### Diagnostic

```sh
curl -s -o /dev/null -w "%{http_code}" -m 5 http://localhost:8083/   # -> 000, timeout
# 0x1F95 == 8085; state 0A == LISTEN
docker exec calibre-web-automated sh -c 'grep -i ":1F95" /proc/net/tcp | grep " 0A "'
```

Port 8085 listening inside the container = the OAuth flow was stuck waiting for a redirect. Two compounding problems:

1. **Calibre-web serves requests single-threaded**, so the blocking `run_local_server()` call froze the *entire* app (including the health check endpoint) until the flow completed — which it couldn't, because…
2. **The login URL never appeared in the logs.** Python block-buffers stdout when it isn't a TTY, so the `print()` of the URL sat in the buffer indefinitely.

### Fix

Insert a line-buffering line before the OAuth call (again inside the container), then restart to unfreeze:

```sh
docker exec calibre-web-automated sed -i \
  '/creds = flow.run_local_server(host="localhost"/i\            import sys; sys.stdout.reconfigure(line_buffering=True)' \
  /app/calibre-web-automated/cps/services/gmail.py
docker restart calibre-web-automated
```

## Completing the flow

1. Click **Setup Gmail Account**. The UI *will* freeze for everyone until the flow finishes — expected, one-time.
2. Get the login URL from the logs:

```sh
docker logs calibre-web-automated 2>&1 | grep -i "please visit"
```

3. Open the URL in a browser **on the server itself** (the redirect goes to `localhost:8085`). From another machine, tunnel first: `ssh -L 8085:localhost:8085 <server>`.
4. Google warns the app is unverified → Continue (you're a test user) → approve the `gmail.send` scope.
5. The redirect hits `localhost:8085`, the flow completes, the token is saved to `app.db`, and the UI unfreezes.

## Cleanup after success

- Remove the `8085:8085` port mapping from `books-docker-compose.yaml` and `up -d` (this also discards the container patches, which are no longer needed).
- Keep `gmail.json` in the config dir — it holds the client secret the refresh flow may need, and calibre-web's updater explicitly preserves it.
- If the token is ever revoked/wiped, the whole runbook applies again (patches included, since the recreate erased them).
