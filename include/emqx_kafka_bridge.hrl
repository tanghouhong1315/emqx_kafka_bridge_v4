-ifndef(EMQX_KAFKA_BRIDGE_HRL).
-define(EMQX_KAFKA_BRIDGE_HRL, true).

%% 转发规则（主键：mqtt_topic）
-record(kafka_forward_rule, {
  mqtt_topic      :: binary(),          %% 主键，支持通配符 + #
  kafka_topic     :: binary(),
  qos             :: integer() | undefined,  %% undefined = 不限
  payload_format  :: raw | json | template,
  payload_template :: binary() | undefined,
  kafka_key       :: client_id | username | topic | none,
  enabled         :: boolean(),
  description     :: binary(),
  created_at      :: integer(),
  updated_at      :: integer()
}).

-define(RULE_TAB, kafka_forward_rule).

-define(LOG(Level, Fmt, Args),
  logger:Level("[kafka_bridge] " ++ Fmt, Args)).

-endif.