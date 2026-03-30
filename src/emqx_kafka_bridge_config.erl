-module(emqx_kafka_bridge_config).

-export([load/0, get/1, get/2]).

-define(APP, emqx_kafka_bridge_v4).

load() ->
  %% Kafka 连接 - 优先使用环境变量，其次配置文件
  BootstrapServersRaw = case os:getenv("KAFKA_BOOTSTRAP_SERVERS") of
    false -> get_config(kafka_bootstrap_hosts, "127.0.0.1:9092");
    "" -> get_config(kafka_bootstrap_hosts, "127.0.0.1:9092");
    EnvVal -> 
      logger:info("[kafka_bridge] using KAFKA_BOOTSTRAP_SERVERS env: ~s", [EnvVal]),
      EnvVal
  end,
  logger:info("[kafka_bridge] bootstrap servers raw: ~p", [BootstrapServersRaw]),
  ParsedHosts = parse_kafka_hosts(BootstrapServersRaw),
  logger:info("[kafka_bridge] bootstrap servers parsed: ~p", [ParsedHosts]),
  application:set_env(?APP, kafka_bootstrap_hosts, ParsedHosts),

  %% 生产者配置
  RequiredAcks = get_config_int(kafka_required_acks, 1),
  MaxRetries = get_config_int(kafka_max_retries, 3),
  RetryBackoff = get_config_int(kafka_retry_backoff_ms, 500),
  MaxBatchBytes = get_config_int(kafka_max_batch_bytes, 1048576),
  MaxInflight = get_config_int(kafka_max_inflight, 10),
  application:set_env(?APP, kafka_producer_config, [
    {required_acks, RequiredAcks},
    {max_retries, MaxRetries},
    {retry_backoff_ms, RetryBackoff},
    {max_batch_bytes, MaxBatchBytes},
    {max_inflight_batches, MaxInflight}
  ]),

  %% 异步配置
  PoolSize = get_config_int(producer_pool_size, 8),
  BatchSize = get_config_int(batch_size, 100),
  BatchTimeout = get_config_int(batch_timeout_ms, 50),
  logger:info("[kafka_bridge] config: pool_size=~p batch_size=~p batch_timeout=~p", 
    [PoolSize, BatchSize, BatchTimeout]),
  application:set_env(?APP, producer_pool_size, PoolSize),
  application:set_env(?APP, batch_size, BatchSize),
  application:set_env(?APP, batch_timeout_ms, BatchTimeout),

  %% 重连
  ReconnectCoolDown = get_config_int(kafka_reconnect_cool_down_seconds, 10),
  application:set_env(?APP, kafka_reconnect_cool_down_seconds, ReconnectCoolDown),

  %% API 端口
  ApiPort = get_config_int(api_port, 8090),
  application:set_env(?APP, api_port, ApiPort),

  %% 规则文件
  RulesFile = get_config(rules_file,
    filename:join([code:priv_dir(?APP), "forward_rules.json"])),
  application:set_env(?APP, rules_file, RulesFile),

  logger:info("[kafka_bridge] config loaded: kafka=~p pool_size=~p api_port=~p",
    [ParsedHosts, PoolSize, ApiPort]),
  ok.

get(Key) ->
  get(Key, undefined).

get(Key, Default) ->
  application:get_env(?APP, Key, Default).

%% ===================================================================
%% Internal
%% ===================================================================

%% 从 application 环境读取配置（EMQX 插件系统已解析配置文件）
get_config(Key, Default) ->
  case application:get_env(?APP, Key) of
    undefined -> Default;
    {ok, Val} -> Val
  end.

get_config_int(Key, Default) ->
  case application:get_env(?APP, Key) of
    undefined -> Default;
    {ok, Val} when is_integer(Val) -> Val;
    {ok, Val} when is_list(Val) ->
      try list_to_integer(Val)
      catch _:_ -> Default
      end;
    {ok, Val} when is_binary(Val) ->
      try binary_to_integer(Val)
      catch _:_ -> Default
      end
  end.

%% "host1:port1,host2:port2" -> [{"host1", 9092}, ...]
parse_kafka_hosts(Str) when is_list(Str) ->
  logger:info("[kafka_bridge] parsing kafka hosts string: ~s", [Str]),
  Pairs = string:tokens(Str, ","),
  Result = lists:map(fun(Pair) ->
    Trimmed = string:trim(Pair),
    case string:tokens(Trimmed, ":") of
      [Host, PortStr] ->
        HostTrimmed = iolist_to_binary(string:trim(Host)),
        PortTrimmed = string:trim(PortStr),
        PortInt = list_to_integer(PortTrimmed),
        {HostTrimmed, PortInt};
      [Host] ->
        HostTrimmed = iolist_to_binary(string:trim(Host)),
        {HostTrimmed, 9092}
    end
  end, Pairs),
  logger:info("[kafka_bridge] parsed kafka hosts: ~p", [Result]),
  Result;
%% Already parsed, return as-is
parse_kafka_hosts(Hosts) when is_list(Hosts) ->
  Hosts.
