-module(emqx_kafka_bridge_static).
-export([init/2]).

init(Req, {File, ContentType}) ->
    PrivDir = code:priv_dir(emqx_kafka_bridge_v4),
    FullPath = filename:join([PrivDir, "swagger-dist", File]),
    case file:read_file(FullPath) of
        {ok, Bin} ->
            Req2 = cowboy_req:reply(200, #{
                <<"content-type">> => ContentType,
                <<"cache-control">> => <<"public, max-age=86400">>
            }, Bin, Req),
            {ok, Req2, undefined};
        {error, _} ->
            Req2 = cowboy_req:reply(404, #{
                <<"content-type">> => <<"text/plain">>
            }, <<"Not found: ", File/binary>>, Req),
            {ok, Req2, undefined}
    end.