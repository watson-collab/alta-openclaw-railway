#!/bin/bash
set -e

chown -R openclaw:openclaw /data
chmod 700 /data

if [ ! -d /data/.linuxbrew ]; then
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
fi

rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

# Configure gog CLI if credentials are provided via env vars
if [ -n "$GOG_CLIENT_ID" ] && [ -n "$GOG_REFRESH_TOKEN" ]; then
  GOG_HOME="/home/openclaw"
  GOG_CONFIG_DIR="$GOG_HOME/.config/gogcli"
  mkdir -p "$GOG_CONFIG_DIR"

  # Write OAuth client credentials
  cat > "$GOG_CONFIG_DIR/credentials.json" <<GOGCREDS
{
  "client_id": "$GOG_CLIENT_ID",
  "client_secret": "$GOG_CLIENT_SECRET"
}
GOGCREDS

  # Set file-based keyring (no system keychain in container)
  cat > "$GOG_CONFIG_DIR/config.json" <<GOGCONF
{
  "keyring_backend": "file"
}
GOGCONF

  # Fix ownership BEFORE import so openclaw user can write to the keyring
  chown -R openclaw:openclaw "$GOG_HOME/.config"

  # Import refresh token if not already present
  if ! gosu openclaw gog auth list 2>/dev/null | grep -q "${GOG_ACCOUNT:-watson@drinkaltawater.com}"; then
    TMPTOKEN=$(mktemp /tmp/gog-token-XXXXXX.json)
    cat > "$TMPTOKEN" <<GOGTOKEN
{
  "email": "${GOG_ACCOUNT:-watson@drinkaltawater.com}",
  "client": "default",
  "services": ["calendar", "gmail"],
  "scopes": [
    "email",
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
    chown openclaw:openclaw "$TMPTOKEN"
    gosu openclaw gog auth tokens import "$TMPTOKEN" 2>&1 && echo "[gog] Token imported for $GOG_ACCOUNT" || echo "[gog] Token import failed — check logs above"
    rm -f "$TMPTOKEN"
  else
    echo "[gog] Account $GOG_ACCOUNT already configured"
  fi
fi

exec gosu openclaw node src/server.js
