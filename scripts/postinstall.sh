#!/usr/bin/env bash
set -euo pipefail
VENOM_HOME="/home/venom"

# مستخدم نظامي بدون شيل (إن لم يوجد)
if ! id -u venom >/dev/null 2>&1; then
  useradd -r -s /usr/sbin/nologin venom || true
fi

mkdir -p "$VENOM_HOME"
chown -R venom:venom "$VENOM_HOME"

# روابط الأوامر
ln -sf "$VENOM_HOME/venom"          /usr/local/bin/venom
ln -sf "$VENOM_HOME/bin/venom-site" /usr/local/bin/venom-site

echo "[postinstall] Done."
