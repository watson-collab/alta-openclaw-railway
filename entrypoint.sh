#!/bin/bash
set -e

# Resolve the openclaw user UID — fall back to 1001 if user doesn't exist
OC_UID=$(id -u openclaw 2>/dev/null || echo 1001)
OC_GID=$(id -g openclaw 2>/dev/null || echo 1001)

# Ensure openclaw user exists (create if missing)
if ! id openclaw &>/dev/null; then
  useradd -u 1001 -m -s /bin/bash openclaw 2>/dev/null || true
  OC_UID=1001
  OC_GID=1001
fi

# Create required directories on the persistent volume
mkdir -p /data/.openclaw /data/workspace /data/.gogcli
# Only chown the dirs we care about — NOT the huge .linuxbrew tree
chown -R "$OC_UID:$OC_GID" /data/.openclaw /data/workspace /data/.gogcli
chown "$OC_UID:$OC_GID" /data
chmod 755 /data

# Linuxbrew persistence
if [ ! -d /data/.linuxbrew ]; then
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
  chown -R "$OC_UID:$OC_GID" /data/.linuxbrew
fi

rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

# Configure gog CLI if credentials are provided via env vars
if [ -n "$GOG_CLIENT_ID" ] && [ -n "$GOG_REFRESH_TOKEN" ]; then
  GOG_DATA_DIR="/data/.gogcli"

  # Write OAuth client credentials
  cat > "$GOG_DATA_DIR/credentials.json" <<GOGCREDS
{
  "client_id": "$GOG_CLIENT_ID",
  "client_secret": "$GOG_CLIENT_SECRET"
}
GOGCREDS

  # Set file-based keyring (no system keychain in container)
  cat > "$GOG_DATA_DIR/config.json" <<GOGCONF
{
  "keyring_backend": "file"
}
GOGCONF

  chown -R "$OC_UID:$OC_GID" "$GOG_DATA_DIR"

  # Symlink gog config for all possible home dirs
  for UHOME in /home/openclaw /home/node /root; do
    if [ -d "$UHOME" ]; then
      mkdir -p "$UHOME/.config"
      rm -rf "$UHOME/.config/gogcli"
      ln -sfn "$GOG_DATA_DIR" "$UHOME/.config/gogcli"
    fi
  done

  # Import refresh token if not already present
  export GOG_KEYRING_PASSWORD="${GOG_KEYRING_PASSWORD:-openclaw}"
  if ! gosu openclaw gog auth list 2>/dev/null | grep -q "${GOG_ACCOUNT:-watson@drinkaltawater.com}"; then
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
    chown "$OC_UID:$OC_GID" "$TMPTOKEN"
    gosu openclaw gog auth tokens import "$TMPTOKEN" && echo "[gog] Token imported for $GOG_ACCOUNT" || echo "[gog] Token import FAILED" >&2
    rm -f "$TMPTOKEN"
  fi
fi

exec gosu openclaw node src/server.js
