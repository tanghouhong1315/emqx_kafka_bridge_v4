-module(emqx_kafka_bridge_producer).

-behaviour(gen_server).

-include("emqx_kafka_bridge.hrl").

-export([start_link/0, produce_async/3, produce_sync/3, status/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(CLIENT, kafka_bridge_client).

-record(st, {
  connected = false :: boolean(),
  hosts     = []    :: list(),
  prod_cfg  = []    :: list(),
  topics    = #{}   :: map()   %% topic => started
}).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

produce_async(Topic, Key, Value) ->
  gen_server:cast(?MODULE, {produce, Topic, Key, Value}).

produce_sync(Topic, Key, Value) ->
  gen_server:call(?MODULE, {produce, Topic, Key, Value}, 10000).

status() ->
  gen_server:call(?MODULE, status).

%% ===================================================================
%% gen_server
%% ===================================================================

init([]) ->
  process_flag(trap_exit, true),
  %% 优先使用环境变量
  HostsRaw = case os:getenv("KAFKA_BOOTSTRAP_SERVERS") of
    false -> emqx_kafka_bridge_config:get(kafka_bootstrap_hosts, [{"127.0.0.1", 9092}]);
    "" -> emqx_kafka_bridge_config:get(kafka_bootstrap_hosts, [{"127.0.0.1", 9092}]);
    EnvVal -> parse_env_hosts(EnvVal)
  end,
  logger:info("[kafka_bridge] producer init with hosts: ~p", [HostsRaw]),
  ProdCfg = emqx_kafka_bridge_config:get(kafka_producer_config, []),
  %% 同步等待连接成功，避免启动时消息被丢弃
  S = #st{hosts = HostsRaw, prod_cfg = ProdCfg},
  S2 = do_connect(S),
  {ok, S2}.

handle_call({produce, _T, _K, _V}, _From, #st{connected = false} = S) ->
  {reply, {error, not_connected}, S};
handle_call({produce, Topic, Key, Value}, _From, S) ->
  S2 = ensure_topic(Topic, S),
  Res = try brod:produce_sync(?CLIENT, Topic, hash, Key, Value)
        catch E:R -> {error, {E, R}} end,
  {reply, Res, S2};
handle_call(status, _From, S) ->
  {reply, #{connected => S#st.connected, hosts => S#st.hosts}, S};
handle_call(_, _, S) ->
  {reply, ok, S}.

handle_cast({produce, _T, _K, _V}, #st{connected = false} = S) ->
  emqx_kafka_bridge_metrics:inc(dropped),
  logger:warning("[kafka_bridge] produce skipped: not connected"),
  {noreply, S};
handle_cast({produce, Topic, Key, Value}, S) ->
  logger:info("[kafka_bridge] produce_async: topic=~s connected=~p", [Topic, S#st.connected]),
  try
    S2 = ensure_topic(Topic, S),
    case brod:produce(?CLIENT, Topic, hash, Key, Value) of
      {ok, _Ref}      -> 
        emqx_kafka_bridge_metrics:inc(out),
        {noreply, S2};
      {error, Reason} ->
        emqx_kafka_bridge_metrics:inc(error),
        logger:error("[kafka_bridge] produce error: topic=~s reason=~p", [Topic, Reason]),
        {noreply, S2}
    end
  catch E:R:Stack ->
    emqx_kafka_bridge_metrics:inc(error),
    logger:error("[kafka_bridge] produce exception: ~p:~p stack=~p", [E, R, Stack]),
    {noreply, S}
  end;
handle_cast(_, S) ->
  {noreply, S}.

handle_info(connect, S) ->
  {noreply, do_connect(S)};
handle_info({'EXIT', _Pid, Reason}, S) ->
  logger:warning("[kafka_bridge] client exited: ~p, reconnecting...", [Reason]),
  erlang:send_after(5000, self(), connect),
  {noreply, S#st{connected = false, topics = #{}}};
handle_info(_, S) ->
  {noreply, S}.

terminate(_, #st{connected = true}) ->
  catch brod:stop_client(?CLIENT), ok;
terminate(_, _) ->
  ok.

%% ===================================================================
%% Internal
%% ===================================================================

%% 解析环境变量中的 Kafka 地址 "host1:port1,host2:port2" -> [{"host1", port1}, ...]
parse_env_hosts(Str) ->
  Pairs = string:tokens(Str, ","),
  lists:map(fun(Pair) ->
    Trimmed = string:trim(Pair),
    case string:tokens(Trimmed, ":") of
      [Host, PortStr] ->
        {iolist_to_binary(string:trim(Host)), list_to_integer(string:trim(PortStr))};
      [Host] ->
        {iolist_to_binary(string:trim(Host)), 9092}
    end
  end, Pairs).

do_connect(#st{hosts = Hosts, prod_cfg = ProdCfg} = S) ->
  catch brod:stop_client(?CLIENT),
  %% 直接使用 tuple 格式 [{Host, Port}]
  HostsTuples = Hosts,
  logger:info("[kafka_bridge] connecting to kafka: ~p (from ~p)", [HostsTuples, Hosts]),
  ClientCfg = [
    {reconnect_cool_down_seconds,
      emqx_kafka_bridge_config:get(kafka_reconnect_cool_down_seconds, 10)},
    {auto_start_producers, true},
    {default_producer_config, ProdCfg},
    {allow_topic_auto_creation, false}
  ],
  case brod:start_client(HostsTuples, ?CLIENT, ClientCfg) of
    ok ->
      logger:info("[kafka_bridge] kafka connected: ~p", [HostsTuples]),
      S#st{connected = true, topics = #{}};
    {error, Reason} ->
      logger:error("[kafka_bridge] kafka connect failed: ~p", [Reason]),
      erlang:send_after(5000, self(), connect),
      S#st{connected = false}
  end.

ensure_topic(Topic, #st{topics = Topics} = S) ->
  try
    case maps:is_key(Topic, Topics) of
      true -> S;
      false ->
        case brod:start_producer(?CLIENT, Topic, S#st.prod_cfg) of
          ok ->
            logger:info("[kafka_bridge] started producer for ~s", [Topic]),
            S#st{topics = Topics#{Topic => true}};
          {error, {already_started, _}} ->
            S#st{topics = Topics#{Topic => true}};
          {error, Reason} ->
            logger:error("[kafka_bridge] start producer ~s failed: ~p", [Topic, Reason]),
            S
        end
    end
  catch E:R:Stack ->
    logger:error("[kafka_bridge] ensure_topic exception: ~p:~p topic=~s", [E, R, Topic, Stack]),
    S
  end.