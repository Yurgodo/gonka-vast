#!/bin/bash

set -eo pipefail

echo "🚀 Запуск Gonka Node..."
echo "📅 $(date)"

cd /opt/gonka/deploy/join

# Проверка наличия config.env
if [ ! -f "config.env" ]; then
    echo "⚠️  config.env не найден, копирую из шаблона..."
    cp config.env.template config.env || echo "❌ Ошибка: нет ни config.env, ни config.env.template"
fi

# Добавление переменных окружения, переданных контейнеру
if [ ! -z "$GONKA_OPERATIONAL_KEY" ]; then
    echo "ML_OPERATIONAL_KEY=$GONKA_OPERATIONAL_KEY" >> config.env
fi

if [ ! -z "$GONKA_HOST_NAME" ]; then
    sed -i "s/HOST_NAME=.*/HOST_NAME=$GONKA_HOST_NAME/" config.env || \
    echo "HOST_NAME=$GONKA_HOST_NAME" >> config.env
fi

echo ""
echo "📋 Конфигурация:"
cat config.env | grep -E "^[^#]" | head -5

echo ""
echo "🔍 Проверка GPU..."
if nvidia-smi &> /dev/null; then
    GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | wc -l)
    echo "✓ Доступно GPU: $GPU_COUNT"

    echo ""
    echo "🟢 Запуск Network Node + ML Node..."
    source config.env
    docker compose -f docker-compose.yml -f docker-compose.mlnode.yml up -d || true

else
    echo "⚠️  GPU не обнаружена"
    echo ""
    echo "🟡 Запуск только Network Node..."
    source config.env
    docker compose -f docker-compose.yml up -d || true
fi

echo ""
echo "✅ Gonka Node инициализирована"
echo ""
echo "📊 Логи:"
docker compose logs -f
