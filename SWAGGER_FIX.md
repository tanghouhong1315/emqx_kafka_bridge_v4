# Swagger UI 修复说明

## 问题描述

访问 `http://192.168.18.78:8090/kafka_bridge/docs` 时，Swagger UI 的 **Servers** 下拉框显示的是 `http://localhost:8090/kafka_bridge`，导致 API 请求发送到错误的地址。

## 根本原因

`swagger.json` 文件中硬编码了 `servers` 字段：
```json
"servers": [
  {
    "url": "http://localhost:8090/kafka_bridge",
    "description": "本地开发环境"
  }
]
```

这导致无论从哪个 IP 地址访问，Swagger UI 始终使用 `localhost` 作为 API 服务器地址。

## 解决方案

修改了 `src/emqx_kafka_bridge_api.erl` 中的 `swagger_ui/2` 函数：

**核心思路**：在 HTML 中嵌入 swagger.json 内容后，使用 JavaScript 动态替换 `servers` 字段为当前浏览器访问的地址。

```erlang
swagger_ui(_Bindings, _Params) ->
    JsonBin = swagger_json(),
    JsonStr = binary_to_list(JsonBin),
    Html = io_lib:format(
        <<"...
        let spec = ~s;
        
        // 动态替换 servers 为当前访问地址
        spec.servers = [{
            url: currentUrl,
            description: \"当前访问地址\"
        }];
        
        SwaggerUIBundle({
            spec: spec,
            ...
        });
        ...">>,
        [JsonStr]),
    ...
```

**效果**：
- 从 `http://192.168.18.78:8090/kafka_bridge/docs` 访问 → Servers 显示 `http://192.168.18.78:8090/kafka_bridge`
- 从 `http://localhost:8090/kafka_bridge/docs` 访问 → Servers 显示 `http://localhost:8090/kafka_bridge`
- 从 `http://10.0.0.100:8090/kafka_bridge/docs` 访问 → Servers 显示 `http://10.0.0.100:8090/kafka_bridge`

## 重新构建和部署

### 1. 在 Linux 构建服务器上

```bash
# 进入项目目录
cd /path/to/emqx_kafka_bridge_v4

# 重新构建 Docker 镜像
./build-linux.sh

# 等待构建完成（约 5-10 分钟，使用缓存）
```

### 2. 推送镜像到 Docker Hub（如果需要）

```bash
docker push tanghouhong/emqx_kafka_bridge_v4:1.0.0-emqx4.4.19
```

### 3. 在目标服务器上部署

```bash
# 停止旧容器
docker stop emqx-kafka
docker rm emqx-kafka

# 拉取新镜像
docker pull tanghouhong/emqx_kafka_bridge_v4:1.0.0-emqx4.4.19

# 启动新容器
docker run -d --name emqx-kafka \
  -p 1883:1883 \
  -p 8090:8090 \
  -p 18083:18083 \
  tanghouhong/emqx_kafka_bridge_v4:1.0.0-emqx4.4.19
```

### 4. 验证修复

访问 Swagger UI：
```
http://192.168.18.78:8090/kafka_bridge/docs
```

现在应该能正常显示 API 文档了！

## 验证检查清单

- [ ] Swagger UI 页面正常加载
- [ ] **Servers 下拉框显示当前访问的 IP 地址**（如 `http://192.168.18.78:8090/kafka_bridge`）
- [ ] 显示所有 API 端点（health, rules, rule/get, rule/add, rule/update, rule/delete）
- [ ] 点击 "Try it out" → "Execute" 能正确发送请求到当前服务器
- [ ] Request URL 显示的是当前访问的地址（不是 localhost）

## 技术细节

### 修改的文件

- `src/emqx_kafka_bridge_api.erl` - `swagger_ui/2` 函数

### 修改内容

1. 调用 `swagger_json()` 获取 swagger.json 内容
2. 使用 `io_lib:format/2` 将 JSON 嵌入到 HTML 模板中
3. Swagger UI 直接使用嵌入的 `spec` 对象，而不是通过 URL 加载

### 优点

- ✅ 完全避免路径解析问题
- ✅ 减少一次 HTTP 请求
- ✅ 确保 swagger.json 和 UI 始终同步
- ✅ 不依赖 CORS 或其他网络配置

## 常见问题

### Q: 如果 swagger.json 更新了怎么办？

A: 每次重新编译插件时，`swagger_json()` 函数会从 `priv/swagger.json` 文件读取最新内容，所以重新构建即可。

### Q: 会影响性能吗？

A: 不会。swagger.json 只有约 10KB，嵌入到 HTML 中对加载时间的影响可以忽略不计。

### Q: 为什么之前用 URL 加载的方式不行？

A: EMQX 的 minirest 路由使用 `/kafka_bridge/[...]` 通配符匹配，Swagger UI 在解析相对路径时可能会产生歧义，导致请求到错误的 URL。

---

*修复日期：2026-03-30*
