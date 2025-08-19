#!/usr/bin/env bash
set -euo pipefail

ORG="VenomDRMSolutions"
REPO="venom-runtime-prebuilt"

# اكتشاف التوزيعة والمعمارية
source /etc/os-release
DISTRO="${VERSION_ID}"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH="x86_64" ;;
  aarch64|arm64) ARCH="aarch64" ;; # فعّلها لاحقًا في CI
  *) echo "Unsupported arch: $ARCH"; exit 1 ;;
esac

# إمكانية تمرير إصدارات مختلفة أثناء التشغيل
PHP_VERSION="${PHP_VERSION:-8.4.1}"
NGINX_VERSION="${NGINX_VERSION:-1.26.2}"
REDIS_VERSION="${REDIS_VERSION:-7.4.1}"

PKG="venom-runtime-ubuntu-${DISTRO}-${ARCH}-php${PHP_VERSION}-nginx${NGINX_VERSION}-redis${REDIS_VERSION}.tar.gz"
BASE="https://github.com/${ORG}/${REPO}/releases/latest/download"

TMP="/tmp/venom-runtime"
sudo rm -rf "$TMP" && mkdir -p "$TMP"
cd "$TMP"

echo "[*] Downloading $PKG ..."
curl -fSLo "$PKG" "${BASE}/${PKG}"
curl -fSLo "${PKG}.sha256" "${BASE}/${PKG}.sha256"

echo "[*] Verifying checksum ..."
sha256sum -c "${PKG}.sha256"

echo "[*] Extracting to / ..."
sudo tar -xzf "$PKG" -C /

# postinstall (مضمنة داخل الحزمة)
if [ -x /home/venom/scripts/postinstall.sh ]; then
  sudo bash /home/venom/scripts/postinstall.sh
else
  echo "[!] postinstall script not found!"
fi

echo
echo "[✓] Installed."
echo "Try: sudo venom start && venom status"
