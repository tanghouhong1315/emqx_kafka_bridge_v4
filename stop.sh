#!/bin/bash
# 停止 EMQX Kafka Bridge 容器

CONTAINER_NAME="emqx-kafka"

docker stop $CONTAINER_NAME 2>/dev/null || true
docker rm $CONTAINER_NAME 2>/dev/null || true

echo "✅ 容器已停止"
