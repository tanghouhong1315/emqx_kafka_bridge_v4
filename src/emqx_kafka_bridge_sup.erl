-module(emqx_kafka_bridge_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  Children = [
    #{id => emqx_kafka_bridge_producer,
      start => {emqx_kafka_bridge_producer, start_link, []},
      restart => permanent, type => worker},

    #{id => emqx_kafka_bridge_rule_cache,
      start => {emqx_kafka_bridge_rule_cache, start_link, []},
      restart => permanent, type => worker},

    #{id => emqx_kafka_bridge_metrics,
      start => {emqx_kafka_bridge_metrics, start_link, []},
      restart => permanent, type => worker}
  ],
  
  {ok, {#{strategy => one_for_one, intensity => 10, period => 60}, Children}}.