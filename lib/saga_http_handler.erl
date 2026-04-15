-module(saga_http_handler).
-export([init/2]).

init(Req, #{handler := Handler}) ->
    Method = cowboy_req:method(Req),
    Path = cowboy_req:path(Req),
    SagaReq = {sagahttp_Request, Method, Path},
    SagaResp = Handler(SagaReq),
    {sagahttp_Response, Status, Body} = SagaResp,
    Req2 = cowboy_req:reply(Status, #{<<"content-type">> => <<"text/plain">>}, Body, Req),
    {ok, Req2, #{}}.
