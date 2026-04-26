-module('SagaHttp.bridge').
-export([
    listen/2,
    accept/1,
    connect/3,
    recv/3,
    send/2,
    close/1,
    local_port/1,
    decode_request_line/2,
    decode_header/2,
    setopts/2,
    peername/1,
    current_http_date/0
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

% http_bin parses the request line (GET /path HTTP/1.1).
% MaxSize bounds the packet body length per decode_packet's packet_size
% option; lines exceeding it return {error, _} which we map to BadRequest.
decode_request_line(Data, MaxSize) ->
    case erlang:decode_packet(http_bin, Data, [{packet_size, MaxSize}]) of
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
decode_header(Data, MaxSize) ->
    case erlang:decode_packet(httph_bin, Data, [{packet_size, MaxSize}]) of
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

%% IMF-fixdate per RFC 7231 §7.1.1.1, e.g. "Sun, 06 Nov 1994 08:49:37 GMT".
%% Self-contained (uses only `calendar`) so no extra OTP apps need to be loaded.
current_http_date() ->
    {{Year, Month, Day}, {Hour, Min, Sec}} = calendar:universal_time(),
    DayName = day_name(calendar:day_of_the_week(Year, Month, Day)),
    MonthName = month_name(Month),
    iolist_to_binary(io_lib:format(
        "~s, ~2..0w ~s ~4..0w ~2..0w:~2..0w:~2..0w GMT",
        [DayName, Day, MonthName, Year, Hour, Min, Sec]
    )).

day_name(1) -> "Mon";
day_name(2) -> "Tue";
day_name(3) -> "Wed";
day_name(4) -> "Thu";
day_name(5) -> "Fri";
day_name(6) -> "Sat";
day_name(7) -> "Sun".

month_name(1)  -> "Jan";
month_name(2)  -> "Feb";
month_name(3)  -> "Mar";
month_name(4)  -> "Apr";
month_name(5)  -> "May";
month_name(6)  -> "Jun";
month_name(7)  -> "Jul";
month_name(8)  -> "Aug";
month_name(9)  -> "Sep";
month_name(10) -> "Oct";
month_name(11) -> "Nov";
month_name(12) -> "Dec".
