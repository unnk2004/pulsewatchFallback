# pulsewatchFallback

Nginx fallback для Xray (VLESS+TLS) с сайтом **PulseWatch** (мониторинг аптайма).
Стек: nginx + один Python-файл (только стандартная библиотека) + systemd. Базы нет, ничего не хранится и не логируется.

## Структура

```
pulsewatchFallback/
├── setup.sh
├── web/       index.html, 404.html, privacy.html, terms.html, style.css, app.js, favicon.svg, robots.txt
├── server/    server.py
└── README.md
```

## Быстрый старт

```
bash <(curl -fsSL https://raw.githubusercontent.com/unnk2004/pulsewatchFallback/main/setup.sh)
```

Сертификаты ожидаются в `/root/cert/<домен>/fullchain.pem` и `privkey.pem`. Повторный запуск обновляет файлы.
Старый сайт nginxFallback на том же порту скрипт отключает (иначе два `server{}` на одном адресе).

## Xray

```
"fallbacks": [{ "dest": 8443 }]
```

## Как работает сайт

- `GET /api/status`: аптайм за 90 дней, дней без инцидентов и «probes connected» (суточная кривая с небольшим шумом). Числа детерминированы по времени, поэтому у всех посетителей одинаковые и плавно меняются. Реальных данных сервера и Xray они не показывают.
- `POST /api/subscribe`: проверяет email, ждёт 0.4–1 с и отвечает «ок». Письмо не отправляется, адрес нигде не сохраняется.
- Есть собственная страница 404, `/privacy`, `/terms`, `robots.txt`, favicon, CSP и кеш статики.

## Переменные окружения

| Переменная   | По умолчанию               | Описание                     |
|--------------|----------------------------|------------------------------|
| `DOMAIN`     | спрашивает                 | Домен                        |
| `YES`        | нет                        | `1` пропускает подтверждение |
| `CERT_DIR`   | `/root/cert/<домен>`       | Каталог с сертификатами      |
| `WEBROOT`    | `/var/www/pulsewatch`      | Каталог сайта                |
| `NGINX_PORT` | `8443`                     | Порт nginx для fallback      |
| `API_PORT`   | `8081`                     | Локальный порт бэкенда       |
| `REPO_RAW`   | raw.githubusercontent.com… | Откуда скачивать файлы       |

Обслуживание: `journalctl -u pulsewatch -n 50`, `systemctl restart pulsewatch`.
