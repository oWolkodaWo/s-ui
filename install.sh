#!/bin/bash

# Цвета для вывода в консоль
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Накатываем кастомный S-UI + Nginx + Заглушка ===${NC}"

# 1. Проверка прав root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Ошибка: Запустите скрипт от имени root (sudo -i)${NC}"
  exit 1
fi

# 2. Сбор данных от пользователя
read -p "Введите ваш домен (например, vpn.domain.com): " DOMAIN
read -p "Введите ваш Email для SSL (например, admin@domain.com): " EMAIL
PANEL_PORT=2095 # Дефолтный порт S-UI

# 3. Обновление системы и установка зависимостей
echo -e "${GREEN}[1/5] Установка зависимостей (Nginx, curl, socat)...${NC}"
apt update && apt install -y curl wget nginx socat unzip tar git

# 4. Выпуск SSL сертификата через acme.sh
echo -e "${GREEN}[2/5] Выпуск SSL сертификата Let's Encrypt...${NC}"
systemctl stop nginx # Временно тушим Nginx для проверки портов

curl https://get.acme.sh | sh -s email=$EMAIL
~/.acme.sh/acme.sh --upgrade --auto-upgrade
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh --issue -d $DOMAIN --standalone --keylength ec-256

# Создаем папку под сертификаты
mkdir -p /etc/s-ui/certs/
~/.acme.sh/acme.sh --install-cert -d $DOMAIN --ecc \
  --key-file /etc/s-ui/certs/private.key \
  --fullchain-file /etc/s-ui/certs/cert.crt

# 5. Установка официальной панели S-UI (alireza0)
echo -e "${GREEN}[3/5] Скачивание и установка панели S-UI...${NC}"
bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh) <<EOF
y
EOF

# 6. Скачивание сайта-заглушки
echo -e "${GREEN}[4/5] Установка сайта-заглушки...${NC}"
mkdir -p /var/www/html
rm -rf /var/www/html/*
# Качаем простую HTML-игру
wget -O /var/www/html/web.zip https://github.com/banyasw/vless-html/raw/main/templates/game.zip
unzip -o /var/www/html/web.zip -d /var/www/html/
rm -f /var/www/html/web.zip

# 7. Настройка Nginx в качестве реверс-прокси
echo -e "${GREEN}[5/5] Конфигурация Nginx...${NC}"
cat > /etc/nginx/sites-available/s-ui.conf <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/s-ui/certs/cert.crt;
    ssl_certificate_key /etc/s-ui/certs/private.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    # Главная страница - наша заглушка
    location / {
        root /var/www/html;
        index index.html;
    }

    # Проксирование панели S-UI (вход в админку)
    location /panel/ {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:$PANEL_PORT/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

# Активируем конфиг и перезапускаем Nginx
ln -sf /etc/nginx/sites-available/s-ui.conf /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl daemon-reload
systemctl restart nginx

echo -e "${GREEN}===============================================${NC}"
echo -e "${GREEN}Установка завершена успешно!${NC}"
echo -e "Сайт-заглушка: https://$DOMAIN"
echo -e "Ваша панель S-UI доступна по адресу: https://$DOMAIN/panel/"
echo -e "${GREEN}===============================================${NC}"
