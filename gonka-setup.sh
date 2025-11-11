#!/bin/bash
set -eo pipefail

# ============================================================================
# Gonka Node Setup для Vast.ai
# Этот скрипт автоматически:
# 1. Устанавливает Docker и зависимости
# 2. Конфигурирует NVIDIA Container Runtime
# 3. Клонирует репозиторий Gonka
# 4. Подготавливает конфигурацию
# ============================================================================

LOG_FILE="/tmp/gonka-setup.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "╔════════════════════════════════════════════════════════╗"
echo "║     Gonka AI Node Setup для Vast.ai                    ║"
echo "║     $(date)                      ║"
echo "╚════════════════════════════════════════════════════════╝"

# Проверка root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Этот скрипт должен запускаться с правами root (sudo)"
    exit 1
fi

# Проверка переменных окружения
echo ""
echo "📋 Проверка переменных окружения..."
echo "   GONKA_HOST_NAME: ${GONKA_HOST_NAME:-not-set}"
echo "   GONKA_OPERATIONAL_KEY: ${GONKA_OPERATIONAL_KEY:0:16}..."
echo "   NVIDIA_VISIBLE_DEVICES: ${NVIDIA_VISIBLE_DEVICES:-all}"

# ============================================================================
# 1. Обновление системы
# ============================================================================
echo ""
echo "📦 Обновление системы..."
apt-get update > /dev/null 2>&1 || true
apt-get upgrade -y > /dev/null 2>&1 || true
apt-get install -y curl wget git jq python3 python3-pip ubuntu-drivers-common > /dev/null 2>&1

echo "✓ Система обновлена"

# ============================================================================
# 2. Установка Docker (если не установлен)
# ============================================================================
echo ""
echo "🐳 Проверка Docker..."

if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version)
    echo "✓ Docker уже установлен: $DOCKER_VERSION"
else
    echo "   Установка Docker..."
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release > /dev/null 2>&1

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg > /dev/null 2>&1

    echo \
      "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update > /dev/null 2>&1
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin > /dev/null 2>&1

    # Docker Compose (Legacy)
    apt-get install -y docker-compose > /dev/null 2>&1 || \
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    systemctl start docker
    systemctl enable docker

    echo "✓ Docker установлен и запущен"
fi

# ============================================================================
# 3. NVIDIA Container Toolkit
# ============================================================================
echo ""
echo "🔧 Проверка NVIDIA Container Toolkit..."

if command -v nvidia-smi &> /dev/null; then
    GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | wc -l)
    echo "✓ NVIDIA GPU обнаружен(а): $GPU_COUNT GPU(s)"

    if ! docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu22.04 nvidia-smi &> /dev/null 2>&1; then
        echo "   Установка NVIDIA Container Runtime..."

        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
        curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add - > /dev/null 2>&1
        curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
            tee /etc/apt/sources.list.d/nvidia-docker.list > /dev/null

        apt-get update > /dev/null 2>&1
        apt-get install -y nvidia-container-runtime > /dev/null 2>&1

        systemctl restart docker

        echo "✓ NVIDIA Container Runtime установлен"
    else
        echo "✓ NVIDIA Container Runtime уже настроен"
    fi
else
    echo "⚠️  GPU не обнаружена - нода будет работать в режиме Network Node только"
fi

# ============================================================================
# 4. Клонирование Gonka репозитория
# ============================================================================
echo ""
echo "📥 Клонирование Gonka репозитория..."

GONKA_DIR="/opt/gonka"
if [ -d "$GONKA_DIR" ]; then
    rm -rf "$GONKA_DIR"
fi

mkdir -p "$GONKA_DIR"
cd /tmp

git clone https://github.com/gonka-ai/gonka.git -b main \
    > /dev/null 2>&1 && echo "✓ Репозиторий клонирован" || {
    echo "❌ Ошибка при клонировании репозитория"
    exit 1
}

mv gonka "$GONKA_DIR"

# ============================================================================
# 5. Подготовка конфигурации
# ============================================================================
echo ""
echo "⚙️  Подготовка конфигурации Gonka..."

cd "$GONKA_DIR/deploy/join"

# Копирование шаблона
if [ -f "config.env.template" ]; then
    cp config.env.template config.env
    echo "✓ config.env создан из шаблона"
else
    # Создание базовой конфигурации, если шаблон отсутствует
    cat > config.env << 'EOF'
# Gonka Network Configuration
# Автогенерирован скриптом provisioning

# Network Node
NETWORK_HOST=0.0.0.0
NETWORK_PORT=5000

# Tendermint
TENDERMINT_RPC_HOST=0.0.0.0
TENDERMINT_RPC_PORT=26657

# ML Node (опционально)
ML_NODE_ENABLED=true
ML_NODE_PORT=5001

EOF
    echo "✓ Базовая конфигурация создана"
fi

# Добавление переменных из vast.ai
{
    echo ""
    echo "# Auto-configured by Vast.ai Provisioning Script"
    echo "HOST_NAME=${GONKA_HOST_NAME:-vastai-gonka-$(hostname -s)}"

    if [ ! -z "$GONKA_OPERATIONAL_KEY" ]; then
        echo "ML_OPERATIONAL_KEY=${GONKA_OPERATIONAL_KEY}"
    fi

    echo "NVIDIA_VISIBLE_DEVICES=${NVIDIA_VISIBLE_DEVICES:-all}"
    echo "PROVISIONED_AT=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
} >> config.env

echo "✓ Конфигурация обновлена"

# ============================================================================
# 6. Тестирование Docker
# ============================================================================
echo ""
echo "🧪 Тестирование Docker..."

docker run --rm hello-world > /dev/null 2>&1 && echo "✓ Docker работает корректно" || {
    echo "❌ Docker тест не пройден"
    exit 1
}

# ============================================================================
# 7. Финальные шаги
# ============================================================================
echo ""
echo "📝 Сохранение информации об окружении..."

cat > /tmp/gonka-info.txt << EOF
╔════════════════════════════════════════════════════════╗
║              Gonka Node Setup Complete                 ║
╚════════════════════════════════════════════════════════╝

📍 Установка: $GONKA_DIR
📅 Время: $(date)

🔧 Компоненты:
   ✓ Docker: $(docker --version)
   ✓ Docker Compose: $(docker-compose --version)
   ✓ NVIDIA Container Runtime: $(docker run --rm --gpus all alpine nvidia-smi > /dev/null 2>&1 && echo "Установлен" || echo "Не установлен")

🖥️  Система:
   CPU: $(nproc) cores
   RAM: $(free -h | awk 'NR==2 {print $2}')
   GPU: $(nvidia-smi --query-gpu=count --format=csv,noheader 2>/dev/null | head -1 || echo "N/A")

📋 Конфигурация:
   HOST_NAME: ${GONKA_HOST_NAME}
   ML_NODE: $([ ! -z "$GONKA_OPERATIONAL_KEY" ] && echo "Enabled" || echo "Disabled")

📖 Следующие шаги:
   1. Проверьте конфигурацию: cat $GONKA_DIR/deploy/join/config.env
   2. Запустите ноду: cd $GONKA_DIR/deploy/join && docker compose up -d
   3. Проверьте логи: docker compose logs -f

📚 Документация:
   GitHub: https://github.com/gonka-ai/gonka
   Quickstart: https://docs.gonka.ai/quickstart

═══════════════════════════════════════════════════════════

Setup логи сохранены в: $LOG_FILE

EOF

cat /tmp/gonka-info.txt

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║  ✅ Setup успешно завершен!                           ║"
echo "║                                                        ║"
echo "║  Инстанс готов для развертывания Gonka Node          ║"
echo "╚════════════════════════════════════════════════════════╝"

exit 0
