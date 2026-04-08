#!/bin/bash
set -e

# === PERMISSION FIX ===
# Everything runs as 'node' user (UID 1000) — the default user in node:22-bookworm.
# No custom users, no UID mismatches, no gosu complexity.

# Create dirs and fix ownership on the persistent volume
mkdir -p /data/.openclaw /data/workspace /data/.gogcli
chown -R node:node /data/.openclaw /data/workspace /data/.gogcli
chown node:node /data
chmod 755 /data /data/.openclaw /data/workspace /data/.gogcli

# Linuxbrew persistence — copy from image to volume on first run
if [ ! -d /data/.linuxbrew ]; then
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
  chown -R node:node /data/.linuxbrew
fi
rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

# === GOG CLI SETUP ===
if [ -n "$GOG_CLIENT_ID" ] && [ -n "$GOG_REFRESH_TOKEN" ]; then
  GOG_DATA_DIR="/data/.gogcli"

  cat > "$GOG_DATA_DIR/credentials.json" <<GOGCREDS
{
  "client_id": "$GOG_CLIENT_ID",
  "client_secret": "$GOG_CLIENT_SECRET"
}
GOGCREDS

  cat > "$GOG_DATA_DIR/config.json" <<GOGCONF
{
  "keyring_backend": "file"
}
GOGCONF

  chown -R node:node "$GOG_DATA_DIR"

  # Symlink gog config to node user's home
  mkdir -p /home/node/.config
  rm -rf /home/node/.config/gogcli
  ln -sfn "$GOG_DATA_DIR" /home/node/.config/gogcli

  # Import refresh token if not already present
  export GOG_KEYRING_PASSWORD="${GOG_KEYRING_PASSWORD:-openclaw}"
  if ! su -s /bin/bash node -c "gog auth list" 2>/dev/null | grep -q "${GOG_ACCOUNT:-watson@drinkaltawater.com}"; then
    TMPTOKEN=$(mktemp /tmp/gog-token-XXXXXX.json)
    cat > "$TMPTOKEN" <<GOGTOKEN
{
  "email": "${GOG_ACCOUNT:-watson@drinkaltawater.com}",
  "client": "default",
  "services": ["calendar", "gmail"],
  "scopes": [
    "email",
    "https://www.googleapis.com/auth/business.manage",
    "https://www.googleapis.com/auth/calendar",
    "https://www.googleapis.com/auth/gmail.modify",
    "https://www.googleapis.com/auth/gmail.settings.basic",
    "https://www.googleapis.com/auth/gmail.settings.sharing",
    "https://www.googleapis.com/auth/userinfo.email",
    "openid"
  ],
  "created_at": "2026-04-07T16:51:20Z",
  "refresh_token": "$GOG_REFRESH_TOKEN"
}
GOGTOKEN
    chown node:node "$TMPTOKEN"
    su -s /bin/bash node -c "GOG_KEYRING_PASSWORD='$GOG_KEYRING_PASSWORD' gog auth tokens import '$TMPTOKEN'" \
      && echo "[gog] Token imported" || echo "[gog] Token import FAILED" >&2
    rm -f "$TMPTOKEN"
  fi
fi

# === START SERVER AS NODE USER ===
exec gosu node node src/server.js
