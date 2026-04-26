-module('SagaHttp.bridge').
-export([
    listen/2,
    accept/1,
    connect/3,
    recv/3,
    send/2,
    close/1,
    local_port/1,
    decode_request_line/1,
    decode_header/1,
    setopts/2,
    peername/1
]).

listen(Port, Backlog) ->
    case
        gen_tcp:listen(Port, [
            binary,
            {active, false},
            {reuseaddr, true},
            {backlog, Backlog},
            {packet, raw}
        ])
    of
        {ok, Socket} -> {ok, Socket};
        {error, Reason} -> {error, atom_to_binary(Reason)}
    end.

accept(ListenSocket) ->
    case gen_tcp:accept(ListenSocket) of
        {ok, Socket} -> {ok, Socket};
        {error, Reason} -> {error, atom_to_binary(Reason)}
    end.

connect(Host, Port, Timeout) ->
    HostStr = binary_to_list(Host),
    case gen_tcp:connect(HostStr, Port, [binary, {active, false}, {packet, raw}], Timeout) of
        {ok, Socket} -> {ok, Socket};
        {error, Reason} -> {error, atom_to_binary(Reason)}
    end.

local_port(ListenSocket) ->
    case inet:port(ListenSocket) of
        {ok, Port} -> {ok, Port};
        {error, Reason} -> {error, atom_to_binary(Reason)}
    end.

recv(Socket, Length, Timeout) ->
    case gen_tcp:recv(Socket, Length, Timeout) of
        {ok, Data} -> {ok, Data};
        {error, Reason} -> {error, atom_to_binary(Reason)}
    end.

send(Socket, Data) ->
    case gen_tcp:send(Socket, Data) of
        ok -> {ok, unit};
        {error, Reason} -> {error, atom_to_binary(Reason)}
    end.

close(Socket) ->
    gen_tcp:close(Socket),
    unit.

% http_bin parses the request line (GET /path HTTP/1.1)
decode_request_line(Data) ->
    case erlang:decode_packet(http_bin, Data, []) of
        {ok, {http_request, Method, {abs_path, Path}, {Major, Minor}}, Rest} ->
            MethodBin =
                if
                    is_atom(Method) -> atom_to_binary(Method);
                    is_binary(Method) -> Method;
                    true -> iolist_to_binary(io_lib:format("~p", [Method]))
                end,
            {ok, {MethodBin, Path, {Major, Minor}, Rest}};
        {ok, {http_error, _Line}, _Rest} ->
            {error, <<"parse_error">>};
        {more, _} ->
            {error, <<"incomplete">>};
        {error, _Reason} ->
            {error, <<"parse_error">>}
    end.

% httph_bin parses headers and end-of-headers
decode_header(Data) ->
    case erlang:decode_packet(httph_bin, Data, []) of
        {ok, {http_header, _, Name, _, Value}, Rest} ->
            NameBin =
                if
                    is_atom(Name) -> atom_to_binary(Name);
                    is_binary(Name) -> Name;
                    true -> iolist_to_binary(io_lib:format("~p", [Name]))
                end,
            {ok, {sagahttp_http_Header, NameBin, Value, Rest}};
        {ok, http_eoh, Rest} ->
            {ok, {sagahttp_http_Done, Rest}};
        {ok, {http_error, _Line}, _Rest} ->
            {error, <<"parse_error">>};
        {more, _} ->
            {error, <<"incomplete">>};
        {error, _Reason} ->
            {error, <<"parse_error">>}
    end.

setopts(Socket, Opts) ->
    inet:setopts(Socket, Opts).

peername(Socket) ->
    case inet:peername(Socket) of
        {ok, {Addr, Port}} ->
            AddrStr = iolist_to_binary(inet:ntoa(Addr)),
            {ok, {AddrStr, Port}};
        {error, Reason} ->
            {error, atom_to_binary(Reason)}
    end.
