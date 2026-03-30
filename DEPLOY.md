# 快速部署指南

## 🚀 修复内容

Swagger UI 现在会**自动检测**浏览器访问的地址，并将该地址设置为 API Servers。

**工作原理**：
```javascript
// 获取当前访问的协议、主机和端口
const currentUrl = window.location.protocol + '//' + window.location.host + '/kafka_bridge';

// 动态替换 swagger.json 中的 servers 字段
spec.servers = [{
    url: currentUrl,
    description: "当前访问地址"
}];
```

## 📦 部署步骤

### 方案 A：如果你有 Linux 构建服务器

#### 1. 复制修改后的代码到构建服务器

```bash
# 在 Windows 上打包修改后的代码
cd C:\Users\thh\.openclaw\workspace
tar -czf emqx_kafka_bridge_v4_fixed.tar.gz emqx_kafka_bridge_v4/

# 通过 SCP 或其他方式上传到 Linux 服务器
scp emqx_kafka_bridge_v4_fixed.tar.gz user@build-server:/home/user/
```

#### 2. 在构建服务器上解压并构建

```bash
# SSH 登录到构建服务器
ssh user@build-server

# 解压
tar -xzf emqx_kafka_bridge_v4_fixed.tar.gz
cd emqx_kafka_bridge_v4

# 执行构建（使用缓存，约 5-10 分钟）
./build-linux.sh
```

#### 3. 推送新镜像

```bash
# 构建脚本会自动推送，如果没有，手动推送
docker push tanghouhong/emqx_kafka_bridge_v4:1.0.0-emqx4.4.19
```

#### 4. 在目标服务器上更新

```bash
# SSH 登录到目标服务器 (192.168.18.78)
ssh user@192.168.18.78

# 停止并删除旧容器
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

### 方案 B：直接在目标服务器上构建

如果目标服务器就是运行 EMQX 的服务器：

```bash
# 1. 复制项目到服务器
cd C:\Users\thh\.openclaw\workspace
tar -czf emqx_kafka_bridge_v4.tar.gz emqx_kafka_bridge_v4/
scp emqx_kafka_bridge_v4.tar.gz user@192.168.18.78:/home/user/

# 2. SSH 登录到服务器
ssh user@192.168.18.78

# 3. 解压并构建
tar -xzf emqx_kafka_bridge_v4.tar.gz
cd emqx_kafka_bridge_v4
./build-linux.sh

# 4. 更新容器
docker stop emqx-kafka && docker rm emqx-kafka
docker run -d --name emqx-kafka \
  -p 1883:1883 \
  -p 8090:8090 \
  -p 18083:18083 \
  tanghouhong/emqx_kafka_bridge_v4:1.0.0-emqx4.4.19
```

## ✅ 验证修复

### 1. 访问 Swagger UI

在浏览器中打开：
```
http://192.168.18.78:8090/kafka_bridge/docs
```

### 2. 检查 Servers 下拉框

应该显示：
```
http://192.168.18.78:8090/kafka_bridge - 当前访问地址
```

✅ **正确** - 显示当前访问的 IP 地址
❌ **错误** - 显示 `localhost` 或其他地址

### 3. 测试 API

1. 展开 `/health` 端点
2. 点击 "Try it out"
3. 点击 "Execute"
4. 检查 **Request URL** 应该是：
   ```
   http://192.168.18.78:8090/kafka_bridge/health
   ```

### 4. 测试规则管理 API

```bash
# 获取规则列表
curl -X GET "http://192.168.18.78:8090/kafka_bridge/rules"

# 添加规则
curl -X POST "http://192.168.18.78:8090/kafka_bridge/rule/add" \
  -H "Content-Type: application/json" \
  -d '{
    "mqtt_topic": "test/#",
    "kafka_topic": "test_topic",
    "enabled": true
  }'

# 验证添加成功
curl -X GET "http://192.168.18.78:8090/kafka_bridge/rules"
```

## 🔧 故障排查

### 问题 1：Servers 仍然显示 localhost

**原因**：可能使用了旧的镜像

**解决**：
```bash
# 确认镜像已更新
docker images | grep emqx_kafka_bridge_v4

# 强制重新拉取
docker rmi tanghouhong/emqx_kafka_bridge_v4:1.0.0-emqx4.4.19
docker pull tanghouhong/emqx_kafka_bridge_v4:1.0.0-emqx4.4.19
docker restart emqx-kafka
```

### 问题 2：Swagger UI 无法加载

**原因**：端口未开放或容器未启动

**解决**：
```bash
# 检查容器状态
docker ps | grep emqx-kafka

# 检查端口监听
netstat -tlnp | grep 8090

# 检查防火墙
firewall-cmd --list-ports
# 如果需要，添加端口
firewall-cmd --add-port=8090/tcp --permanent
firewall-cmd --reload
```

### 问题 3：API 请求返回错误

**原因**：插件未正确加载

**解决**：
```bash
# 查看容器日志
docker logs emqx-kafka | grep kafka_bridge

# 检查插件状态
docker exec emqx-kafka emqx_ctl plugins list | grep kafka

# 如果插件未加载，手动加载
docker exec emqx-kafka emqx_ctl plugins load emqx_kafka_bridge_v4
```

## 📝 修改的文件

只修改了一个文件：
- `src/emqx_kafka_bridge_api.erl` - `swagger_ui/2` 函数

**修改内容**：
1. 嵌入 swagger.json 内容到 HTML
2. 使用 JavaScript 动态替换 `servers` 字段
3. 确保 API 请求发送到当前访问的服务器地址

## 🎯 预期效果

修复后，无论你从哪个设备、哪个 IP 地址访问 Swagger UI：

| 访问地址 | Servers 显示 | API 请求发送到 |
|---------|-------------|---------------|
| `http://192.168.18.78:8090/kafka_bridge/docs` | `http://192.168.18.78:8090/kafka_bridge` | `192.168.18.78:8090` |
| `http://localhost:8090/kafka_bridge/docs` | `http://localhost:8090/kafka_bridge` | `localhost:8090` |
| `http://10.0.0.100:8090/kafka_bridge/docs` | `http://10.0.0.100:8090/kafka_bridge` | `10.0.0.100:8090` |

---

*最后更新：2026-03-30*
