# API 实现总结

## 实现的 5 个核心接口

### 1. 规则列表查询 - `GET /kafka_bridge/rules`

**功能**:
- ✅ 分页查询（page, limit）
- ✅ 排序（sort_by, sort_order）
- ✅ 模糊匹配（topic 关键字）

**实现**:
```erlang
emqx_kafka_bridge_api:handle_rules/2
  → handle_rules_list/1
    → emqx_kafka_bridge_store:search_rules/1
      → filter_by_keyword/2      % 模糊匹配
      → sort_rules/3             % 排序
      → paginate/3               % 分页
```

**参数**:
- `topic` - MQTT 主题关键字（模糊匹配）
- `page` - 页码（默认 1）
- `limit` - 每页数量（默认 10）
- `sort_by` - 排序字段（created_at | mqtt_topic | name）
- `sort_order` - 排序方向（asc | desc）

---

### 2. 单个规则详情 - `GET /kafka_bridge/rule/get`

**功能**:
- ✅ 根据 MQTT 主题查询规则

**实现**:
```erlang
emqx_kafka_bridge_api:handle_rule_get/2
  → handle_get_rule_by_topic/1
    → emqx_kafka_bridge_store:get_rule_by_topic/1
      → mnesia:dirty_match_object/2
```

**参数**:
- `topic` - MQTT 主题（必需）

---

### 3. 新增规则 - `POST /kafka_bridge/rule/add`

**功能**:
- ✅ 创建新规则
- ✅ 自动保存到持久化文件
- ✅ 刷新缓存

**实现**:
```erlang
emqx_kafka_bridge_api:handle_rule_add/2
  → validate_rule_json/2         % 验证必需字段
  → json_to_rule/1               % JSON 转记录
  → emqx_kafka_bridge_store:add_rule/1
    → mnesia:transaction/1       % 事务写入
    → refresh_cache/0            % 刷新缓存
    → save_to_file/0             % 持久化
```

**必需字段**:
- `mqtt_topic` - MQTT 主题
- `kafka_topic` - Kafka 主题

---

### 4. 修改规则 - `POST /kafka_bridge/rule/update`

**功能**:
- ✅ 更新现有规则
- ✅ 自动保存到持久化文件
- ✅ 刷新缓存

**实现**:
```erlang
emqx_kafka_bridge_api:handle_rule_update/2
  → get_rule_by_topic/1          % 查找规则
  → emqx_kafka_bridge_store:update_rule/2
    → mnesia:transaction/1       % 事务更新
    → merge_rule/2               % 合并字段
    → refresh_cache/0            % 刷新缓存
    → save_to_file/0             % 持久化
```

**必需字段**:
- `mqtt_topic` - MQTT 主题（用于查找）
- `kafka_topic` - 新的 Kafka 主题

---

### 5. 删除规则 - `POST /kafka_bridge/rule/delete`

**功能**:
- ✅ 删除规则
- ✅ 自动保存到持久化文件
- ✅ 刷新缓存

**实现**:
```erlang
emqx_kafka_bridge_api:handle_rule_delete/2
  → get_rule_by_topic/1          % 查找规则
  → emqx_kafka_bridge_store:delete_rule/1
    → mnesia:transaction/1       % 事务删除
    → refresh_cache/0            % 刷新缓存
    → save_to_file/0             % 持久化
```

**必需字段**:
- `mqtt_topic` - MQTT 主题

---

## 技术实现

### 框架选择

**EMQX 5.x**: 使用 `minirest` 框架
- 声明式 API 定义
- 自动参数验证
- Swagger 集成

**EMQX 4.x**: 使用 `cowboy` 框架
- 手动路由配置
- 手动参数解析
- 更灵活的控制

### Cowboy Handler 实现

```erlang
%% 路由配置
Routes = [
  {'_', [
    {"/kafka_bridge/rules", ?MODULE, handle_rules, []},
    {"/kafka_bridge/rule/get", ?MODULE, handle_rule_get, []},
    {"/kafka_bridge/rule/add", ?MODULE, handle_rule_add, []},
    {"/kafka_bridge/rule/update", ?MODULE, handle_rule_update, []},
    {"/kafka_bridge/rule/delete", ?MODULE, handle_rule_delete, []}
  ]}
],

%% Handler 函数
handle_rules(Req = #{method := <<"GET">>}, _Opts) ->
  Query = maps:get(query, Req, #{}),
  handle_rules_list(Query);
handle_rules(Req, _Opts) ->
  method_not_allowed(Req).
```

### 数据存储

**Mnesia 表结构**:
```erlang
-record(kafka_forward_rule, {
  id              :: binary(),
  name            :: binary(),
  mqtt_topic      :: binary(),
  kafka_topic     :: binary(),
  qos             :: integer() | undefined,
  payload_format  :: raw | json | template,
  payload_template :: binary() | undefined,
  kafka_key       :: client_id | username | topic | none,
  enabled         :: boolean(),
  description     :: binary(),
  created_at      :: integer(),
  updated_at      :: integer()
}).
```

**存储方式**:
- `disc_copies` - 磁盘存储（集群同步）
- JSON 备份 - 单节点恢复

---

## 与 5.x 版本的区别

| 特性 | EMQX 5.x | EMQX 4.x (本项目) |
|------|---------|-----------------|
| HTTP 框架 | minirest | cowboy |
| API 定义 | 声明式 (api_spec) | 手动路由 |
| 参数验证 | 自动（schema） | 手动验证 |
| 路由匹配 | 自动 | 手动 pattern match |
| 响应格式 | 统一 | 统一 |
| Swagger | 自动生成 | 需手动编写 |

### 5.x 示例（minirest）
```erlang
rules_list_path() ->
  {"/kafka_bridge/rules",
    #{get => #{
      parameters => [
        #{name => <<"page">>, in => query, schema => #{type => integer}}
      ]
    }}}.
```

### 4.x 示例（cowboy）
```erlang
handle_rules(Req = #{method := <<"GET">>}, _Opts) ->
  Query = maps:get(query, Req, #{}),
  Page = get_int_param(Query, <<"page">>, 1),
  handle_rules_list(Query).
```

---

## 关键函数实现

### 1. 模糊匹配
```erlang
filter_by_keyword(Rules, Keyword) ->
  lists:filter(fun(#kafka_forward_rule{mqtt_topic = Topic}) ->
    case binary:match(Topic, Keyword) of
      nomatch -> false;
      _ -> true
    end
  end, Rules).
```

### 2. 动态排序
```erlang
sort_rules(Rules, SortBy, SortOrder) ->
  CompareFun = fun(A, B) ->
    ValA = extract_field(A, SortBy),
    ValB = extract_field(B, SortBy),
    case SortOrder of
      asc -> ValA =< ValB;
      desc -> ValA >= ValB
    end
  end,
  lists:sort(CompareFun, Rules).
```

### 3. 分页
```erlang
paginate(List, Page, Limit) ->
  Start = (Page - 1) * Limit + 1,
  lists:sublist(List, Start, Limit).
```

---

## 测试验证

### 1. 规则列表查询
```bash
# 基础查询
curl "http://localhost:8090/kafka_bridge/rules"

# 分页 + 排序
curl "http://localhost:8090/kafka_bridge/rules?page=1&limit=5&sort_by=created_at&sort_order=desc"

# 模糊搜索
curl "http://localhost:8090/kafka_bridge/rules?topic=sensor"
```

### 2. 单个规则查询
```bash
curl "http://localhost:8090/kafka_bridge/rule/get?topic=sensor/+/data"
```

### 3. 新增规则
```bash
curl -X POST "http://localhost:8090/kafka_bridge/rule/add" \
  -H "Content-Type: application/json" \
  -d '{"mqtt_topic":"test/#","kafka_topic":"test_data"}'
```

### 4. 更新规则
```bash
curl -X POST "http://localhost:8090/kafka_bridge/rule/update" \
  -H "Content-Type: application/json" \
  -d '{"mqtt_topic":"test/#","kafka_topic":"test_data_v2"}'
```

### 5. 删除规则
```bash
curl -X POST "http://localhost:8090/kafka_bridge/rule/delete" \
  -H "Content-Type: application/json" \
  -d '{"mqtt_topic":"test/#"}'
```

---

## 统一响应格式

所有 API 响应遵循统一格式：

```json
{
  "code": 0,
  "message": "success",
  "data": { ... }
}
```

**成功响应**:
- `code`: 0
- `message`: "success" | "created" | "updated" | "deleted"
- `data`: 响应数据

**错误响应**:
- `code`: 400 | 404 | 405 | 409 | 500
- `message`: 错误描述
- `data`: （可选）错误详情

---

## 持久化保证

每次规则变更都会：
1. Mnesia 事务写入
2. 刷新 ETS 缓存
3. 保存到 JSON 文件

确保：
- ✅ 数据一致性
- ✅ 重启不丢失
- ✅ 缓存实时性

---

## 下一步优化

1. **批量操作** - 批量导入/导出规则
2. **规则测试** - API 支持测试规则匹配
3. **导入导出** - 支持 JSON 文件导入导出
4. **监控指标** - Prometheus 指标导出
5. **Web UI** - 简单的管理界面
