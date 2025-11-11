# Multi-stage build для оптимизации размера образа

FROM nvidia/cuda:12.6.0-devel-ubuntu22.04 as builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl wget ca-certificates build-essential \
    && rm -rf /var/lib/apt/lists/*

# Промежуточный слой для клонирования репозитория
RUN git clone --depth 1 https://github.com/gonka-ai/gonka.git -b main /tmp/gonka

# ============================================================================

FROM nvidia/cuda:12.6.0-runtime-ubuntu22.04

LABEL maintainer="Gonka AI"
LABEL description="Gonka AI Node for Vast.ai"

# Установка необходимых пакетов
RUN apt-get update && apt-get install -y --no-install-recommends \
    docker.io \
    docker-compose \
    git \
    curl \
    wget \
    jq \
    python3 \
    python3-pip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# NVIDIA Container Runtime
RUN distribution=$(. /etc/os-release;echo $ID$VERSION_ID) && \
    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add - && \
    curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
    tee /etc/apt/sources.list.d/nvidia-docker.list && \
    apt-get update && apt-get install -y nvidia-container-runtime

# Копирование Gonka из builder
COPY --from=builder /tmp/gonka /opt/gonka

WORKDIR /opt/gonka/deploy/join

# Копирование entrypoint скрипта
COPY entrypoint.sh /
RUN chmod +x /entrypoint.sh

# Expose ports
EXPOSE 5000 26657 8000

# Environment variables
ENV GONKA_HOME=/opt/gonka
ENV PROVISIONED_AT=""
ENV NVIDIA_VISIBLE_DEVICES=all

ENTRYPOINT ["/entrypoint.sh"]
