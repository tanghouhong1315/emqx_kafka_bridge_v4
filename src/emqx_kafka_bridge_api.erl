-module(emqx_kafka_bridge_api).

-include("emqx_kafka_bridge.hrl").

-rest_api(#{name => swagger,
            method => 'GET',
            path => "/swagger.json",
            func => swagger,
            descr => "OpenAPI 3.0 specification"}).

-rest_api(#{name => swagger_ui,
            method => 'GET',
            path => "/docs",
            func => swagger_ui,
            descr => "Swagger UI"}).

-rest_api(#{name => health,
            method => 'GET',
            path => "/health",
            func => health,
            descr => "Health check"}).

-rest_api(#{name => list_rules,
            method => 'GET',
            path => "/rules",
            func => list_rules,
            descr => "List all rules"}).

-rest_api(#{name => get_rule,
            method => 'GET',
            path => "/rule/get",
            func => get_rule,
            descr => "Get rule by topic"}).

-rest_api(#{name => add_rule,
            method => 'POST',
            path => "/rule/add",
            func => add_rule,
            descr => "Add a new rule"}).

-rest_api(#{name => update_rule,
            method => 'POST',
            path => "/rule/update",
            func => update_rule,
            descr => "Update an existing rule"}).

-rest_api(#{name => delete_rule,
            method => 'POST',
            path => "/rule/delete",
            func => delete_rule,
            descr => "Delete a rule"}).

-export([start/0, stop/0, http_handlers/0]).
-export([swagger/2, swagger_ui/2, health/2, list_rules/2, get_rule/2, add_rule/2, update_rule/2, delete_rule/2]).

-define(API_PORT, 8090).
-define(LISTENER, kafka_bridge_http).

%% ===================================================================
%% 启动/停止
%% ===================================================================

start() ->
    Port = emqx_kafka_bridge_config:get(api_listen_port, ?API_PORT),
    Dispatch = [
        {"/kafka_bridge/[...]", minirest, http_handlers()}
    ],
    case minirest:start_http(?LISTENER, #{num_acceptors => 4, socket_opts => [{port, Port}]}, Dispatch, #{}) of
        ok ->
            logger:info("[kafka_bridge] API started on port ~p", [Port]),
            ok;
        {error, Reason} ->
            logger:error("[kafka_bridge] API start failed: ~p", [Reason]),
            error(Reason)
    end.

stop() ->
    catch minirest:stop_http(?LISTENER),
    ok.

%% ===================================================================
%% HTTP Handlers
%% ===================================================================

http_handlers() ->
    [{"/kafka_bridge", minirest:handler(#{apps => [emqx_kafka_bridge_v4]}), []}].

%% ===================================================================
%% Handler Functions
%% 注意：Params 是 proplist，需要转换为 map
%% ===================================================================

swagger(_Bindings, _Params) ->
    JsonBin = swagger_json(),
    %% 解析成 map，让 minirest 自己序列化
    JsonMap = jiffy:decode(JsonBin, [return_maps]),
    {200, #{<<"content-type">> => <<"application/json">>}, JsonMap}.

swagger_ui(_Bindings, _Params) ->
    HtmlBin = swagger_ui_html(),
    %% 返回 map 格式的 headers，确保 binary 不被转义
    {200, #{<<"content-type">> => <<"text/html; charset=utf-8">>}, HtmlBin}.

swagger_json() ->
    {ok, App} = application:get_application(?MODULE),
    PrivDir = code:priv_dir(App),
    File = filename:join(PrivDir, "swagger.json"),
    case file:read_file(File) of
        {ok, Bin} -> Bin;
        _ -> <<"{}">>
    end.

swagger_ui_html() ->
    %% 简单的 API 文档页面 - 从 swagger.json 加载并渲染
    Html = <<"<!DOCTYPE html>
<html>
<head>
    <meta charset=\"UTF-8\">
    <title>EMQX Kafka Bridge API 文档</title>
    <style>
        * { box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        h1 { color: #333; }
        .api-list { background: white; border-radius: 8px; padding: 20px; }
        .api-item { border-bottom: 1px solid #eee; padding: 15px 0; }
        .api-item:last-child { border-bottom: none; }
        .method { display: inline-block; padding: 4px 8px; border-radius: 4px; font-weight: bold; margin-right: 10px; }
        .GET { background: #61affe; color: white; }
        .POST { background: #49cc90; color: white; }
        .PUT { background: #fca130; color: white; }
        .DELETE { background: #f93e3e; color: white; }
        .path { font-size: 16px; color: #333; font-family: monospace; }
        .desc { color: #666; margin-top: 5px; }
        .params { margin-top: 10px; padding: 10px; background: #f9f9f9; border-radius: 4px; font-size: 14px; }
        .params table { width: 100%; border-collapse: collapse; }
        .params td { padding: 5px; }
        .params td:first-child { font-weight: bold; width: 150px; }
        .loading { text-align: center; padding: 40px; color: #666; }
        .error { color: red; padding: 20px; }
        pre { background: #f5f5f5; padding: 10px; border-radius: 4px; overflow-x: auto; }
    </style>
</head>
<body>
    <h1>EMQX Kafka Bridge API 文档</h1>
    <div id=\"content\" class=\"api-list\">
        <div class=\"loading\">加载中...</div>
    </div>
    <script>
    async function loadApiDocs() {
        try {
            const response = await fetch('/kafka_bridge/swagger.json');
            const spec = await response.json();
            
            let html = '';
            const paths = spec.paths || {};
            
            for (const [path, methods] of Object.entries(paths)) {
                for (const [method, details] of Object.entries(methods)) {
                    const methodClass = method.toUpperCase();
                    const summary = details.summary || '';
                    const description = details.description || '';
                    const operationId = details.operationId || '';
                    
                    html += '<div class=\"api-item\">';
                    html += '<span class=\"method ' + methodClass + '\">' + methodClass + '</span>';
                    html += '<span class=\"path\">' + path + '</span>';
                    if (summary) html += '<div class=\"desc\">' + summary + '</div>';
                    if (description) html += '<div class=\"desc\">' + description + '</div>';
                    
                    // Request Body
                    if (details.requestBody) {
                        const content = details.requestBody.content;
                        if (content && content['application/json']) {
                            const schema = content['application/json'].schema;
                            html += '<div class=\"params\"><strong>Request Body:</strong><pre>' + JSON.stringify(schema, null, 2) + '</pre></div>';
                        }
                    }
                    
                    // Parameters
                    if (details.parameters && details.parameters.length > 0) {
                        html += '<div class=\"params\"><strong>Parameters:</strong><table>';
                        for (const param of details.parameters) {
                            const required = param.required ? ' (必填)' : '';
                            html += '<tr><td>' + param.name + required + '</td><td>' + (param.description || '') + ' - ' + (param.in || '') + '</td></tr>';
                        }
                        html += '</table></div>';
                    }
                    
                    // Responses
                    if (details.responses) {
                        html += '<div class=\"params\"><strong>Responses:</strong><table>';
                        for (const [code, resp] of Object.entries(details.responses)) {
                            html += '<tr><td>' + code + '</td><td>' + (resp.description || '') + '</td></tr>';
                        }
                        html += '</table></div>';
                    }
                    
                    html += '</div>';
                }
            }
            
            if (!html) {
                html = '<div class=\"error\">未找到 API 端点</div>';
            }
            
            document.getElementById('content').innerHTML = html;
        } catch (error) {
            document.getElementById('content').innerHTML = '<div class=\"error\">加载失败: ' + error.message + '</div>';
        }
    }
    loadApiDocs();
    </script>
</body>
</html>">>,
    Html.

health(_Bindings, _Params) ->
    ok_response(#{
        status => <<"running">>,
        timestamp => erlang:system_time(millisecond)
    }).

list_rules(_Bindings, Params) ->
    ParamsMap = maps:from_list(Params),
    TopicKeyword = maps:get(<<"topic">>, ParamsMap, undefined),
    Page = get_int_param(ParamsMap, <<"page">>, 1),
    Limit = get_int_param(ParamsMap, <<"limit">>, 10),
    
    Options = #{
        keyword => TopicKeyword,
        page => Page,
        limit => Limit,
        sort_by => created_at,
        sort_order => desc
    },
    
    case emqx_kafka_bridge_store:search_rules(Options) of
        {ok, Result} ->
            #{total := Total, data := Data} = Result,
            FormattedData = [format_rule(R) || R <- Data],
            ok_response(#{
                page => Page,
                limit => Limit,
                total => Total,
                rules => FormattedData
            });
        {error, Reason} ->
            error_response(500, atom_to_binary(Reason, utf8))
    end.

get_rule(Bindings, Params) ->
    ParamsMap = maps:from_list(Params),
    RawTopic = maps:get(topic, Bindings, maps:get(<<"topic">>, ParamsMap, undefined)),
    Decoded = unicode:characters_to_binary(http_uri:decode(unicode:characters_to_list(RawTopic))),
    %% 兼容：把空格还原为 +（浏览器地址栏不会自动编码 +）
    Topic = bin_replace(Decoded, <<" ">>, <<"+">>),
    case Topic of
        undefined ->
            error_response(400, <<"Missing topic parameter">>);
        _ ->
            case emqx_kafka_bridge_store:get_rule_by_topic(Topic) of
                {ok, Rule} ->
                    ok_response(format_rule(Rule));
                {error, not_found} ->
                    error_response(404, <<"Rule not found">>)
            end
    end.

add_rule(_Bindings, Params) ->
    ParamsMap = maps:from_list(Params),
    MqttTopic = maps:get(<<"mqtt_topic">>, ParamsMap, undefined),
    KafkaTopic = maps:get(<<"kafka_topic">>, ParamsMap, undefined),
    case {MqttTopic, KafkaTopic} of
        {undefined, _} ->
            error_response(400, <<"Missing mqtt_topic">>);
        {_, undefined} ->
            error_response(400, <<"Missing kafka_topic">>);
        _ ->
            %% 检查 mqtt_topic 是否已存在（主键唯一性）
            case emqx_kafka_bridge_store:get_rule_by_topic(MqttTopic) of
                {ok, _} ->
                    error_response(409, <<"Rule for this mqtt_topic already exists">>);
                {error, not_found} ->
                    Rule = #kafka_forward_rule{
                        mqtt_topic = MqttTopic,
                        kafka_topic = KafkaTopic,
                        qos = case maps:get(<<"qos">>, ParamsMap, 1) of null -> 1; V when is_number(V) -> V; _ -> 1 end,
                        payload_format = binary_to_existing_atom(maps:get(<<"payload_format">>, ParamsMap, <<"json">>), utf8),
                        payload_template = maps:get(<<"payload_template">>, ParamsMap, undefined),
                        kafka_key = binary_to_existing_atom(maps:get(<<"kafka_key">>, ParamsMap, <<"topic">>), utf8),
                        enabled = maps:get(<<"enabled">>, ParamsMap, true),
                        description = maps:get(<<"description">>, ParamsMap, <<>>),
                        created_at = erlang:system_time(second),
                        updated_at = erlang:system_time(second)
                    },
                    case emqx_kafka_bridge_store:add_rule(Rule) of
                        {ok, NewRule} ->
                            emqx_kafka_bridge_store:save_to_file(),
                            emqx_kafka_bridge_rule_cache:refresh(),
                            ok_response(format_rule(NewRule));
                        {error, Reason} ->
                            error_response(500, atom_to_binary(Reason, utf8))
                    end
            end
    end.

update_rule(Bindings, Params) ->
    ParamsMap = maps:from_list(Params),
    RawTopic = maps:get(topic, Bindings, maps:get(<<"mqtt_topic">>, ParamsMap, undefined)),
    Decoded = unicode:characters_to_binary(http_uri:decode(unicode:characters_to_list(RawTopic))),
    MqttTopic = bin_replace(Decoded, <<" ">>, <<"+">>),
    case MqttTopic of
        undefined ->
            error_response(400, <<"Missing mqtt_topic">>);
        _ ->
            %% 先查询记录是否存在
            case emqx_kafka_bridge_store:get_rule_by_topic(MqttTopic) of
                {ok, OldRule} ->
                    Updates = #kafka_forward_rule{
                        mqtt_topic = MqttTopic,
                        kafka_topic = maps:get(<<"kafka_topic">>, ParamsMap, OldRule#kafka_forward_rule.kafka_topic),
                        qos = case maps:get(<<"qos">>, ParamsMap, null) of null -> OldRule#kafka_forward_rule.qos; V -> V end,
                        payload_format = OldRule#kafka_forward_rule.payload_format,
                        payload_template = maps:get(<<"payload_template">>, ParamsMap, OldRule#kafka_forward_rule.payload_template),
                        kafka_key = OldRule#kafka_forward_rule.kafka_key,
                        enabled = maps:get(<<"enabled">>, ParamsMap, OldRule#kafka_forward_rule.enabled),
                        description = maps:get(<<"description">>, ParamsMap, OldRule#kafka_forward_rule.description),
                        created_at = OldRule#kafka_forward_rule.created_at,
                        updated_at = erlang:system_time(second)
                    },
                    case emqx_kafka_bridge_store:update_rule(MqttTopic, Updates) of
                        {ok, UpdatedRule} ->
                            emqx_kafka_bridge_store:save_to_file(),
                            emqx_kafka_bridge_rule_cache:refresh(),
                            ok_response(format_rule(UpdatedRule));
                        {error, Reason} ->
                            error_response(500, atom_to_binary(Reason, utf8))
                    end;
                {error, not_found} ->
                    error_response(404, <<"Rule not found">>)
            end
    end.

delete_rule(Bindings, Params) ->
    ParamsMap = maps:from_list(Params),
    RawTopic = maps:get(topic, Bindings, maps:get(<<"mqtt_topic">>, ParamsMap, undefined)),
    Decoded = unicode:characters_to_binary(http_uri:decode(unicode:characters_to_list(RawTopic))),
    MqttTopic = bin_replace(Decoded, <<" ">>, <<"+">>),
    case MqttTopic of
        undefined ->
            error_response(400, <<"Missing mqtt_topic">>);
        _ ->
            %% 根据 mqtt_topic 查询记录是否存在
            case emqx_kafka_bridge_store:get_rule_by_topic(MqttTopic) of
                {ok, _Rule} ->
                    case emqx_kafka_bridge_store:delete_rule(MqttTopic) of
                        ok ->
                            emqx_kafka_bridge_store:save_to_file(),
                            emqx_kafka_bridge_rule_cache:refresh(),
                            ok_response(#{})
                            ;
                        {error, Reason} ->
                            error_response(500, atom_to_binary(Reason, utf8))
                    end;
                {error, not_found} ->
                    error_response(404, <<"Rule not found">>)
            end
    end.

%% ===================================================================
%% Internal Functions
%% ===================================================================

format_rule(Rule) ->
    #{
        mqtt_topic => Rule#kafka_forward_rule.mqtt_topic,
        kafka_topic => Rule#kafka_forward_rule.kafka_topic,
        qos => case Rule#kafka_forward_rule.qos of undefined -> 1; Q when is_integer(Q) -> Q; _ -> 1 end,
        payload_format => atom_to_binary(Rule#kafka_forward_rule.payload_format, utf8),
        kafka_key => atom_to_binary(Rule#kafka_forward_rule.kafka_key, utf8),
        enabled => Rule#kafka_forward_rule.enabled,
        description => Rule#kafka_forward_rule.description,
        created_at => format_timestamp(Rule#kafka_forward_rule.created_at),
        updated_at => format_timestamp(Rule#kafka_forward_rule.updated_at)
    }.

%% 格式化时间戳为 yyyy-MM-dd HH:mm:ss（北京时间 UTC+8）
format_timestamp(Timestamp) when is_integer(Timestamp) ->
    %% 转换为北京时间 (UTC+8 = 28800 秒)
    LocalTimestamp = Timestamp + 28800,
    {{Year, Month, Day}, {Hour, Min, Sec}} = calendar:system_time_to_local_time(LocalTimestamp, second),
    iolist_to_binary(io_lib:format("~4.10.0b-~2.10.0b-~2.10.0b ~2.10.0b:~2.10.0b:~2.10.0b", 
        [Year, Month, Day, Hour, Min, Sec]));
format_timestamp(_) ->
    <<"">>.

get_int_param(ParamsMap, Key, Default) ->
    case maps:get(Key, ParamsMap, Default) of
        Bin when is_binary(Bin) ->
            try binary_to_integer(Bin) catch _:_ -> Default end;
        Int when is_integer(Int) -> Int;
        _ -> Default
    end.

%% 字符串替换（binary 版）
bin_replace(Bin, From, To) ->
    bin_replace(Bin, From, To, []).
bin_replace(<<>>, _, _, Acc) ->
    iolist_to_binary(lists:reverse(Acc));
bin_replace(Bin, From, To, Acc) ->
    case binary:match(Bin, From) of
        nomatch -> iolist_to_binary(lists:reverse([Bin | Acc]));
        {Pos, Len} ->
            <<Prefix:Pos/binary, _:Len/binary, Suffix/binary>> = Bin,
            bin_replace(Suffix, From, To, [To, Prefix | Acc])
    end.

%% ===================================================================
%% 统一返回格式
%% ===================================================================
%% 成功响应：{code: 0, message: "ok", data: {...}}
ok_response(Data) ->
    {200, #{
        code => 0,
        message => <<"success">>,
        data => Data
    }}.

%% 错误响应：{code: X, message: "...", data: {}}
error_response(Code, Message) when is_integer(Code) ->
    MsgBin = if is_binary(Message) -> Message; true -> list_to_binary(io_lib:format("~p", [Message])) end,
    {Code, #{
        code => Code,
        message => MsgBin,
        data => #{}
    }}.