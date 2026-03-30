-module(emqx_kafka_bridge_app).

-behaviour(application).

-emqx_plugin(?MODULE).

-include("emqx_kafka_bridge.hrl").

-export([start/2, stop/1]).

start(_Type, _Args) ->
  logger:info("[kafka_bridge] application starting..."),
  
  %% 0. 加载配置
  emqx_kafka_bridge_config:load(),
  
  %% 1. 初始化 Mnesia 存储表
  case emqx_kafka_bridge_store:init() of
    ok ->
      logger:info("[kafka_bridge] storage tables initialized");
    {error, Reason1} ->
      logger:warning("[kafka_bridge] storage init warning: ~p", [Reason1]);
    {timeout, _} ->
      logger:warning("[kafka_bridge] storage init timeout")
  end,
  
  %% 2. 加载初始规则（从 etc/forward_rules.json 或持久化文件）
  emqx_kafka_bridge_store:load_initial_rules(),
  
  %% 3. 启动 supervisor (包含 producer, rule_cache, metrics, async workers)
  case emqx_kafka_bridge_sup:start_link() of
    {ok, Sup} ->
      logger:info("[kafka_bridge] supervisor started"),
      
      %% 4. 注册 MQTT 消息钩子（在 supervisor 启动后）
      case emqx_kafka_bridge_hook:register(#{}) of
        ok ->
          logger:info("[kafka_bridge] hooks registered");
        {error, Reason3} ->
          logger:error("[kafka_bridge] hook register failed: ~p", [Reason3])
      end,
      
      %% 5. 启动 HTTP API
      case emqx_kafka_bridge_api:start() of
        ok ->
          logger:info("[kafka_bridge] HTTP API started");
        {error, ReasonApi} ->
          logger:error("[kafka_bridge] HTTP API start failed: ~p", [ReasonApi])
      end,
      
      {ok, Sup};
    {error, Reason2} ->
      logger:error("[kafka_bridge] supervisor start failed: ~p", [Reason2]),
      {error, Reason2}
  end.

stop(_State) ->
  logger:info("[kafka_bridge] application stopping..."),
  %% 注销 MQTT 消息钩子
  catch emqx_kafka_bridge_hook:unregister(),
  emqx_kafka_bridge_api:stop(),
  ok.
