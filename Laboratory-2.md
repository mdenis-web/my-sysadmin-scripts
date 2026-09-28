# Лабораторная работа №2: Docker, Nginx, TLS, systemd, RAID, LVM

## Содержание
1. [Установка Docker](#1-установка-docker)
2. [Создание Dockerfile (Вариант В)](#2-создание-dockerfile-вариант-в)
3. [Сборка и запуск контейнера](#3-сборка-и-запуск-контейнера)
4. [Docker Compose](#4-docker-compose)
5. [RAID (программный массив)](#5-raid-программный-массив)
6. [LVM (Logical Volume Manager)](#6-lvm-logical-volume-manager)
7. [Добавление HTTP-сервера в Dockerfile](#7-добавление-http-сервера-в-dockerfile)
8. [Настройка Nginx как обратного прокси](#8-настройка-nginx-как-обратного-прокси)
9. [TLS (самоподписанный сертификат)](#9-tls-самоподписанный-сертификат)
10. [Превращение контейнера в systemd-службу](#10-превращение-контейнера-в-systemd-службу)
11. [Наблюдаемость (логи)](#11-наблюдаемость-логи)

---

## 1. Установка Docker

Docker установлен ранее по следующей схеме:

```bash
# Обновляем списки пакетов
sudo apt update

# Устанавливаем Docker и Docker Compose
sudo apt install -y docker.io docker-compose-v2

# Добавляем текущего пользователя в группу docker (запуск без sudo)
sudo usermod -aG docker $USER && newgrp docker
```

---

## 2. Создание Dockerfile (Вариант В)

Создаём файл `Dockerfile`:

```bash
> Dockerfile
nano Dockerfile
```

Содержимое Dockerfile:

```dockerfile
FROM ubuntu:22.04

COPY script.sh /usr/local/bin/script.sh
RUN chmod +x /usr/local/bin/script.sh

WORKDIR /root

ENTRYPOINT ["/usr/local/bin/script.sh"]
```

Сохраняем файл.

---

## 3. Сборка и запуск контейнера

```bash
# Собираем контейнер
docker build -t my-script .

# Запуск контейнера с аргументом
docker run --rm my-script ivan
```

---

## 4. Docker Compose

Создаём файл `docker-compose.yaml`:

```bash
> docker-compose.yaml
nano docker-compose.yaml
```

Содержимое:

```yaml
services:
  script:
    build: .
    image: my-script
    container_name: my-script-runner
    command: ["${USERNAME:-guest}"]
    volumes:
      - ./data:/root
```

Создаём файл `.env` для аргументов:

```bash
> .env
nano .env
```

Содержимое:

```
USERNAME=ivan
```

Запуск:

```bash
# Запуск с ivan из .env файла
docker compose up --build -d

# Разовый запуск с другим пользователем, минуя .env
USERNAME=anna docker compose up --build -d

# Просмотр контейнеров и логов
docker compose ps -a
docker compose logs

# Остановка и удаление контейнера
docker compose down
```

---

## 5. RAID (программный массив)

Устанавливаем утилиты:

```bash
sudo apt install -y mdadm lvm2
```

Создаём рабочий каталог и файлы дисков:

```bash
sudo mkdir -p /mnt/raid-lab && cd /mnt/raid-lab

sudo dd if=/dev/zero of=disk1.img bs=1M count=512
sudo dd if=/dev/zero of=disk2.img bs=1M count=512
sudo dd if=/dev/zero of=disk3.img bs=1M count=512
```

Превращаем файлы в блочные устройства (loop devices):

```bash
LOOP1=$(sudo losetup -fP --show disk1.img)
LOOP2=$(sudo losetup -fP --show disk2.img)
LOOP3=$(sudo losetup -fP --show disk3.img)

# Проверка
lsblk
```

Создаём RAID1-массив:

```bash
sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 "$LOOP1" "$LOOP2"
```

Создаём файловую систему и монтируем:

```bash
sudo mkfs.ext4 /dev/md0
sudo mkdir -p /mnt/raid && sudo mount /dev/md0 /mnt/raid
```

Проверка состояния:

```bash
cat /proc/mdstat
sudo mdadm --detail /dev/md0
```

---

## 6. LVM (Logical Volume Manager)

Создаём физический том (PV):

```bash
sudo pvcreate "$LOOP3"
```

Создаём группу томов (VG):

```bash
sudo vgcreate vg_data "$LOOP3"
```

Создаём логический том (LV):

```bash
sudo lvcreate -L 200M -n lv_logs vg_data
```

Файловая система и монтирование:

```bash
sudo mkfs.ext4 /dev/vg_data/lv_logs
sudo mkdir -p /mnt/logs && sudo mount /dev/vg_data/lv_logs /mnt/logs
```

Проверка:

```bash
df -h | grep -E "raid|logs"
```

Добавляем 100 МБ к LV:

```bash
sudo lvextend -L +100M /dev/vg_data/lv_logs
sudo resize2fs /dev/vg_data/lv_logs   # расширить ФС на ходу
```

Проверка:

```bash
df -h /mnt/logs   # объём вырос
```

---

## 7. Добавление HTTP-сервера в Dockerfile

Редактируем `Dockerfile`:

```bash
nano Dockerfile
```

Добавляем строки:

```dockerfile
# Обновляем пакеты и ставим Python 3
RUN apt-get update && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*

# Запускаем скрипт с аргументом (demo-user), а затем запускаем веб-сервер
CMD ["/bin/bash", "-c", "/usr/local/bin/script.sh demo-user && exec python3 -m http.server 8080"]

# Удаляем ENTRYPOINT
```

Собираем образ и запускаем контейнер:

```bash
docker build -t my-script .
docker run -d -p 8080:8080 --name my-app -v /var/log:/var/log:ro my-script
```

Проверяем:

```bash
docker ps
curl http://127.0.0.1:8080/
curl http://127.0.0.1:8080/setup.log
```

---

## 8. Настройка Nginx как обратного прокси

Устанавливаем Nginx и удаляем дефолтный конфиг:

```bash
sudo apt install -y nginx
sudo rm -f /etc/nginx/sites-enabled/default
```

Создаём конфиг для приложения:

```bash
sudo tee /etc/nginx/sites-available/my-app << 'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:8080;
    }
}
EOF
```

Активируем конфиг и перезагружаем Nginx:

```bash
sudo ln -sf /etc/nginx/sites-available/my-app /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

Тест:

```bash
curl http://127.0.0.1:8080/ | head -5
curl http://127.0.0.1/ | head -5
# Ожидаемо: одинаковый результат
```

---

## 9. TLS (самоподписанный сертификат)

Генерируем самоподписанный сертификат:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/my-app.key \
  -out /etc/ssl/certs/my-app.crt \
  -subj "/CN=my-app.local"
```

Редактируем конфиг Nginx (перенаправление с HTTP на HTTPS, коды 301):

```bash
sudo tee /etc/nginx/sites-available/my-app <<'EOF'
server {
    listen 80;
    server_name _;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name _;

    ssl_certificate     /etc/ssl/certs/my-app.crt;
    ssl_certificate_key /etc/ssl/private/my-app.key;

    location / {
        proxy_pass http://127.0.0.1:8080;
    }
}
EOF
```

Применяем и проверяем:

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -kI https://127.0.0.1/
```

---

## 10. Превращение контейнера в systemd-службу

Удаляем старый контейнер:

```bash
docker rm -f my-app
```

Создаём файл службы systemd:

```bash
sudo tee /etc/systemd/system/my-app.service <<'EOF'
[Unit]
Description=my-app service
After=docker.service
Requires=docker.service

[Service]
ExecStart=docker start -a my-app
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
```

Создаём контейнер:

```bash
docker create -p 8080:8080 --name my-app -v /var/log:/var/log:ro my-script
```

Активируем и запускаем службу:

```bash
sudo systemctl daemon-reload
sudo systemctl enable my-app
sudo systemctl start my-app
sleep 3
sudo systemctl status my-app
```

Финальная проверка:

```bash
curl -kI https://127.0.0.1/   # ОК
```

---

## 11. Наблюдаемость (логи)

Включаем вывод логов приложения (первое окно):

```bash
sudo journalctl -u my-app -f
```

Включаем вывод логов Nginx (второе окно):

```bash
sudo tail -f /var/log/nginx/access.log
```

В третьем окне делаем запрос:

```bash
curl -kI https://127.0.0.1/
```

В обоих окнах видим запросы.
```
