#!/bin/bash
# 快速启动 EMQX Kafka Bridge 容器

CONTAINER_NAME="emqx-kafka"
IMAGE_NAME="tanghouhong/emqx_kafka_bridge_v4:1.0.0-emqx4.4.19"
KAFKA_SERVERS="${KAFKA_BOOTSTRAP_SERVERS:-192.168.19.71:10003}"

# 如果容器已存在，先删除
docker stop $CONTAINER_NAME 2>/dev/null || true
docker rm $CONTAINER_NAME 2>/dev/null || true

# 启动容器
docker run -d --name $CONTAINER_NAME \
  -p 1883:1883 \
  -p 18083:18083 \
  -p 8090:8090 \
  -e KAFKA_BOOTSTRAP_SERVERS=$KAFKA_SERVERS \
  $IMAGE_NAME

echo "✅ EMQX Kafka Bridge 已启动"
echo "📊 Dashboard: http://localhost:18083 (admin/public)"
echo "📝 日志：docker logs -f $CONTAINER_NAME"
