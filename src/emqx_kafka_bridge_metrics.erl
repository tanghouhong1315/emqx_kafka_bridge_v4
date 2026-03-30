-module(emqx_kafka_bridge_metrics).

-behaviour(gen_server).

-export([start_link/0, inc/1, get/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(st, {
  in = 0      :: non_neg_integer(),
  out = 0     :: non_neg_integer(),
  dropped = 0 :: non_neg_integer(),
  error = 0   :: non_neg_integer()
}).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

inc(Type) ->
  gen_server:cast(?MODULE, {inc, Type}).

get() ->
  gen_server:call(?MODULE, get).

init([]) ->
  {ok, #st{}}.

handle_call(get, _From, S) ->
  {reply, #{
    in      => S#st.in,
    out     => S#st.out,
    dropped => S#st.dropped,
    error   => S#st.error
  }, S};
handle_call(_, _, S) ->
  {reply, ok, S}.

handle_cast({inc, in}, S)      -> {noreply, S#st{in = S#st.in + 1}};
handle_cast({inc, out}, S)     -> {noreply, S#st{out = S#st.out + 1}};
handle_cast({inc, dropped}, S) -> {noreply, S#st{dropped = S#st.dropped + 1}};
handle_cast({inc, error}, S)   -> {noreply, S#st{error = S#st.error + 1}};
handle_cast(_, S)              -> {noreply, S}.

handle_info(_, S) -> {noreply, S}.
terminate(_, _)   -> ok.