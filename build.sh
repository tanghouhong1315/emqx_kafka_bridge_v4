#!/bin/bash
set -e

IMAGE_NAME="tanghouhong/emqx_kafka_bridge_v4:1.0.1-emqx4.4.19"
KAFKA_SERVERS="${KAFKA_BOOTSTRAP_SERVERS:-192.168.19.71:10003}"

# 默认参数
PLATFORM="${PLATFORM:-linux/amd64}"
PUSH="${PUSH:-false}"
NO_CACHE="${NO_CACHE:-false}"
PULL="${PULL:-false}"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
  case $1 in
    --platform)
      PLATFORM="$2"
      shift 2
      ;;
    --push)
      PUSH="true"
      shift
      ;;
    --no-cache)
      NO_CACHE="true"
      shift
      ;;
    --pull)
      PULL="true"
      shift
      ;;
    --help)
      echo "用法：$0 [选项]"
      echo ""
      echo "选项:"
      echo "  --platform <平台>    构建平台 (默认：linux/amd64)"
      echo "                       多架构：linux/amd64,linux/arm64"
      echo "  --push               构建后推送到 Docker Hub"
      echo "  --no-cache           不使用缓存"
      echo "  --pull               自动拉取最新基础镜像"
      echo "  --help               显示帮助"
      exit 0
      ;;
    *)
      echo "未知选项：$1"
      echo "使用 --help 查看用法"
      exit 1
      ;;
  esac
done

echo "=========================================="
echo "  EMQX Kafka Bridge v4 - 构建脚本"
echo "=========================================="
echo "平台：$PLATFORM"
echo "推送：$PUSH"
echo "无缓存：$NO_CACHE"
echo "=========================================="
echo ""

# 构建参数
BUILD_ARGS="--platform $PLATFORM -t $IMAGE_NAME -f Dockerfile.build --cache-from=ghcr.nju.edu.cn/emqx/emqx-builder/4.4-5:24.1.5-3-alpine3.14"

if [ "$NO_CACHE" = "true" ]; then
  BUILD_ARGS="$BUILD_ARGS --no-cache"
  echo "[提示] 使用 --no-cache 参数，将不使用任何缓存"
  echo ""
fi

if [ "$PULL" = "true" ]; then
  BUILD_ARGS="$BUILD_ARGS --pull"
  echo "[提示] 使用 --pull 参数，自动拉取最新基础镜像"
  echo ""
fi

if [ "$PUSH" = "true" ]; then
  BUILD_ARGS="$BUILD_ARGS --push"
  echo "[提示] 构建完成后将推送到 Docker Hub"
  echo ""
else
  BUILD_ARGS="$BUILD_ARGS --load"
  echo "[提示] 构建完成后镜像将保存到本地"
  echo ""
fi

# 1. 构建镜像
echo "[1/2] 构建镜像..."
echo "    镜像名称：$IMAGE_NAME"
echo "    平台：$PLATFORM"
echo ""

if docker buildx build $BUILD_ARGS .; then
  echo ""
  echo "    ✓ 镜像构建成功"
else
  echo ""
  echo "    ✗ 镜像构建失败"
  echo ""
  echo "💡 提示：如果构建失败，可以尝试清理缓存后重试"
  echo "   docker buildx prune -f"
  echo "   或者使用 --no-cache 参数"
  echo "   ./build.sh --no-cache"
  exit 1
fi
echo ""

# 2. 显示后续操作提示
echo "[2/2] 后续操作提示"
echo "=========================================="
echo ""

if [ "$PUSH" = "false" ]; then
  echo "✅ 镜像已构建完成！"
  echo ""
  echo "📦 镜像信息:"
  echo "   名称：$IMAGE_NAME"
  echo "   平台：$PLATFORM"
  echo ""
  echo "🚀 启动容器:"
  echo ""
  echo "   docker run -d --name emqx-kafka \\"
  echo "     -p 1883:1883 \\"
  echo "     -p 18083:18083 \\"
  echo "     -p 8090:8090 \\"
  echo "     -v emqx-data:/opt/emqx/data \\"
  echo "     -e KAFKA_BOOTSTRAP_SERVERS=$KAFKA_SERVERS \\"
  echo "     $IMAGE_NAME"
  echo ""
  echo "📊 查看日志:"
  echo ""
  echo "   docker logs -f emqx-kafka"
  echo ""
  echo "📝 测试 API:"
  echo ""
  echo "   # 健康检查"
  echo "   curl http://localhost:8090/kafka_bridge/health"
  echo ""
  echo "   # 创建规则"
  echo "   curl -X POST http://localhost:8090/kafka_bridge/rule/add \\"
  echo "     -H 'Content-Type: application/json' \\"
  echo "     -d '{\"mqtt_topic\":\"test/#\",\"kafka_topic\":\"test_data\"}'"
  echo ""
  echo "   # 查询规则列表"
  echo "   curl http://localhost:8090/kafka_bridge/rules"
  echo ""
  echo "💾 持久化说明:"
  echo ""
  echo "   数据已挂载到 emqx-data 卷，容器重启后数据不丢失"
  echo "   查看卷位置：docker volume inspect emqx-data"
  echo ""
  echo "🛑 停止容器:"
  echo ""
  echo "   docker stop emqx-kafka"
  echo "   docker rm emqx-kafka"
  echo ""
else
  echo "✅ 镜像已构建并推送到 Docker Hub！"
  echo ""
  echo "📦 镜像信息:"
  echo "   名称：$IMAGE_NAME"
  echo "   平台：$PLATFORM"
  echo ""
  echo "🔗 Docker Hub 链接:"
  echo "   https://hub.docker.com/r/tanghouhong/emqx_kafka_bridge_v4"
  echo ""
  echo "🚀 在其他机器上拉取并运行:"
  echo ""
  echo "   docker pull $IMAGE_NAME"
  echo "   docker run -d --name emqx-kafka \\"
  echo "     -p 1883:1883 \\"
  echo "     -p 18083:18083 \\"
  echo "     -p 8090:8090 \\"
  echo "     -v emqx-data:/opt/emqx/data \\"
  echo "     -e KAFKA_BOOTSTRAP_SERVERS=$KAFKA_SERVERS \\"
  echo "     $IMAGE_NAME"
  echo ""
fi

echo "=========================================="
echo "  构建完成！"
echo "=========================================="
