#!/bin/bash
USERNAME="$1"

if [ -z "$USERNAME" ]; then
    read -p "Имя пользователя не указано. Введите имя: " USERNAME
fi

if [ -z "$USERNAME" ]; then
    echo "Имя не введено. Завершение." >&2
    exit 1
fi

TARGET_DIR="$HOME/managed-users/$USERNAME"

if [ -d "$TARGET_DIR" ]; then
    echo "Добро пожаловать $USERNAME, Ваш каталог был создан ранее."
    echo "$(date): Попытка создания дубликата пользователя $USERNAME" >> setup.log
    exit 0
fi

mkdir -p "$TARGET_DIR"
echo "# настройки $USERNAME" > "$TARGET_DIR/.bashrc"
echo "Добро пожаловать, $USERNAME!"
echo "$(date): создан пользовательский каталог для $USERNAME" >> setup.log
