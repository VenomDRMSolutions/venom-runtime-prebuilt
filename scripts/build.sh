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

# شجرة الوجهة (مطابقة للاسكربت الرئيسي)
mkdir -p "$STAGE$VENOM_HOME"/{bin,php,nginx,redis,www/public,scripts,conf/sites-available,conf/sites-enabled,conf/ssl,logs,tmp}

# 1) المصادر
cd "$BUILD"
curl -fSLO "https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz"
curl -fSLO "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"
curl -fSLO "http://download.redis.io/releases/redis-${REDIS_VERSION}.tar.gz"

# 2) PHP (مع config-file-path و socket)
tar -xzf "php-${PHP_VERSION}.tar.gz"
cd "php-${PHP_VERSION}"
./configure \
  --prefix="$VENOM_HOME/php" \
  --with-config-file-path="$VENOM_HOME/conf" \
  --enable-fpm \
  --with-fpm-user=venom \
  --with-fpm-group=venom \
  --with-openssl --with-zlib --with-curl \
  --with-pdo-mysql --with-mysqli \
  --enable-mbstring --enable-opcache --with-zip
make -j"$(nproc)"
make INSTALL_ROOT="$STAGE" install

cat > "$STAGE$VENOM_HOME/conf/php-fpm.conf" <<'CFG'
[global]
pid = /home/venom/tmp/php-fpm.pid
error_log = /home/venom/logs/php-fpm.log
daemonize = yes
[www]
user = venom
group = venom
listen = /home/venom/tmp/php-fpm.sock
listen.owner = venom
listen.group = venom
listen.mode = 0660
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 5
CFG
# php.ini مبدئي
cat > "$STAGE$VENOM_HOME/conf/php.ini" <<'INI'
date.timezone = UTC
error_log = /home/venom/logs/php_errors.log
upload_max_filesize = 100M
post_max_size = 100M
memory_limit = 512M
max_execution_time = 300
INI

# 3) Nginx (conf تحت /home/venom/conf + pcre-jit)
cd "$BUILD"
tar -xzf "nginx-${NGINX_VERSION}.tar.gz"
cd "nginx-${NGINX_VERSION}"
./configure \
  --prefix="$VENOM_HOME/nginx" \
  --conf-path="$VENOM_HOME/conf/nginx.conf" \
  --with-http_ssl_module \
  --with-http_gzip_static_module \
  --with-pcre-jit
make -j"$(nproc)"
make DESTDIR="$STAGE" install

# fastcgi_params و nginx.conf + موقع افتراضي
cat > "$STAGE$VENOM_HOME/conf/fastcgi_params" <<'FCGI'
fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
include        mime.types;
FCGI

cat > "$STAGE$VENOM_HOME/conf/nginx.conf" <<'NGX'
user  venom;
worker_processes auto;
events { worker_connections 1024; }
http {
  include       /home/venom/conf/mime.types;
  default_type  application/octet-stream;
  sendfile on; keepalive_timeout 65;
  include /home/venom/conf/sites-enabled/*.conf;
}
NGX

cat > "$STAGE$VENOM_HOME/conf/mime.types" <<'MIME'
types { text/html html; application/javascript js; text/css css; image/png png; image/jpeg jpg jpeg; }
MIME

cat > "$STAGE$VENOM_HOME/conf/sites-available/default.conf" <<'SITE'
server {
  listen 8080;
  server_name _;
  root /home/venom/www/public;
  index index.php index.html;
  location / { try_files $uri $uri/ /index.php?$query_string; }
  location ~ \.php$ {
    include        /home/venom/conf/fastcgi_params;
    fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
    fastcgi_pass   unix:/home/venom/tmp/php-fpm.sock;
  }
}
SITE
ln -sf ../sites-available/default.conf "$STAGE$VENOM_HOME/conf/sites-enabled/default.conf"

# 4) Redis
cd "$BUILD"
tar -xzf "redis-${REDIS_VERSION}.tar.gz"
cd "redis-${REDIS_VERSION}"
make -j"$(nproc)"
make PREFIX="$STAGE$VENOM_HOME/redis" install

# 5) index.php بسيط
cat > "$STAGE$VENOM_HOME/www/public/index.php" <<'PHP'
<?php echo "VENOM runtime OK<br>PHP: ".PHP_VERSION."<br>SAPI: ".php_sapi_name()."<br>";
PHP

# 6) أوامر الإدارة (تقرأ من conf الموحد)
cat > "$STAGE$VENOM_HOME/venom" <<'SH'
#!/usr/bin/env bash
set -e
VENOM_HOME="/home/venom"
CMD="${1:-help}"
php_start() { "$VENOM_HOME/php/sbin/php-fpm" -y "$VENOM_HOME/conf/php-fpm.conf"; }
php_stop()  { [ -f "$VENOM_HOME/tmp/php-fpm.pid" ] && kill -QUIT "$(cat "$VENOM_HOME/tmp/php-fpm.pid")" || true; }
nginx_start(){ "$VENOM_HOME/nginx/sbin/nginx" -c "$VENOM_HOME/conf/nginx.conf"; }
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

# 7) postinstall داخل الباكدج
install -Dm755 "$ROOT/scripts/postinstall.sh" "$STAGE$VENOM_HOME/scripts/postinstall.sh"

# 8) تغليف + checksum
PKG="venom-runtime-ubuntu-${DISTRO}-${ARCH}-php${PHP_VERSION}-nginx${NGINX_VERSION}-redis${REDIS_VERSION}.tar.gz"
cd "$STAGE"; tar -czf "$PKG" .; sha256sum "$PKG" > "${PKG}.sha256"
mkdir -p "$ROOT/dist/${DISTRO}/${ARCH}"; mv "$PKG"* "$ROOT/dist/${DISTRO}/${ARCH}/"
echo "Built: dist/${DISTRO}/${ARCH}/${PKG}"
