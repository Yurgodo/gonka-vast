#!/bin/bash

# Выключить на ошибке
set -eo pipefail

# Логирование
echo "=== Gonka Node Setup для Vast.ai ===" | tee /tmp/gonka-setup.log

# Обновление системы
sudo apt update && sudo apt upgrade -y
sudo apt install -y git wget curl jq python3 python3-pip

# Установка Docker (если не установлен)
if ! command -v docker &> /dev/null; then
    echo "Установка Docker..."
    sudo apt install -y docker.io docker-compose
    sudo usermod -aG docker root
else
    echo "Docker уже установлен"
fi

# Проверка NVIDIA Container Runtime
if ! command -v nvidia-smi &> /dev/null; then
    echo "⚠️  NVIDIA GPU не обнаружена. Установка NVIDIA Container Runtime..."
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
    curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
        sudo tee /etc/apt/sources.list.d/nvidia-docker.list
    sudo apt update && sudo apt install -y nvidia-container-runtime
    sudo systemctl restart docker
fi

# Клонирование Gonka репозитория
cd /tmp
if [ -d "gonka" ]; then
    rm -rf gonka
fi

echo "Клонирование Gonka репозитория..."
git clone https://github.com/gonka-ai/gonka.git -b main
cd gonka/deploy/join

# Копирование шаблона конфигурации
cp config.env.template config.env

# Переменные окружения (должны быть переданы из vast.ai шаблона)
ACCOUNT_KEY="${GONKA_ACCOUNT_KEY:-}"
OPERATIONAL_KEY="${GONKA_OPERATIONAL_KEY:-}"
HOST_NAME="${GONKA_HOST_NAME:-gonka-node-$(hostname -s)}"

# Если ключи не переданы, создавать новые (ТОЛЬКО для ML-only ноды)
if [ -z "$ACCOUNT_KEY" ]; then
    echo "⚠️  Account Key не переданы. Используется режим ML-only node."
    # ML-only ноды не нуждаются в Account Key локально
fi

# Обновление config.env с переменными среды
if [ ! -z "$OPERATIONAL_KEY" ]; then
    echo "ML_OPERATIONAL_KEY=$OPERATIONAL_KEY" >> config.env
fi

echo "HOST_NAME=$HOST_NAME" >> config.env

# Установка прав на файлы
chmod +x /tmp/gonka/deploy/join/config.env

# Проверка конфигурации
echo "=== Проверка конфигурации ==="
cat config.env | grep -E "^[^#]" | head -10

echo "✓ Gonka Node Setup завершена успешно!"
echo "Инстанс готов для развертывания контейнеров Gonka"
