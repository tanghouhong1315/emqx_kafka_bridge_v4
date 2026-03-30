# EMQX Kafka Bridge v4

EMQX Kafka 桥接插件 - 使用 Docker 多阶段构建

## 📋 项目结构

```
emqx_kafka_bridge_v4/
├── src/                    # Erlang 源代码
│   └── *.erl               # 插件实现
├── include/                # Erlang 头文件
│   └── emqx_kafka_bridge.hrl
├── etc/                    # 配置文件
│   ├── emqx_kafka_bridge.conf
│   └── forward_rules.json
├── priv/                   # 资源文件
│   └── emqx_kafka_bridge_v4.schema
├── rebar.config            # Erlang 构建配置
├── Dockerfile.build        # Docker 多阶段构建文件
├── build-linux.sh          # Linux 构建脚本
└── README.md               # 本文档
```

## 🚀 快速开始

### 前置条件

**构建服务器要求：**
- Linux (Ubuntu 20.04+ / CentOS 7+)
- Docker 20.10+ (支持 buildx)
- **不需要**在宿主机安装 Erlang/OTP（构建在容器内进行）
- 至少 4GB 内存
- 至少 10GB 磁盘空间

### 构建流程

#### 1. 复制项目到 Linux 服务器

```bash
# 在 Windows 上打包
cd D:\openclaw\workspace
tar -czf emqx_kafka_bridge_v4.tar.gz emqx_kafka_bridge_v4/

# 上传到 Linux 服务器
scp emqx_kafka_bridge_v4.tar.gz user@your-server:/home/user/

# 在 Linux 上解压
tar -xzf emqx_kafka_bridge_v4.tar.gz
cd emqx_kafka_bridge_v4
```

#### 2. 执行构建

```bash
# 赋予执行权限
chmod +x build-linux.sh

# 执行构建（自动检测架构）
./build-linux.sh

# 或指定架构
./build-linux.sh amd64   # x86_64
./build-linux.sh arm64   # ARM64
./build-linux.sh both    # 双架构
```

**构建时间：**
- 首次构建：20-40 分钟（拉取 builder 镜像 + 编译）
- 后续构建：5-10 分钟（使用 Docker 缓存）

#### 3. 构建产物

构建完成后会生成 Docker 镜像：

```bash
# 查看镜像
docker images | grep emqx_kafka_bridge_v4

# 示例输出
tanghouhong/emqx_kafka_bridge_v4   1.0.0-emqx4.4.19   xxxxx   2 hours ago
```

#### 4. 推送镜像（可选）

脚本会自动推送到 Docker Hub。

---

## 🐳 运行容器

### 基本运行

```bash
docker run -d --name emqx-kafka \
  -p 1883:1883 \
  -p 8083:8083 \
  -p 18083:18083 \
  tanghouhong/emqx_kafka_bridge_v4:1.0.0-emqx4.4.19
```

### 配置 Kafka 连接

```bash
docker run -d --name emqx-kafka \
  -p 1883:1883 \
  -p 18083:18083 \
  -e KAFKA_BOOTSTRAP_SERVERS=kafka:9092 \
  -v $(pwd)/etc/emqx_kafka_bridge.conf:/opt/emqx/etc/plugins/emqx_kafka_bridge.conf \
  tanghouhong/emqx_kafka_bridge_v4:1.0.0-emqx4.4.19
```

### Docker Compose

```yaml
version: '3.8'

services:
  emqx:
    image: tanghouhong/emqx_kafka_bridge_v4:1.0.0-emqx4.4.19
    ports:
      - "1883:1883"
      - "18083:18083"
    environment:
      - KAFKA_BOOTSTRAP_SERVERS=kafka:9092
    volumes:
      - ./etc/emqx_kafka_bridge.conf:/opt/emqx/etc/plugins/emqx_kafka_bridge.conf
    depends_on:
      - kafka

  kafka:
    image: confluentinc/cp-kafka:7.0.0
    ports:
      - "9092:9092"
    environment:
      - KAFKA_BROKER_ID=1
      - KAFKA_ZOOKEEPER_CONNECT=zookeeper:2181
      - KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://kafka:9092
      - KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1
    depends_on:
      - zookeeper

  zookeeper:
    image: confluentinc/cp-zookeeper:7.0.0
    ports:
      - "2181:2181"
    environment:
      - ZOOKEEPER_CLIENT_PORT=2181
```

---

## 🔧 配置说明

### 插件配置

编辑 `etc/emqx_kafka_bridge.conf`：

```ini
## Kafka 集群地址
kafka.bootstrap.servers = 127.0.0.1:9092

## 生产者配置
kafka.producer.required_acks = 1
kafka.producer.pool_size = 8
kafka.producer.batch_size = 100
kafka.producer.batch_timeout_ms = 50

## 主题配置
kafka.topic = emqx/messages
```

### 转发规则

编辑 `etc/forward_rules.json`：

```json
[
  {
    "topic": "sensor/+/temperature",
    "kafka_topic": "sensor-temperature",
    "partition": 0
  },
  {
    "topic": "device/+/status",
    "kafka_topic": "device-status",
    "partition_key": "device_id"
  }
]
```

---

## ✅ 验证插件

### 1. 检查插件状态

```bash
docker exec emqx-kafka emqx_ctl plugins list
```

输出示例：
```
Plugin(s) on the node:
[
  {emqx_kafka_bridge_v4,"1.0.0",true},
  {emqx_dashboard,"4.4.19",true},
  {emqx_management,"4.4.19",true}
]
```

### 2. 查看插件日志

```bash
docker logs emqx-kafka | grep kafka
```

### 3. 测试消息转发

```bash
# 发布 MQTT 消息
mosquitto_pub -t sensor/device1/temperature -m '{"temp": 25.5}'

# 查看 Kafka 主题
docker exec kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic sensor-temperature \
  --from-beginning
```

---

## 🧪 测试验证

### 自动化 API 测试

**Linux/macOS:**
```bash
chmod +x test-api.sh
bash test-api.sh localhost
```

**Windows PowerShell:**
```powershell
.\test-api.ps1 -EMQXHost localhost
```

### 测试覆盖

- ✅ 健康检查接口
- ✅ 规则 CRUD 操作（15 个测试用例）
- ✅ 分页/排序/模糊搜索
- ✅ 错误处理（400/404/409）

### 详细测试指南

参见 [TEST-VERIFICATION-GUIDE.md](./TEST-VERIFICATION-GUIDE.md)

包括：
- API 功能测试
- 持久化验证
- 端到端转发测试
- 缓存刷新验证
- 故障排查指南

---

## 🏗️ 多架构支持

### 构建双架构镜像

```bash
# 启用多架构支持
docker run --privileged --rm tonistiigi/binfmt --install all

# 构建双架构
./build-linux.sh both
```

### 架构兼容性

| 架构 | 平台 | 状态 |
|------|------|------|
| `amd64` | x86_64 服务器 | ✅ 支持 |
| `arm64` | Raspberry Pi 4, Apple M1, ARM 服务器 | ✅ 支持 |

---

## 📚 技术说明

### 编译环境

- **Builder 镜像**: `ghcr.io/emqx/emqx-builder/4.4-5:24.1.5-3-alpine3.14`
- **Erlang/OTP**: 24.1.5-3
- **EMQX**: 4.4.19
- **构建方式**: Docker 多阶段构建

### 运行环境

- **基础镜像**: Ubuntu 20.04
- **运行用户**: emqx (UID 1000)
- **协议**: MQTT 3.1/3.1.1/5.0

### 依赖项

```erlang
{deps, [
  {brod, "3.18.0"},          % Kafka 客户端
  {jiffy, "1.1.1"},          % JSON 解析
  {supervisor3, "1.1.12"}    % Supervisor 兼容
]}.
```

### 插件标识

插件已正确标识为 EMQX 插件：

```erlang
%% src/emqx_kafka_bridge_app.erl
-emqx_plugin(?MODULE).
```

---

## 🔍 故障排查

### 插件未加载

```bash
# 检查 loaded_plugins 文件
docker exec emqx-kafka cat /opt/emqx/data/loaded_plugins

# 手动加载插件
docker exec emqx-kafka emqx_ctl plugins load emqx_kafka_bridge_v4
```

### 构建失败

```bash
# 清理 Docker 缓存
docker system prune -a

# 重新构建
./build-linux.sh
```

### 查看构建日志

```bash
# 如果使用 Docker Desktop，可以在应用中查看
# 或使用详细输出
docker buildx build --progress=plain ...
```

---

## 📝 开发指南

### 本地开发

```bash
# 编译插件（不编译 EMQX）
cd emqx_kafka_bridge_v4
rebar3 get-deps
rebar3 compile

# 运行测试
rebar3 eunit
rebar3 ct
```

### 修改后重新构建

```bash
# 修改插件代码后
./build-linux.sh

# Docker 会缓存 builder 阶段，只重新编译插件
```

---

## 📄 许可证

Apache License 2.0

## 📞 支持

- GitHub Issues: [提交问题](https://github.com/your-repo/emqx_kafka_bridge_v4/issues)
- 文档：[EMQX 官方文档](https://docs.emqx.io/)

---

*最后更新：2026-03-19*
