#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/versions.env"

DISTRO="${1:?Usage: build.sh <ubuntu: 20.04|22.04|24.04> <arch: x86_64>}"
ARCH="${2:?}"

BUILD=/tmp/venom-build
STAGE=/tmp/venom-stage
rm -rf "$BUILD" "$STAGE"
mkdir -p "$BUILD" "$STAGE"

VENOM_HOME="/home/venom"

# إعداد شجرة الوجهة داخل الحزمة
mkdir -p "$STAGE$VENOM_HOME" \
         "$STAGE$VENOM_HOME/bin" \
         "$STAGE$VENOM_HOME/php" \
         "$STAGE$VENOM_HOME/nginx" \
         "$STAGE$VENOM_HOME/redis" \
         "$STAGE$VENOM_HOME/www/public" \
         "$STAGE$VENOM_HOME/scripts"

# 1) جلب السورس
cd "$BUILD"
curl -fSLO "https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz"
curl -fSLO "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"
curl -fSLO "http://download.redis.io/releases/redis-${REDIS_VERSION}.tar.gz"

# 2) Build PHP (باختيارات أساسية كفاية)
tar -xzf "php-${PHP_VERSION}.tar.gz"
cd "php-${PHP_VERSION}"
./configure \
  --prefix="$VENOM_HOME/php" \
  --enable-fpm \
  --with-openssl \
  --with-zlib \
  --with-curl \
  --with-pdo-mysql \
  --with-mysqli \
  --enable-mbstring \
  --with-zip
make -j"$(nproc)"
make INSTALL_ROOT="$STAGE" install
mkdir -p "$STAGE$VENOM_HOME/php/etc"
cat > "$STAGE$VENOM_HOME/php/etc/php-fpm.conf" <<CFG
[global]
pid = $VENOM_HOME/php/var/run/php-fpm.pid
error_log = $VENOM_HOME/php/var/log/php-fpm.log
daemonize = yes
[www]
user = venom
group = venom
listen = 127.0.0.1:9070
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 5
CFG

# 3) Build Nginx
cd "$BUILD"
tar -xzf "nginx-${NGINX_VERSION}.tar.gz"
cd "nginx-${NGINX_VERSION}"
./configure \
  --prefix="$VENOM_HOME/nginx" \
  --with-http_ssl_module \
  --with-http_gzip_static_module \
  --with-pcre-jit
make -j"$(nproc)"
make DESTDIR="$STAGE" install
mkdir -p "$STAGE$VENOM_HOME/nginx/conf"
cat > "$STAGE$VENOM_HOME/nginx/conf/nginx.conf" <<'CFG'
worker_processes auto;
events { worker_connections 1024; }
http {
  include       mime.types;
  default_type  application/octet-stream;
  sendfile      on;
  keepalive_timeout 65;
  server {
    listen 8080;
    server_name _;
    root /home/venom/www/public;
    index index.php index.html;
    location / { try_files $uri $uri/ /index.php?$query_string; }
    location ~ \.php$ {
      include        fastcgi_params;
      fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
      fastcgi_pass   127.0.0.1:9070;
    }
  }
}
CFG

# 4) Build Redis
cd "$BUILD"
tar -xzf "redis-${REDIS_VERSION}.tar.gz"
cd "redis-${REDIS_VERSION}"
make -j"$(nproc)"
make PREFIX="$STAGE$VENOM_HOME/redis" install

# 5) صفحة فحص
cat > "$STAGE$VENOM_HOME/www/public/index.php" <<'PHP'
<?php
echo "VENOM runtime OK<br>";
echo "PHP: " . PHP_VERSION . "<br>";
echo "SAPI: " . php_sapi_name() . "<br>";
PHP

# 6) سكربتات الإدارة
cat > "$STAGE$VENOM_HOME/venom" <<'SH'
#!/usr/bin/env bash
set -e
CMD="${1:-help}"
VENOM_HOME="/home/venom"
php_start() { "$VENOM_HOME/php/sbin/php-fpm" -y "$VENOM_HOME/php/etc/php-fpm.conf"; }
php_stop()  { [ -f "$VENOM_HOME/php/var/run/php-fpm.pid" ] && kill -QUIT "$(cat "$VENOM_HOME/php/var/run/php-fpm.pid")" || true; }
nginx_start(){ "$VENOM_HOME/nginx/sbin/nginx" -p "$VENOM_HOME/nginx" -c "$VENOM_HOME/nginx/conf/nginx.conf"; }
nginx_stop() { "$VENOM_HOME/nginx/sbin/nginx" -s quit || true; }
status()     { pgrep -af php-fpm || true; pgrep -af nginx || true; }
case "$CMD" in
  start) php_start; nginx_start; echo "[✓] Started";;
  stop)  nginx_stop; php_stop; echo "[✓] Stopped";;
  restart) $0 stop; sleep 1; $0 start;;
  status) status;;
  *) echo "Usage: venom {start|stop|restart|status}"; exit 1;;
esac
SH
chmod +x "$STAGE$VENOM_HOME/venom"

cat > "$STAGE$VENOM_HOME/bin/venom-site" <<'SH'
#!/usr/bin/env bash
echo "venom-site placeholder (attach your project ops here)."
SH
chmod +x "$STAGE$VENOM_HOME/bin/venom-site"

# 7) إدراج postinstall داخل الحزمة
install -Dm755 "$ROOT/scripts/postinstall.sh" "$STAGE$VENOM_HOME/scripts/postinstall.sh"

# 8) تغليف + checksum
PKG="venom-runtime-ubuntu-${DISTRO}-${ARCH}-php${PHP_VERSION}-nginx${NGINX_VERSION}-redis${REDIS_VERSION}.tar.gz"
cd "$STAGE"
tar -czf "$PKG" .
sha256sum "$PKG" > "${PKG}.sha256"
mkdir -p "$ROOT/dist/${DISTRO}/${ARCH}"
mv "$PKG"* "$ROOT/dist/${DISTRO}/${ARCH}/"
echo "Built: dist/${DISTRO}/${ARCH}/${PKG}"
