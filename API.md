# EMQX Kafka Bridge v4 - HTTP API 文档

## 基础信息

- **端口**: 8090（可在 `etc/emqx_kafka_bridge.conf` 中配置）
- **协议**: HTTP/1.1
- **格式**: JSON
- **框架**: Cowboy（EMQX 4.x）

---

## API 端点

### 1. 规则列表查询

**接口**: `GET /kafka_bridge/rules`

**功能**: 查询规则列表，支持分页、排序、模糊匹配

**查询参数**:

| 参数 | 类型 | 必需 | 默认值 | 说明 |
|------|------|------|--------|------|
| topic | string | 否 | - | MQTT 主题关键字（模糊匹配） |
| page | integer | 否 | 1 | 页码 |
| limit | integer | 否 | 10 | 每页数量 |
| sort_by | string | 否 | created_at | 排序字段：`created_at`, `mqtt_topic`, `name` |
| sort_order | string | 否 | desc | 排序方向：`asc`, `desc` |

**请求示例**:
```bash
# 查询所有规则
curl "http://localhost:8090/kafka_bridge/rules"

# 分页查询
curl "http://localhost:8090/kafka_bridge/rules?page=1&limit=20"

# 模糊搜索 sensor 相关的规则
curl "http://localhost:8090/kafka_bridge/rules?topic=sensor"

# 按 mqtt_topic 升序排序
curl "http://localhost:8090/kafka_bridge/rules?sort_by=mqtt_topic&sort_order=asc"
```

**响应示例**:
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "total": 5,
    "page": 1,
    "limit": 10,
    "rules": [
      {
        "id": "12345678-1234-1234-1234-123456789abc",
        "name": "传感器数据转发",
        "mqtt_topic": "sensor/+/data",
        "kafka_topic": "sensor_data",
        "qos": null,
        "payload_format": "json",
        "kafka_key": "client_id",
        "enabled": true,
        "description": "转发传感器数据到 Kafka",
        "created_at": 1773984766,
        "updated_at": 1773984766
      }
    ]
  }
}
```

---

### 2. 单个规则详情查询

**接口**: `GET /kafka_bridge/rule/get`

**功能**: 根据 MQTT 主题查询单个规则详情

**查询参数**:

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| topic | string | 是 | MQTT 主题 |

**请求示例**:
```bash
curl "http://localhost:8090/kafka_bridge/rule/get?topic=sensor/+/data"
```

**响应示例**:
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "id": "12345678-1234-1234-1234-123456789abc",
    "name": "传感器数据转发",
    "mqtt_topic": "sensor/+/data",
    "kafka_topic": "sensor_data",
    "qos": null,
    "payload_format": "json",
    "kafka_key": "client_id",
    "enabled": true,
    "description": "转发传感器数据到 Kafka",
    "created_at": 1773984766,
    "updated_at": 1773984766
  }
}
```

**错误响应 (404)**:
```json
{
  "code": 404,
  "message": "Rule not found"
}
```

---

### 3. 新增规则

**接口**: `POST /kafka_bridge/rule/add`

**功能**: 创建新的转发规则

**请求头**:
```
Content-Type: application/json
```

**请求体字段**:

| 字段 | 类型 | 必需 | 默认值 | 说明 |
|------|------|------|--------|------|
| mqtt_topic | string | 是 | - | MQTT 主题（支持通配符 `+` 和 `#`） |
| kafka_topic | string | 是 | - | Kafka 主题 |
| name | string | 否 | - | 规则名称 |
| qos | integer | 否 | null | QoS 级别（0, 1, 2 或 null） |
| payload_format | string | 否 | json | 消息格式：`json`, `raw`, `template` |
| kafka_key | string | 否 | topic | Kafka Key 策略：`topic`, `client_id`, `username`, `none` |
| enabled | boolean | 否 | true | 是否启用 |
| description | string | 否 | - | 规则描述 |

**请求示例**:
```bash
curl -X POST "http://localhost:8090/kafka_bridge/rule/add" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "传感器数据转发",
    "mqtt_topic": "sensor/+/data",
    "kafka_topic": "sensor_data",
    "payload_format": "json",
    "kafka_key": "client_id",
    "enabled": true,
    "description": "转发所有传感器数据到 Kafka"
  }'
```

**响应示例 (201 Created)**:
```json
{
  "code": 0,
  "message": "created",
  "data": {
    "id": "12345678-1234-1234-1234-123456789abc",
    "name": "传感器数据转发",
    "mqtt_topic": "sensor/+/data",
    "kafka_topic": "sensor_data",
    "enabled": true,
    "created_at": 1773984766,
    "updated_at": 1773984766
  }
}
```

**错误响应**:
- `400` - 参数错误（缺少必需字段或 JSON 格式错误）
- `409` - 规则已存在
- `500` - 服务器错误

---

### 4. 修改规则

**接口**: `POST /kafka_bridge/rule/update`

**功能**: 更新现有规则

**请求头**:
```
Content-Type: application/json
```

**请求体字段**:

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| mqtt_topic | string | 是 | MQTT 主题（用于查找规则） |
| kafka_topic | string | 是 | 新的 Kafka 主题 |
| name | string | 否 | 规则名称 |
| enabled | boolean | 否 | 是否启用 |
| description | string | 否 | 规则描述 |

**请求示例**:
```bash
curl -X POST "http://localhost:8090/kafka_bridge/rule/update" \
  -H "Content-Type: application/json" \
  -d '{
    "mqtt_topic": "sensor/+/data",
    "kafka_topic": "sensor_data_v2",
    "enabled": false,
    "description": "已更新的传感器数据转发规则"
  }'
```

**响应示例 (200 OK)**:
```json
{
  "code": 0,
  "message": "updated",
  "data": {
    "id": "12345678-1234-1234-1234-123456789abc",
    "name": "传感器数据转发",
    "mqtt_topic": "sensor/+/data",
    "kafka_topic": "sensor_data_v2",
    "enabled": false,
    "created_at": 1773984766,
    "updated_at": 1773984800
  }
}
```

**错误响应**:
- `400` - 参数错误
- `404` - 规则不存在
- `500` - 服务器错误

---

### 5. 删除规则

**接口**: `POST /kafka_bridge/rule/delete`

**功能**: 删除指定的转发规则

**请求头**:
```
Content-Type: application/json
```

**请求体字段**:

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| mqtt_topic | string | 是 | MQTT 主题 |

**请求示例**:
```bash
curl -X POST "http://localhost:8090/kafka_bridge/rule/delete" \
  -H "Content-Type: application/json" \
  -d '{
    "mqtt_topic": "sensor/+/data"
  }'
```

**响应示例 (200 OK)**:
```json
{
  "code": 0,
  "message": "deleted"
}
```

**错误响应**:
- `400` - 参数错误（缺少 mqtt_topic）
- `404` - 规则不存在
- `500` - 服务器错误

---

### 6. 健康检查

**接口**: `GET /kafka_bridge/health`

**功能**: 检查服务健康状态

**请求示例**:
```bash
curl "http://localhost:8090/kafka_bridge/health"
```

**响应示例**:
```json
{
  "code": 0,
  "message": "healthy",
  "data": {
    "status": "running",
    "timestamp": 1773984766437
  }
}
```

---

## 使用示例

### 完整工作流

```bash
# 1. 查询规则列表（初始为空）
curl "http://localhost:8090/kafka_bridge/rules"

# 2. 创建规则
curl -X POST "http://localhost:8090/kafka_bridge/rule/add" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "测试规则",
    "mqtt_topic": "test/#",
    "kafka_topic": "test_messages",
    "enabled": true
  }'

# 3. 查询规则列表（现在有 1 条规则）
curl "http://localhost:8090/kafka_bridge/rules"

# 4. 查询规则详情
curl "http://localhost:8090/kafka_bridge/rule/get?topic=test/#"

# 5. 更新规则
curl -X POST "http://localhost:8090/kafka_bridge/rule/update" \
  -H "Content-Type: application/json" \
  -d '{
    "mqtt_topic": "test/#",
    "kafka_topic": "test_messages_v2",
    "enabled": false
  }'

# 6. 删除规则
curl -X POST "http://localhost:8090/kafka_bridge/rule/delete" \
  -H "Content-Type: application/json" \
  -d '{"mqtt_topic": "test/#"}'

# 7. 验证删除
curl "http://localhost:8090/kafka_bridge/rules"
```

---

## 持久化说明

### 规则存储

- **主存储**: Mnesia 表（`disc_copies` 磁盘存储）
- **备份文件**: `/opt/emqx/data/kafka_bridge_rules.json`
- **初始规则**: `etc/forward_rules.json`（首次启动时加载）

### 加载顺序

1. EMQX 启动时检查 Mnesia 表是否有规则
2. 如果有规则，直接使用（跳过加载）
3. 如果无规则，尝试从 `/opt/emqx/data/kafka_bridge_rules.json` 加载
4. 如果持久化文件不存在，从 `etc/forward_rules.json` 加载初始规则
5. 加载成功后自动保存到持久化文件

### 保存机制

- 每次创建、更新、删除规则时自动保存到持久化文件
- EMQX 重启后优先从持久化文件加载

---

## 错误码说明

| 错误码 | 说明 |
|--------|------|
| 0 | 成功 |
| 400 | 请求参数错误 |
| 404 | 资源不存在 |
| 405 | 方法不允许 |
| 409 | 资源冲突（如规则已存在） |
| 500 | 服务器内部错误 |

---

## 响应格式

所有 API 响应统一格式：

```json
{
  "code": 0,
  "message": "success",
  "data": { ... }
}
```

- `code`: 错误码（0 表示成功）
- `message`: 响应消息
- `data`: 响应数据（成功时）或错误详情（失败时）
