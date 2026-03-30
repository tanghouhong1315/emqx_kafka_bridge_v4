-module(emqx_kafka_bridge_hook).

-include("emqx_kafka_bridge.hrl").

-export([register/1, unregister/0, on_message_publish/2]).

%% Hook 回调函数（通过 emqx_hooks 调用，不是未使用）
-compile({nowarn_unused_func, [forward_message/5, make_kafka_key/3, format_payload/5]}).

register(Env) ->
  ?LOG(warning, "=== HOOKS REGISTERING ===", []),
  emqx:hook('message.publish', {?MODULE, on_message_publish, [Env]}),
  ?LOG(warning, "=== HOOKS REGISTERED ===", []),
  ok.

unregister() ->
  emqx:unhook('message.publish', {?MODULE, on_message_publish}),
  logger:info("[kafka_bridge] hooks unregistered"),
  ok.

%% ===================================================================
%% Hook Callbacks
%% ===================================================================

on_message_publish(Message, _Env) ->
  Topic = emqx_message:topic(Message),
  %% 过滤系统主题（$SYS/开头的主题不处理）
  case is_system_topic(Topic) of
    true ->
      {ok, Message};
    false ->
      try
        Payload = emqx_message:payload(Message),
        QoS = emqx_message:qos(Message),
        ClientId = emqx_message:from(Message),

        emqx_kafka_bridge_metrics:inc(in),
        logger:info("[kafka_bridge] message received: topic=~s client=~s", [Topic, ClientId]),

        %% 匹配规则
        Rules = emqx_kafka_bridge_rule_cache:match(Topic),
        logger:info("[kafka_bridge] rules matched: ~p rules for topic ~s", [length(Rules), Topic]),
        case Rules of
          [] -> ok;
          _ -> 
            logger:info("[kafka_bridge] forwarding ~p messages to kafka", [length(Rules)])
        end,
        lists:foreach(fun(Rule) ->
          logger:info("[kafka_bridge] forwarding to kafka: ~s", [Rule#kafka_forward_rule.kafka_topic]),
          forward_message(Rule, Topic, Payload, QoS, ClientId)
                      end, Rules)
      catch E:R:Stack ->
        logger:error("[kafka_bridge] hook error: ~p:~p ~p", [E, R, Stack])
      end,
      {ok, Message}
  end.

%% ===================================================================
%% Internal
%% ===================================================================

forward_message(#kafka_forward_rule{
  kafka_topic = KafkaTopic,
  payload_format = Format,
  kafka_key = KeyStrategy
}, MqttTopic, Payload, QoS, ClientId) ->

  try
    %% 构建Kafka消息
    KafkaKey = make_kafka_key(KeyStrategy, MqttTopic, ClientId),
    KafkaValue = format_payload(Format, MqttTopic, Payload, QoS, ClientId),

    %% 直接调用 producer 异步发送（brod 本身支持异步）
    emqx_kafka_bridge_producer:produce_async(KafkaTopic, KafkaKey, KafkaValue)
  catch E:R:Stack ->
    logger:error("[kafka_bridge] forward_message exception: ~p:~p stack=~p", [E, R, Stack])
  end.

make_kafka_key(topic, Topic, _) ->
  Topic;
make_kafka_key(client_id, _, ClientId) ->
  ClientId;
make_kafka_key(username, _, _) ->
  <<"">>;  %% TODO: 从message获取username
make_kafka_key(none, _, _) ->
  <<"">>.

format_payload(json, Topic, Payload, QoS, ClientId) ->
  jiffy:encode(#{
    <<"topic">>     => Topic,
    <<"payload">>   => Payload,
    <<"qos">>       => QoS,
    <<"client_id">> => ClientId,
    <<"timestamp">> => erlang:system_time(millisecond)
  });
format_payload(raw, _Topic, Payload, _QoS, _ClientId) ->
  Payload;
format_payload(template, _Topic, Payload, _QoS, _ClientId) ->
  Payload.

%% 判断是否是系统主题（$SYS/开头）
is_system_topic(<<"$SYS/", _/binary>>) -> true;
is_system_topic(_) -> false.