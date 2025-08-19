#!/usr/bin/env bash
set -euo pipefail
VENOM_HOME="/home/venom"
id -u venom >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin venom
install -d "$VENOM_HOME" "$VENOM_HOME"/{logs,tmp}
chown -R venom:venom "$VENOM_HOME"
ln -sf "$VENOM_HOME/venom" /usr/local/bin/venom
ln -sf "$VENOM_HOME/bin/venom-site" /usr/local/bin/venom-site
echo "[postinstall] Done."
