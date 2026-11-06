#!/bin/bash
# pulsewatchFallback: nginx fallback для Xray + сайт PulseWatch (Python stdlib, systemd).
# Повторный запуск = обновление файлов.

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/unnk2004/pulsewatchFallback/main}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
FILES="index.html 404.html privacy.html terms.html style.css app.js favicon.svg robots.txt"

echo -e "${GREEN}=== Nginx fallback для Xray + PulseWatch ===${NC}\n"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Скрипт должен запускаться с правами root${NC}"; exit 1
fi

MISSING=()
for c in nginx python3 curl; do command -v $c &> /dev/null || MISSING+=($c); done
if [ ${#MISSING[@]} -gt 0 ]; then
    echo -e "${YELLOW}Устанавливаем: ${MISSING[*]}${NC}"
    apt-get update -qq && apt-get install -y "${MISSING[@]}" || { echo -e "${RED}Не удалось установить пакеты${NC}"; exit 1; }
fi
PYTHON="$(command -v python3)"

DOMAIN="${DOMAIN:-}"
if [ -z "$DOMAIN" ]; then
    echo -e "${YELLOW}Введите домен (например, de.skynets.uk):${NC}"
    read -p "Домен: " DOMAIN
fi
[ -z "$DOMAIN" ] && { echo -e "${RED}Домен не может быть пустым${NC}"; exit 1; }

CERT_DIR="${CERT_DIR:-/root/cert/$DOMAIN}"
WEBROOT="${WEBROOT:-/var/www/pulsewatch}"
NGINX_PORT="${NGINX_PORT:-8443}"
API_PORT="${API_PORT:-8081}"
APP_DIR="/opt/pulsewatch"

echo -e "\n${YELLOW}Параметры установки:${NC}"
echo -e " Домен:         ${GREEN}$DOMAIN${NC}"
echo -e " Сертификаты:   ${GREEN}$CERT_DIR${NC}"
echo -e " Webroot:       ${GREEN}$WEBROOT${NC}"
echo -e " Nginx порт:    ${GREEN}$NGINX_PORT${NC}"
echo -e " Бэкенд (loc.): ${GREEN}127.0.0.1:$API_PORT${NC}\n"

if [ "$YES" != "1" ]; then
    read -p "Продолжить установку? (y/n): " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo -e "${RED}Установка отменена${NC}"; exit 0; }
fi

if [ ! -f "$CERT_DIR/fullchain.pem" ] || [ ! -f "$CERT_DIR/privkey.pem" ]; then
    echo -e "${RED}Сертификаты не найдены в $CERT_DIR${NC}"; exit 1
fi

fetch() {
    if [ -f "$SRC/$1" ]; then install -m 644 "$SRC/$1" "$2"
    else curl -fsSL "$REPO_RAW/$1" -o "$2" && chmod 644 "$2" || { echo -e "${RED}Не удалось скачать $1${NC}"; exit 1; }
    fi
}

echo -e "${YELLOW}Установка сайта и бэкенда...${NC}"
mkdir -p "$WEBROOT" "$APP_DIR"
for f in $FILES; do fetch "web/$f" "$WEBROOT/$f"; done
fetch server/server.py "$APP_DIR/server.py"

cat > /etc/systemd/system/pulsewatch.service << EOF
[Unit]
Description=PulseWatch API
After=network.target

[Service]
ExecStart=$PYTHON $APP_DIR/server.py
Environment=PULSE_PORT=$API_PORT
DynamicUser=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pulsewatch > /dev/null 2>&1
systemctl restart pulsewatch
sleep 1
systemctl is-active --quiet pulsewatch || { echo -e "${RED}Бэкенд не запустился: journalctl -u pulsewatch -n 30${NC}"; exit 1; }
echo -e "${GREEN}Бэкенд запущен${NC}\n"

echo -e "${YELLOW}Настройка Nginx...${NC}"
cat > /etc/nginx/sites-available/pulsewatch-fallback << EOF
server {
    listen 80;
    listen [::]:80;
    server_name _;
    return 301 https://\$host\$request_uri;
}

server {
    listen 127.0.0.1:$NGINX_PORT ssl http2;
    server_name _;
    server_tokens off;

    ssl_certificate $CERT_DIR/fullchain.pem;
    ssl_certificate_key $CERT_DIR/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    root $WEBROOT;
    index index.html;
    charset utf-8;
    error_page 404 /404.html;

    location / {
        try_files \$uri \$uri.html \$uri/ =404;
    }

    location = /404.html {
        internal;
    }

    location ^~ /api/ {
        proxy_pass http://127.0.0.1:$API_PORT;
        proxy_set_header Host \$host;
        client_max_body_size 2k;
    }

    location ~* \.(css|js|svg)\$ {
        expires 1h;
    }

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; base-uri 'none'; frame-ancestors 'self'" always;

    access_log off;
    error_log /var/log/nginx/pulsewatch-error.log warn;
}
EOF

# Старый сайт на этом же порту (nginxFallback) отключаем, иначе два server{} на одном адресе
rm -f /etc/nginx/sites-enabled/xray-fallback /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/pulsewatch-fallback /etc/nginx/sites-enabled/

if nginx -t; then
    systemctl enable nginx > /dev/null 2>&1
    systemctl restart nginx
    echo -e "\n${GREEN}Настройка завершена успешно!${NC}\n"
    echo -e "📍 Nginx:   ${GREEN}127.0.0.1:$NGINX_PORT${NC} (HTTPS), порт 80 → HTTPS"
    echo -e "📍 Сайт:    ${GREEN}$WEBROOT${NC}"
    echo -e "📍 Бэкенд:  ${GREEN}pulsewatch.service${NC} (ничего не хранит и не логирует)"
    if systemctl list-unit-files skynet-sync.service 2>/dev/null | grep -q skynet-sync; then
        echo -e "${YELLOW}Остался старый сервис skynet-sync, он больше не нужен:${NC} systemctl disable --now skynet-sync"
    fi
    echo -e "\n${YELLOW}Xray fallback:${NC}  ${GREEN}\"fallbacks\": [{ \"dest\": $NGINX_PORT }]${NC}"
    echo -e "${GREEN}Проверка:${NC} curl -I https://$DOMAIN"
else
    echo -e "${RED}Ошибка в конфигурации Nginx${NC}"; exit 1
fi
