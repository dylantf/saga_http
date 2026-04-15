-module('SagaHttp.bridge').
-export([start/2]).

start(Port, Handler) ->
    {ok, _} = application:ensure_all_started(cowboy),
    Dispatch = cowboy_router:compile([
        {'_', [
            {'_', saga_http_handler, #{handler => Handler}}
        ]}
    ]),
    {ok, _} = cowboy:start_clear(http, [{port, Port}], #{
        env => #{dispatch => Dispatch}
    }),
    unit.
