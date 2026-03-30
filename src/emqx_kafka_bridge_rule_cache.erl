-module(emqx_kafka_bridge_rule_cache).

-behaviour(gen_server).

-include("emqx_kafka_bridge.hrl").

-export([start_link/0, refresh/0, match/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(TAB, kafka_rule_cache).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

refresh() ->
  gen_server:cast(?MODULE, refresh).

%% 直接从ETS读，无需经过gen_server
match(MqttTopic) ->
  try
    TopicParts = binary:split(MqttTopic, <<"/">>, [global]),
    ets:foldl(fun({_Id, Rule}, Acc) ->
      FilterParts = binary:split(Rule#kafka_forward_rule.mqtt_topic, <<"/">>, [global]),
      case topic_match(TopicParts, FilterParts) of
        true  -> [Rule | Acc];
        false -> Acc
      end
              end, [], ?TAB)
  catch
    error:badarg -> []
  end.

%% ===================================================================
%% gen_server
%% ===================================================================

init([]) ->
  ets:new(?TAB, [named_table, set, public, {read_concurrency, true}]),
  self() ! load,
  {ok, #{}}.

handle_call(_, _, S)           -> {reply, ok, S}.
handle_cast(refresh, S)        -> do_refresh(), {noreply, S}.
handle_info(load, S)           -> do_refresh(), {noreply, S};
handle_info(_, S)              -> {noreply, S}.
terminate(_, _)                -> catch ets:delete(?TAB), ok.

%% ===================================================================
%% Internal
%% ===================================================================

do_refresh() ->
  try
    Rules = emqx_kafka_bridge_store:list_enabled_rules(),
    ets:delete_all_objects(?TAB),
    [ets:insert(?TAB, {R#kafka_forward_rule.mqtt_topic, R}) || R <- Rules],
    logger:info("[kafka_bridge] cache refreshed, ~p rules", [length(Rules)])
  catch E:R ->
    logger:error("[kafka_bridge] cache refresh failed: ~p:~p", [E, R]),
    erlang:send_after(1000, self(), load)
  end.

%% MQTT主题通配符匹配
topic_match([], [])                    -> true;
topic_match([_|T1], [<<"+">>|T2])      -> topic_match(T1, T2);
topic_match(_, [<<"#">>])              -> true;
topic_match([H|T1], [H|T2])           -> topic_match(T1, T2);
topic_match(_, _)                      -> false.