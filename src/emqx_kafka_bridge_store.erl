-module(emqx_kafka_bridge_store).

-include("emqx_kafka_bridge.hrl").

-export([init/0]).
-export([list_rules/0, list_enabled_rules/0]).
-export([get_rule/1, get_rule_by_topic/1, add_rule/1, update_rule/2, delete_rule/1]).
-export([save_to_file/0, load_from_file/0, load_initial_rules/0]).
-export([search_rules/1]).

-define(TABLE, kafka_forward_rule).
-define(PERSIST_FILE, "/opt/emqx/data/kafka_bridge_rules.json").
-define(INITIAL_RULES_FILE, "forward_rules.json").

%% ===================================================================
%% 初始化 Mnesia 表
%% ===================================================================

init() ->
  case mnesia:create_table(?TABLE, [
    {type, set},
    {disc_copies, [node()]},
    {record_name, kafka_forward_rule},
    {attributes, record_info(fields, kafka_forward_rule)}
  ]) of
    {atomic, ok} ->
      wait_for_table();
    {aborted, {already_exists, ?TABLE}} ->
      wait_for_table(),
      %% 检查是否是内存表，如果是则转换为磁盘表
      case mnesia:table_info(?TABLE, storage_type) of
        ram_copies ->
          mnesia:change_table_copy_type(?TABLE, node(), disc_copies),
          ok;
        _ ->
          ok
      end;
    {aborted, Reason} ->
      logger:warning("[kafka_bridge] create table failed: ~p", [Reason]),
      ok
  end.

wait_for_table() ->
  case mnesia:wait_for_tables([?TABLE], 30000) of
    ok -> ok;
    {timeout, _} ->
      logger:error("[kafka_bridge] wait for table timeout"),
      {error, timeout};
    {error, Reason} ->
      logger:error("[kafka_bridge] wait for table error: ~p", [Reason]),
      {error, Reason}
  end.

%% ===================================================================
%% 查询操作
%% ===================================================================

list_rules() ->
  mnesia:dirty_select(?TABLE, [{'_', [], ['$_']}]).

list_enabled_rules() ->
  mnesia:dirty_select(?TABLE, [
    {#kafka_forward_rule{enabled = true, _ = '_'}, [], ['$_']}
  ]).

get_rule(Id) ->
  case mnesia:dirty_read(?TABLE, Id) of
    [Rule] -> {ok, Rule};
    [] -> {error, not_found}
  end.

get_rule_by_topic(Topic) ->
  case mnesia:dirty_match_object(?TABLE, #kafka_forward_rule{mqtt_topic = Topic, _ = '_'}) of
    [Rule] -> {ok, Rule};
    [] -> {error, not_found};
    Rules when is_list(Rules) -> {ok, hd(Rules)}
  end.

%% ===================================================================
%% 写操作
%% ===================================================================

add_rule(Rule) ->
  Now = erlang:system_time(second),
  NewRule = Rule#kafka_forward_rule{
    created_at = Now,
    updated_at = Now
  },
  case mnesia:transaction(fun() -> mnesia:write(?TABLE, NewRule, write) end) of
    {atomic, ok} ->
      refresh_cache(),
      {ok, NewRule};
    {aborted, Reason} ->
      {error, Reason}
  end.

update_rule(Id, Updates) ->
  Now = erlang:system_time(second),
  case mnesia:transaction(fun() ->
    case mnesia:read(?TABLE, Id) of
      [Old] ->
        Merged = merge_rule(Old, Updates#kafka_forward_rule{updated_at = Now}),
        mnesia:write(?TABLE, Merged, write),
        Merged;
      [] ->
        mnesia:abort(not_found)
    end
  end) of
    {atomic, Updated} ->
      refresh_cache(),
      {ok, Updated};
    {aborted, not_found} ->
      {error, not_found};
    {aborted, Reason} ->
      {error, Reason}
  end.

delete_rule(Id) ->
  case mnesia:transaction(fun() ->
    case mnesia:read(?TABLE, Id) of
      [_] -> mnesia:delete(?TABLE, Id, write);
      [] -> mnesia:abort(not_found)
    end
  end) of
    {atomic, ok} ->
      refresh_cache(),
      ok;
    {aborted, not_found} ->
      {error, not_found};
    {aborted, Reason} ->
      {error, Reason}
  end.

%% ===================================================================
%% 持久化到文件
%% ===================================================================

save_to_file() ->
  Rules = list_rules(),
  JsonRules = [rule_to_json(R) || R <- Rules],
  Bin = jiffy:encode(JsonRules),
  case file:write_file(?PERSIST_FILE, Bin) of
    ok ->
      logger:info("[kafka_bridge] saved ~p rules to ~s", [length(Rules), ?PERSIST_FILE]),
      ok;
    {error, Reason} ->
      logger:error("[kafka_bridge] save rules failed: ~p", [Reason]),
      {error, Reason}
  end.

load_from_file() ->
  case file:read_file(?PERSIST_FILE) of
    {ok, Bin} ->
      try
        RulesJson = jiffy:decode(Bin, [return_maps]),
        Count = lists:foldl(fun(Json, Acc) ->
          case json_to_rule(Json) of
            {ok, Rule} ->
              case add_rule(Rule) of
                {ok, _} -> Acc + 1;
                {error, _} -> Acc
              end;
            {error, _} -> Acc
          end
        end, 0, RulesJson),
        {ok, Count}
      catch E:R ->
        logger:error("[kafka_bridge] load rules failed: ~p:~p", [E, R]),
        {error, {parse_error, E, R}}
      end;
    {error, enoent} ->
      {error, enoent};
    {error, Reason} ->
      {error, Reason}
  end.

%% ===================================================================
%% 高级查询（分页、排序、模糊搜索）
%% ===================================================================

search_rules(Options) when is_map(Options) ->
  %% 1. 获取全量数据
  AllRules = list_rules(),
  
  %% 2. 关键字过滤（模糊匹配 mqtt_topic）
  Keyword = maps:get(keyword, Options, undefined),
  FilteredRules = filter_by_keyword(AllRules, Keyword),
  
  %% 3. 获取总数
  TotalCount = length(FilteredRules),
  
  %% 4. 排序
  SortBy = maps:get(sort_by, Options, created_at),
  SortOrder = maps:get(sort_order, Options, desc),
  SortedRules = sort_rules(FilteredRules, SortBy, SortOrder),
  
  %% 5. 分页
  Page = maps:get(page, Options, 1),
  Limit = maps:get(limit, Options, 10),
  PagedData = paginate(SortedRules, Page, Limit),
  
  %% 6. 返回分页结果
  {ok, #{
    total => TotalCount,
    page => Page,
    limit => Limit,
    data => PagedData
  }}.

filter_by_keyword(Rules, undefined) -> Rules;
filter_by_keyword(Rules, <<>>) -> Rules;
filter_by_keyword(Rules, Keyword) ->
  lists:filter(fun(#kafka_forward_rule{mqtt_topic = Topic}) ->
    %% 模糊匹配：检查 Topic 是否包含 Keyword
    case binary:match(Topic, Keyword) of
      nomatch -> false;
      _ -> true
    end
  end, Rules).

sort_rules(Rules, SortBy, SortOrder) ->
  CompareFun = fun(A, B) ->
    ValA = extract_field(A, SortBy),
    ValB = extract_field(B, SortBy),
    case SortOrder of
      asc -> ValA =< ValB;
      desc -> ValA >= ValB;
      _ -> ValA >= ValB
    end
  end,
  lists:sort(CompareFun, Rules).

extract_field(#kafka_forward_rule{mqtt_topic = M}, mqtt_topic) -> M;
extract_field(#kafka_forward_rule{kafka_topic = T}, kafka_topic) -> T;
extract_field(#kafka_forward_rule{qos = Q}, qos) -> Q;
extract_field(#kafka_forward_rule{payload_format = P}, payload_format) -> P;
extract_field(#kafka_forward_rule{payload_template = P}, payload_template) -> P;
extract_field(#kafka_forward_rule{kafka_key = K}, kafka_key) -> K;
extract_field(#kafka_forward_rule{enabled = E}, enabled) -> E;
extract_field(#kafka_forward_rule{description = D}, description) -> D;
extract_field(#kafka_forward_rule{created_at = C}, created_at) -> C;
extract_field(#kafka_forward_rule{updated_at = U}, updated_at) -> U;
extract_field(#kafka_forward_rule{}, _) -> undefined.

paginate(List, Page, Limit) when Page > 0, Limit > 0 ->
  Start = (Page - 1) * Limit + 1,
  lists:sublist(List, Start, Limit);
paginate(List, _, _) -> List.

%% ===================================================================
%% 加载初始规则 (from etc/forward_rules.json)
%% ===================================================================

load_initial_rules() ->
  %% 只在表为空时加载初始规则
  case list_rules() of
    [] ->
      %% 尝试从持久化文件加载
      case load_from_file() of
        {ok, Count} when Count > 0 ->
          logger:info("[kafka_bridge] loaded ~p rules from persist file", [Count]);
        {error, enoent} ->
          %% 持久化文件不存在，尝试加载初始规则文件
          case load_rules_from_file(?INITIAL_RULES_FILE) of
            {ok, InitCount} when InitCount > 0 ->
              logger:info("[kafka_bridge] loaded ~p rules from ~s", [InitCount, ?INITIAL_RULES_FILE]),
              %% 保存到持久化文件
              save_to_file();
            {error, enoent} ->
              logger:info("[kafka_bridge] no initial rules file found");
            {error, Reason} ->
              logger:warning("[kafka_bridge] load initial rules failed: ~p", [Reason])
          end;
        {error, Reason} ->
          logger:warning("[kafka_bridge] load persist file failed: ~p", [Reason])
      end;
    ExistingRules ->
      logger:info("[kafka_bridge] rules already exist (~p rules), skip initial load", [length(ExistingRules)])
  end.

load_rules_from_file(Filename) ->
  %% 从 etc 目录加载（尝试多个可能的位置）
  PossiblePaths = [
    filename:join(["/opt/emqx/etc", Filename]),
    filename:join([code:root_dir(), "lib", "emqx_kafka_bridge_v4-*", "etc", Filename]),
    filename:join(["etc", Filename])
  ],
  File = find_existing_file(PossiblePaths),
  
  case File of
    undefined ->
      {error, enoent};
    _ ->
      case file:read_file(File) of
        {ok, Bin} ->
          try
            RulesJson = jiffy:decode(Bin, [return_maps]),
            Count = lists:foldl(fun(Json, Acc) ->
              case json_to_rule(Json) of
                {ok, Rule} ->
                  case add_rule(Rule) of
                    {ok, _} -> Acc + 1;
                    {error, _} -> Acc
                  end;
                {error, _} -> Acc
              end
            end, 0, RulesJson),
            {ok, Count}
          catch E:R ->
            logger:error("[kafka_bridge] parse rules file failed: ~p:~p", [E, R]),
            {error, {parse_error, E, R}}
          end;
        {error, enoent} ->
          {error, enoent};
        {error, Reason} ->
          {error, Reason}
      end
  end.

%% ===================================================================
%% Internal
%% ===================================================================

find_existing_file(Paths) ->
  find_existing_file(Paths, undefined).

find_existing_file([], _NotFound) -> undefined;
find_existing_file([Path | Rest], _NotFound) ->
  %% 支持通配符路径
  case has_wildcard(Path) of
    true ->
      case filelib:wildcard(Path) of
        [Matched | _] -> Matched;
        [] -> find_existing_file(Rest, undefined)
      end;
    false ->
      case filelib:is_file(Path) of
        true -> Path;
        false -> find_existing_file(Rest, undefined)
      end
  end.

has_wildcard(Path) ->
  binary:match(list_to_binary(Path), [<<"*">>, <<"?">>]) =/= nomatch.

gen_id() ->
  <<A:32, B:16, C:16, D:16, E:48>> = crypto:strong_rand_bytes(16),
  iolist_to_binary(io_lib:format(
    "~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b", [A, B, C, D, E])).

refresh_cache() ->
  catch emqx_kafka_bridge_rule_cache:refresh().

merge_rule(Old, Updates) ->
  #kafka_forward_rule{
    mqtt_topic = coalesce(Updates#kafka_forward_rule.mqtt_topic, Old#kafka_forward_rule.mqtt_topic),
    kafka_topic = coalesce(Updates#kafka_forward_rule.kafka_topic, Old#kafka_forward_rule.kafka_topic),
    qos = pick(Updates#kafka_forward_rule.qos, Old#kafka_forward_rule.qos),
    payload_format = coalesce(Updates#kafka_forward_rule.payload_format, Old#kafka_forward_rule.payload_format),
    payload_template = coalesce(Updates#kafka_forward_rule.payload_template, Old#kafka_forward_rule.payload_template),
    kafka_key = coalesce(Updates#kafka_forward_rule.kafka_key, Old#kafka_forward_rule.kafka_key),
    enabled = pick(Updates#kafka_forward_rule.enabled, Old#kafka_forward_rule.enabled),
    description = coalesce(Updates#kafka_forward_rule.description, Old#kafka_forward_rule.description),
    created_at = Old#kafka_forward_rule.created_at,
    updated_at = Updates#kafka_forward_rule.updated_at
  }.

coalesce(undefined, V) -> V;
coalesce(V, _) -> V.

pick(undefined, V) -> V;
pick(V, _) -> V.

to_binary(Bin) when is_binary(Bin) -> Bin;
to_binary(Atom) when is_atom(Atom) -> atom_to_binary(Atom, utf8);
to_binary(Str) when is_list(Str) -> iolist_to_binary(Str);
to_binary(null) -> null;
to_binary(Undefined) when Undefined == undefined orelse Undefined == <<>> -> null;
to_binary(Val) -> iolist_to_binary(Val).

rule_to_json(Rule) ->
  #{
    <<"mqtt_topic">> => to_binary(Rule#kafka_forward_rule.mqtt_topic),
    <<"kafka_topic">> => to_binary(Rule#kafka_forward_rule.kafka_topic),
    <<"qos">> => case Rule#kafka_forward_rule.qos of undefined -> null; V -> V end,
    <<"payload_format">> => atom_to_binary(Rule#kafka_forward_rule.payload_format, utf8),
    <<"payload_template">> => to_binary(Rule#kafka_forward_rule.payload_template),
    <<"kafka_key">> => atom_to_binary(Rule#kafka_forward_rule.kafka_key, utf8),
    <<"enabled">> => Rule#kafka_forward_rule.enabled,
    <<"description">> => to_binary(Rule#kafka_forward_rule.description),
    <<"created_at">> => Rule#kafka_forward_rule.created_at,
    <<"updated_at">> => Rule#kafka_forward_rule.updated_at
  }.

json_to_rule(Json) ->
  try
    {ok, #kafka_forward_rule{
      mqtt_topic = maps:get(<<"mqtt_topic">>, Json, <<"#">>),
      kafka_topic = maps:get(<<"kafka_topic">>, Json, <<"mqtt_messages">>),
      qos = case maps:get(<<"qos">>, Json, 1) of null -> 1; V when is_number(V) -> V; _ -> 1 end,
      payload_format = binary_to_existing_atom(maps:get(<<"payload_format">>, Json, <<"json">>), utf8),
      payload_template = case maps:get(<<"payload_template">>, Json, null) of null -> undefined; V -> V end,
      kafka_key = binary_to_existing_atom(maps:get(<<"kafka_key">>, Json, <<"topic">>), utf8),
      enabled = maps:get(<<"enabled">>, Json, true),
      description = maps:get(<<"description">>, Json, <<>>)
    }}
  catch
    _:Reason -> {error, Reason}
  end.
