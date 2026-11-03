#!/usr/bin/env bash
# Установка Монополии на чистый Ubuntu (Aeza и любой другой VPS).
# Запуск:  bash install-vps.sh ваш-домен.ru      (домен должен уже вести на IP сервера)
#     или: bash install-vps.sh                   (без домена: игра на http://IP)
set -e
DOMAIN="$1"
DIR=/opt/monopoly
if [ "$(id -u)" != "0" ]; then echo "Запустите от root"; exit 1; fi
if [ ! -f "$DIR/server.js" ]; then echo "Не найден $DIR/server.js — сначала загрузите игру в $DIR (через WinSCP)"; exit 1; fi

echo "== 1/4 Установка Node.js и Caddy =="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl ca-certificates gnupg debian-keyring debian-archive-keyring apt-transport-https ufw
if ! command -v node >/dev/null || [ "$(node -v | cut -d. -f1 | tr -d v)" -lt 18 ]; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
if ! command -v caddy >/dev/null; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -y
  apt-get install -y caddy
fi

echo "== 2/4 Установка зависимостей игры =="
cd "$DIR"
npm install --omit=dev

echo "== 3/4 Автозапуск игры =="
cat > /etc/systemd/system/monopoly.service <<UNIT
[Unit]
Description=Monopoly
After=network.target

[Service]
WorkingDirectory=$DIR
Environment=MONOPOLY_SUPERVISED=1
Environment=PORT=3000
ExecStart=$(command -v node) server.js
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now monopoly
systemctl restart monopoly

echo "== 4/4 Адрес сайта и защита =="
if [ -n "$DOMAIN" ]; then
  printf '%s {\n    reverse_proxy localhost:3000\n}\n' "$DOMAIN" > /etc/caddy/Caddyfile
else
  printf ':80 {\n    reverse_proxy localhost:3000\n}\n' > /etc/caddy/Caddyfile
fi
systemctl enable caddy
systemctl restart caddy
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null

sleep 2
echo
if systemctl is-active --quiet monopoly; then echo "ГОТОВО. Игра запущена."; else echo "Игра не запустилась. Смотрите: journalctl -u monopoly -n 30"; fi
if [ -n "$DOMAIN" ]; then echo "Ссылка для игроков: https://$DOMAIN  (сертификат может выдаваться до минуты)"; else echo "Ссылка для игроков: http://$(curl -s ifconfig.me)"; fi
echo "Обновления: кладите update-*.js в $DIR/updates/"
